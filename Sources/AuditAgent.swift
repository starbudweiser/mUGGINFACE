// mUGGINFACE — audit assisté par un agent IA : analyse rédigée, plan de mise à jour, exécution sauvegardée et retour arrière.
import Foundation
import AppKit

struct UpdatePlan: Codable, Identifiable {
    enum Status: String, Codable { case prepared, executed, failed, rolledBack }
    struct Backup: Codable { var original: String; var backup: String? }   // backup nil = le fichier n'existait pas avant le plan
    var id: String
    var date: Date
    var text: String
    var targets: [String]
    var status: Status = .prepared
    var backups: [Backup] = []
    var result: String?
    var downloads: [String] = []
}

@MainActor
final class AuditAgentStore: ObservableObject {
    static let shared = AuditAgentStore()
    @Published private(set) var analysis: String?
    @Published private(set) var analysisDate: Date?
    @Published private(set) var analysisAgent: String?
    @Published private(set) var plans: [UpdatePlan] = []
    @Published var draftPlan = ""
    @Published var draftTargets: Set<String> = []
    @Published private(set) var busyAnalysis = false
    @Published private(set) var busyPlan = false
    @Published private(set) var busyExec = false
    @Published var error: String?
    @Published var notice: String?

    private var prefs: Prefs { Prefs.shared }
    private var agent: AgentBridge { AgentBridge.shared }
    private var root: URL { AppModel.dataDir.appendingPathComponent("plans") }
    private var file: URL { AppModel.dataDir.appendingPathComponent("audit-agent.json") }
    private struct Saved: Codable { var analysis: String?; var analysisDate: Date?; var analysisAgent: String?; var plans: [UpdatePlan] }

    init() {
        if let d = try? Data(contentsOf: file) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            if let s = try? dec.decode(Saved.self, from: d) { analysis = s.analysis; analysisDate = s.analysisDate; analysisAgent = s.analysisAgent; plans = s.plans }
        }
    }

    private func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(Saved(analysis: analysis, analysisDate: analysisDate, analysisAgent: analysisAgent, plans: plans)) { try? d.write(to: file, options: .atomic) }
    }

    var agentName: String {
        switch agent.kind { case .claudeCode: return "Claude Code"; case .claudeAPI: return L.t("agent.api"); case .custom: return L.t("agent.custom") }
    }
    var canExecute: Bool { agent.kind != .claudeAPI }
    func planDir(_ id: String) -> URL { root.appendingPathComponent(id) }
    var evolutionFile: String { (prefs.modelsPath as NSString).appendingPathComponent("WORKFLOW-EVOLUTION.md") }

    // MARK: Contexte envoyé à l'agent (aucune donnée personnelle : modèles, tailles, matériel)

    private func auditText() -> String {
        let audit = AuditStore.shared, app = AppModel.shared
        var lines: [String] = []
        for e in audit.entries {
            var s = "- \(e.installed.id) [\(e.domain.map { L.t($0.titleKey) } ?? "?")] \(String(format: "%.1f", e.installed.sizeGB)) GB, source \(e.installed.source)"
            if let sc = e.score { s += ", estimated score \(String(format: "%.1f", sc))" }
            s += ", verdict \(e.verdict.rawValue)"
            if e.verdict == .better, let b = e.best {
                s += "; best candidate \(b.model.id) (+\(Int((e.gain ?? 0) * 100))% estimated, \(L.t(b.fit.level.tagKey))"
                if let r = b.fit.ramGB { s += ", RAM \(String(format: "%.0f", r)) GB" }
                s += ", license \(b.model.license ?? "unknown"), \(b.model.likes) likes)"
            }
            if let c = e.commonEval { s += "; measured \(c.name): installed \(String(format: "%.2f", c.mine)) vs candidate \(String(format: "%.2f", c.best))" }
            lines.append(s)
        }
        let c = audit.current, p = audit.previous
        var head = "Mac: \(app.hw.chip), \(Int(app.hw.memGB)) GB memory (\(Int(app.usableGB)) GB usable for a model), \(Int(app.hw.diskFreeGB)) GB free disk."
        if let c { head += " Workshop index: \(Int(c.index))%" + (p.map { " (previous audit: \(Int($0.index))%)" } ?? "") + "." }
        return head + "\n" + lines.joined(separator: "\n")
    }

    // MARK: Analyse

    func analyze() async {
        guard !busyAnalysis, !AuditStore.shared.entries.isEmpty else { return }
        busyAnalysis = true; error = nil
        defer { busyAnalysis = false }
        // Les consignes de l'agent sont en anglais (l'agent répond dans la langue de l'application).
        let prompt = """
        You are an AI model advisor. Below is an audit of the AI models installed on a user's Mac, compared with the best compatible candidates from Hugging Face. Scores marked "estimated" come from popularity, size and freshness (not real benchmarks); "measured" values are benchmarks published by the model authors.
        Write the analysis in \(L.languageName), around 350 words, plain prose with short bold titles (no markdown headings, no tables, no commands). Cover: 1) overall state of the setup, 2) the priorities in order (what to upgrade first and why), 3) risks and caveats (license, memory fit, uncertain estimates, quality differences the numbers cannot show), 4) what to leave alone, 5) the expected benefit for the user's daily workflow. Be honest when the data is thin. Do not run anything.

        \(auditText())
        """
        do {
            let text = try await agent.run(prompt: prompt, allowTools: false, timeout: 300)
            analysis = text; analysisDate = Date(); analysisAgent = agentName
            save()
        } catch { self.error = error.localizedDescription }
    }

    // MARK: Plan

    var upgradeCandidates: [AuditEntry] { AuditStore.shared.entries.filter { $0.verdict == .better && $0.best != nil } }

    func preparePlan() async {
        guard !busyPlan else { return }
        let targets = upgradeCandidates.filter { draftTargets.contains($0.id) }
        guard !targets.isEmpty else { return }
        busyPlan = true; error = nil
        defer { busyPlan = false }
        let items = targets.map { e -> String in
            let b = e.best!
            return "- replace \(e.installed.id) by \(b.model.id) (domain \(e.domain.map { L.t($0.titleKey) } ?? "?"), about \(b.fit.ramGB.map { String(format: "%.0f GB RAM", $0) } ?? "unknown RAM"))"
        }.joined(separator: "\n")
        let files = prefs.auditInstr.isEmpty ? "(none)" : prefs.auditInstr.joined(separator: "\n")
        let prompt = """
        You prepare a model update plan for a user's Mac. Do NOT execute anything: write the plan only, in \(L.languageName), as a numbered list.
        Requested replacements:
        \(items)
        Workflow instruction files the plan may update (they are backed up automatically before execution):
        \(files)
        Models folder: \(prefs.modelsPath)
        Rules the plan must follow: new models are installed side by side in the models folder, never overwriting or deleting an existing model; each new model is tested before any reference is changed; references in the instruction files are changed only after a successful test (state which lines or sections, old → new); a dated entry is appended to \(evolutionFile) describing what changed, why, and how to revert; check free disk space first (\(Int(AppModel.shared.hw.diskFreeGB)) GB free).
        For each replacement give: download step, test step with a short command, the instruction-file changes, and the revert note. Finish with a one-paragraph summary of the expected workflow improvement. Context (analysis, if any): \(analysis ?? "none")

        Audit data:
        \(auditText())
        """
        do { draftPlan = try await agent.run(prompt: prompt, allowTools: false, timeout: 300) }
        catch { self.error = error.localizedDescription }
    }

    // MARK: Exécution (sauvegarde automatique avant)

    private func makeBackups(_ id: String) -> [UpdatePlan.Backup] {
        let fm = FileManager.default
        let dir = planDir(id).appendingPathComponent("backup")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [UpdatePlan.Backup] = []
        for (i, raw) in (prefs.auditInstr + [evolutionFile]).enumerated() {
            let src = (raw as NSString).expandingTildeInPath
            guard fm.fileExists(atPath: src) else { out.append(.init(original: src, backup: nil)); continue }
            let dst = dir.appendingPathComponent("\(i)-" + (src as NSString).lastPathComponent)
            do { try fm.copyItem(atPath: src, toPath: dst.path); out.append(.init(original: src, backup: dst.path)) }
            catch { out.append(.init(original: src, backup: nil)) }
        }
        return out
    }

    func execute() async {
        guard !busyExec, canExecute, !draftPlan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busyExec = true; error = nil; notice = nil
        defer { busyExec = false }
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
        let id = df.string(from: Date())
        try? FileManager.default.createDirectory(at: planDir(id), withIntermediateDirectories: true)
        var plan = UpdatePlan(id: id, date: Date(), text: draftPlan, targets: Array(draftTargets))
        plan.backups = makeBackups(id)
        let journal = planDir(id).appendingPathComponent("journal.json")
        try? Data("{\"downloads\":[],\"notes\":[]}".utf8).write(to: journal)
        plans.insert(plan, at: 0); save()

        let instr = prefs.auditInstr.map { ($0 as NSString).expandingTildeInPath }
        var rules = ["Edit(/\(evolutionFile))", "Edit(/\(journal.path))"]   // « Edit » couvre aussi l'écriture de fichiers
        var dirs = [planDir(id).path, prefs.modelsPath]
        for f in instr {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: f, isDirectory: &isDir)
            rules.append(isDir.boolValue ? "Edit(/\(f)/**)" : "Edit(/\(f))")
            dirs.append(isDir.boolValue ? f : (f as NSString).deletingLastPathComponent)
        }
        let prompt = """
        Execute the model update plan below on the user's Mac. Answer in \(L.languageName).
        STRICT RULES (the user can roll everything back; keep it that way):
        1. Do only what the plan says. Modify only these files: \(instr.isEmpty ? "(none)" : instr.joined(separator: ", ")) and \(evolutionFile). The app already saved backups in \(planDir(id).path)/backup: never touch that folder.
        2. Never delete, move or overwrite an existing model. Install each new model in its own folder inside \(prefs.modelsPath) (e.g. with `hf download <id> --local-dir <models folder>/<name>`).
        3. Before downloading, check free disk space. Test each new model with a short run before changing any reference; if a test fails, change nothing for that model and say so.
        4. The journal \(journal.path) is JSON {"downloads":[absolute paths of every folder or file you created],"notes":[short strings]}. Update it right after each download, before anything else.
        5. When done, append a dated entry to \(evolutionFile) (create it if missing): what changed, old → new, results of the tests, and how to revert.
        6. End with a short report: done, skipped, problems.

        PLAN:
        \(plan.text)
        """
        do {
            let out = try await agent.run(prompt: prompt, allowTools: true, extraRules: rules, addDirs: dirs, timeout: 2700)
            finish(id, status: .executed, result: out)
        } catch {
            self.error = error.localizedDescription
            finish(id, status: .failed, result: error.localizedDescription)
        }
    }

    private func finish(_ id: String, status: UpdatePlan.Status, result: String) {
        guard let i = plans.firstIndex(where: { $0.id == id }) else { return }
        plans[i].status = status; plans[i].result = result
        plans[i].downloads = readJournal(id).downloads
        save()
    }

    func readJournal(_ id: String) -> (downloads: [String], notes: [String]) {
        guard let d = try? Data(contentsOf: planDir(id).appendingPathComponent("journal.json")),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return ([], []) }
        return ((j["downloads"] as? [String]) ?? [], (j["notes"] as? [String]) ?? [])
    }

    // MARK: Retour arrière

    private func allowedRoots() -> [String] {
        let home = NSHomeDirectory()
        return ([prefs.modelsPath, home + "/.cache/huggingface/hub"] + prefs.auditDirs.map { ($0 as NSString).expandingTildeInPath }).map { URL(fileURLWithPath: $0).standardized.path }
    }
    private func isUnder(_ path: String, _ roots: [String]) -> Bool {
        let p = URL(fileURLWithPath: path).standardized.path
        return roots.contains { p == $0 || p.hasPrefix($0 + "/") }
    }

    /// Restaure les fichiers sauvegardés (la version actuelle est gardée à côté) et met à la corbeille ce que le plan a téléchargé.
    func rollback(_ id: String) {
        guard let i = plans.firstIndex(where: { $0.id == id }) else { return }
        let fm = FileManager.default
        let plan = plans[i]
        var done: [String] = [], skipped: [String] = []
        let kept = planDir(id).appendingPathComponent("replaced")
        try? fm.createDirectory(at: kept, withIntermediateDirectories: true)
        let allowedFiles = (prefs.auditInstr + [evolutionFile]).map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardized.path }
        for (n, b) in plan.backups.enumerated() {
            let orig = URL(fileURLWithPath: b.original).standardized.path
            guard allowedFiles.contains(orig) else { skipped.append(b.original); continue }
            if fm.fileExists(atPath: orig) {
                let side = kept.appendingPathComponent("\(n)-" + (orig as NSString).lastPathComponent)
                try? fm.removeItem(at: side)
                try? fm.moveItem(atPath: orig, toPath: side.path)
            }
            if let bk = b.backup, fm.fileExists(atPath: bk) {
                do { try fm.copyItem(atPath: bk, toPath: orig); done.append((orig as NSString).lastPathComponent) }
                catch { skipped.append(orig) }
            } else { done.append((orig as NSString).lastPathComponent + " ↩︎") }   // fichier créé par le plan : retiré
        }
        let roots = allowedRoots()
        for path in Set(plan.downloads + readJournal(id).downloads) {
            guard isUnder(path, roots), fm.fileExists(atPath: path) else { skipped.append(path); continue }
            do { try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil); done.append((path as NSString).lastPathComponent) }
            catch { skipped.append(path) }
        }
        plans[i].status = .rolledBack
        plans[i].result = (plan.result ?? "")
        save()
        notice = L.t("audit.plan.rollback.done", done.isEmpty ? "—" : done.joined(separator: ", ")) + (skipped.isEmpty ? "" : "\n" + L.t("audit.plan.rollback.skipped", skipped.joined(separator: ", ")))
    }

    func reveal(_ id: String) { NSWorkspace.shared.activateFileViewerSelecting([planDir(id)]) }
}
