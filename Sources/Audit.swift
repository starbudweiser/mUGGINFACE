// mUGGINFACE — audit des modèles installés : détection sur le Mac, comparaison au catalogue, historique daté.
import Foundation

struct InstalledModel: Identifiable, Codable, Hashable {
    var id: String          // identifiant Hub (auteur/nom) ou nom local
    var source: String      // hf, app, ollama, lmstudio, folder
    var path: String
    var sizeGB: Double
    var hubLike: Bool       // l'identifiant ressemble à un dépôt Hub
}

enum InstalledScanner {
    private static let weightExts: Set<String> = ["safetensors", "gguf", "bin", "pt", "pth", "npz"]

    static func dirSize(_ url: URL) -> Double {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        for case let u as URL in en {
            if let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true { total += Int64(v.totalFileAllocatedSize ?? 0) }
        }
        return Double(total) / 1_073_741_824
    }

    /// Taille d'un modèle du cache Hub : les fichiers de « snapshots » sont des liens vers « blobs », éventuellement partagés ; on suit les liens sans compter deux fois.
    static func linkedSize(_ url: URL) -> Double {
        var seen = Set<String>(), total: Int64 = 0
        guard let en = FileManager.default.enumerator(atPath: url.path) else { return 0 }
        for case let rel as String in en {
            let full = url.appendingPathComponent(rel).resolvingSymlinksInPath()
            guard seen.insert(full.path).inserted, let a = try? FileManager.default.attributesOfItem(atPath: full.path),
                  (a[.type] as? FileAttributeType) == .typeRegular else { continue }
            total += (a[.size] as? NSNumber)?.int64Value ?? 0
        }
        return Double(total) / 1_073_741_824
    }

    private static func subdirs(_ path: String) -> [URL] {
        let u = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let list = (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return list.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// Détecte les modèles : cache Hugging Face, dossier de l'appli, Ollama, LM Studio et dossiers ajoutés.
    static func scan(appDir: String, appDownloads: [String: String], extraDirs: [String]) -> [InstalledModel] {
        var out: [InstalledModel] = []
        let home = NSHomeDirectory()
        let env = ProcessInfo.processInfo.environment

        // Cache Hugging Face : models--auteur--nom
        var hubDirs = [env["HUGGINGFACE_HUB_CACHE"], env["HF_HOME"].map { $0 + "/hub" }, home + "/.cache/huggingface/hub"].compactMap { $0 }
        hubDirs = Array(Set(hubDirs))
        for d in hubDirs {
            for u in subdirs(d) where u.lastPathComponent.hasPrefix("models--") {
                let parts = u.lastPathComponent.dropFirst(8).components(separatedBy: "--")
                guard parts.count >= 2 else { continue }
                let size = linkedSize(u)
                guard size > 0.005 else { continue }
                out.append(InstalledModel(id: parts.joined(separator: "/"), source: "hf", path: u.path, sizeGB: size, hubLike: true))
            }
        }

        // Dossier de l'appli : un sous-dossier par modèle téléchargé
        for u in subdirs(appDir) {
            let size = linkedSize(u)
            guard size > 0.005 else { continue }
            let id = appDownloads[u.path] ?? u.lastPathComponent
            out.append(InstalledModel(id: id, source: "app", path: u.path, sizeGB: size, hubLike: id.contains("/")))
        }

        // LM Studio : éditeur/dépôt
        for root in [home + "/.lmstudio/models", home + "/.cache/lm-studio/models"] {
            for pub in subdirs(root) {
                for repo in subdirs(pub.path) {
                    let size = linkedSize(repo)
                    guard size > 0.005 else { continue }
                    out.append(InstalledModel(id: pub.lastPathComponent + "/" + repo.lastPathComponent, source: "lmstudio", path: repo.path, sizeGB: size, hubLike: true))
                }
            }
        }

        // Ollama : manifestes registry/espace/nom/étiquette
        let man = home + "/.ollama/models/manifests"
        if let en = FileManager.default.enumerator(at: URL(fileURLWithPath: man), includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let u as URL in en where (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let rel = u.path.replacingOccurrences(of: man + "/", with: "").split(separator: "/").map(String.init)
                guard rel.count >= 4, let data = try? Data(contentsOf: u),
                      let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let layers = j["layers"] as? [[String: Any]] else { continue }
                let bytes = layers.compactMap { ($0["size"] as? NSNumber)?.doubleValue }.reduce(0, +)
                let name = rel[rel.count - 2], tag = rel[rel.count - 1], ns = rel[rel.count - 3]
                out.append(InstalledModel(id: (ns == "library" ? "" : ns + "/") + name + ":" + tag, source: "ollama", path: u.path, sizeGB: bytes / 1_073_741_824, hubLike: false))
            }
        }

        // Dossiers choisis par l'utilisateur : chaque sous-dossier est un modèle (ou le dossier lui-même s'il contient des poids)
        for d in extraDirs {
            let root = URL(fileURLWithPath: (d as NSString).expandingTildeInPath)
            let direct = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            let candidates: [URL] = direct.contains { weightExts.contains(($0 as NSString).pathExtension.lowercased()) } ? [root] : subdirs(root.path)
            for u in candidates {
                let size = linkedSize(u)
                guard size > 0.05 else { continue }
                out.append(InstalledModel(id: u.lastPathComponent, source: "folder", path: u.path, sizeGB: size, hubLike: false))
            }
        }

        // Dédoublonnage par identifiant (le cache Hub prime)
        var seen = Set<String>(), res: [InstalledModel] = []
        for m in out.sorted(by: { $0.source == "hf" && $1.source != "hf" }) where seen.insert(m.id.lowercased()).inserted { res.append(m) }
        return res.sorted { $0.sizeGB > $1.sizeGB }
    }
}

// MARK: - Résultats

enum AuditVerdict: String, Codable { case upToDate, better, unknown }

struct AuditEntry: Identifiable {
    var installed: InstalledModel
    var model: Model?
    var domain: Domain?
    var score: Double?
    var best: Row?
    var gain: Double?                       // gain estimé du meilleur candidat (0,25 = +25 %)
    var verdict: AuditVerdict
    var evals: [Hub.Eval] = []
    var bestEvals: [Hub.Eval] = []
    var id: String { installed.id }
    /// Premier benchmark public publié à la fois pour le modèle installé et son meilleur candidat.
    var commonEval: (name: String, mine: Double, best: Double)? {
        for e in evals {
            if let b = bestEvals.first(where: { $0.dataset == e.dataset && $0.task == e.task }) {
                let short = (e.dataset.split(separator: "/").last.map(String.init) ?? e.dataset) + (e.task.isEmpty ? "" : " · " + e.task)
                return (short, e.value, b.value)
            }
        }
        return nil
    }
}

struct AuditSnapshot: Codable, Identifiable {
    struct Item: Codable { var id: String; var domain: String?; var score: Double?; var bestID: String?; var bestScore: Double? }
    var date: Date
    var items: [Item]
    var index: Double            // 0–100 : part moyenne du meilleur candidat atteinte par les modèles installés
    var upToDate: Int
    var better: Int
    var unknown: Int
    var totalGB: Double
    var id: Date { date }
}

@MainActor
final class AuditStore: ObservableObject {
    static let shared = AuditStore()
    @Published private(set) var entries: [AuditEntry] = []
    @Published private(set) var history: [AuditSnapshot] = []
    @Published private(set) var running = false
    @Published private(set) var lastRun: Date?

    private var file: URL { AppModel.dataDir.appendingPathComponent("audit.json") }
    private struct Saved: Codable { var history: [AuditSnapshot] }
    private var infoCache: [String: (model: Model, domain: Domain?, evals: [Hub.Eval])] = [:]

    init() {
        if let d = try? Data(contentsOf: file) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            if let s = try? dec.decode(Saved.self, from: d) { history = s.history; lastRun = s.history.last?.date }
        }
    }

    private func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(Saved(history: history)) { try? d.write(to: file, options: .atomic) }
    }

    var current: AuditSnapshot? { history.last }
    var previous: AuditSnapshot? { history.count >= 2 ? history[history.count - 2] : nil }

    // MARK: Noms et tâches

    private static let quantWords: Set<String> = ["4bit", "8bit", "6bit", "3bit", "2bit", "bf16", "fp16", "fp8", "mlx", "gguf", "int4", "int8", "q4", "q8", "q2", "q3", "q5", "q6", "nvfp4", "awq", "gptq", "instruct", "it"]
    static func baseName(_ id: String) -> String {
        let n = (id.split(separator: "/").last.map(String.init) ?? id).lowercased()
        let toks = n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { !quantWords.contains($0) && !$0.hasPrefix("q4") && !$0.hasPrefix("q8") }
        return toks.joined()
    }
    /// Sous-tâches voisines qui partagent une étiquette de pipeline mais ne se remplacent pas (diarisation, détection de voix…).
    private static let niche = ["diariz", "segmentation", "vad", "pii", "punctuation"]
    private static let noise = ["uncensored", "abliterated", "heretic", "jailbreak", "nsfw", "unfiltered"]
    private static let tasks = ["text-generation", "text-to-image", "text-to-video", "image-to-video", "text-to-speech", "automatic-speech-recognition", "text-to-audio",
                                "image-text-to-text", "feature-extraction", "sentence-similarity", "translation"]
    static func task(of m: Model) -> String? { tasks.first { m.tags.contains($0) } }
    private static func sameTaskFamily(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return true }
        let groups = [["feature-extraction", "sentence-similarity"], ["text-to-video", "image-to-video"]]
        return a == b || groups.contains { $0.contains(a) && $0.contains(b) }
    }

    /// Domaine deviné d'après le nom, pour un modèle que le Hub ne connaît pas (dossier local, Ollama).
    static func guessDomain(_ id: String) -> Domain? {
        let n = id.lowercased()
        func has(_ ws: [String]) -> Bool { ws.contains { n.contains($0) } }
        if has(["whisper", "tts", "kokoro", "voice", "speech", "chatterbox", "zonos", "parakeet", "audio"]) { return .audio }
        if has(["flux", "sdxl", "stable-diffusion", "fibo", "image", "qwen-image", "z-image"]) { return .image }
        if has(["ltx", "wan", "video", "hunyuan"]) { return .video }
        if has(["embed", "bge", "minilm", "e5-"]) { return .embeddings }
        if has(["coder", "code"]) { return .code }
        if has(["-vl", "vision", "llava", "pixtral"]) { return .vision }
        if has(["nllb", "mt-"]) { return .translation }
        if has(["llama", "qwen", "gemma", "mistral", "phi", "gpt-oss", "deepseek", "smol"]) { return .text }
        return nil
    }

    // MARK: Audit

    func run(auto: Bool = false) async {
        guard !running else { return }
        let app = AppModel.shared
        if auto, let l = lastRun, Date().timeIntervalSince(l) < 20 * 3600 { return }
        guard !app.models.isEmpty else { return }
        running = true
        defer { running = false }
        let prefs = Prefs.shared
        let dl = Dictionary(DownloadManager.shared.items.filter { $0.state == .done }.map { ($0.destDir, $0.modelID) }, uniquingKeysWith: { a, _ in a })
        let appDir = prefs.modelsPath, extra = prefs.auditDirs
        let installed = await Task.detached { InstalledScanner.scan(appDir: appDir, appDownloads: dl, extraDirs: extra) }.value
        let token = app.token
        var out: [AuditEntry] = []
        for inst in installed {
            // 1. Modèle du catalogue, sinon fiche Hub, sinon rien
            var model = Self.match(inst.id, in: app.models)
            var domain: Domain? = model.flatMap { m in Domain.allCases.first { m.hasDomain($0) } }
            var evals: [Hub.Eval] = []
            if inst.hubLike {
                let info = await cachedInfo(inst.id, token: token)
                if let info { evals = info.evals; if model == nil { model = info.model }; if domain == nil { domain = info.domain } }
            }
            if domain == nil { domain = Self.guessDomain(inst.id) }
            // 2. Score et meilleur candidat de la même tâche, compatible avec le Mac
            var entry = AuditEntry(installed: inst, model: model, domain: domain, score: nil, best: nil, gain: nil, verdict: .unknown, evals: evals)
            if let m = model, m.downloads > 0 || m.likes > 0, let d = domain {
                let mine = Scoring.performance(m)
                entry.score = mine
                let myTask = Self.task(of: m), myBase = Self.baseName(m.id)
                let cands = app.rows(domains: [d], filtered: false).filter { r in
                    let id = r.model.id.lowercased()
                    return r.fit.level != .heavy && r.model.id != m.id && Self.baseName(r.model.id) != myBase
                        && !Self.noise.contains { id.contains($0) } && r.model.likes >= 100
                        && !Self.niche.contains { id.contains($0) && !m.id.lowercased().contains($0) }
                        && Self.sameTaskFamily(myTask, Self.task(of: r.model))
                }
                if let best = cands.max(by: { Scoring.performance($0.model) < Scoring.performance($1.model) }) {
                    let bp = Scoring.performance(best.model)
                    entry.best = best
                    entry.gain = mine > 0 ? bp / mine - 1 : nil
                    entry.verdict = (entry.gain ?? 0) >= 0.15 ? .better : .upToDate
                    if entry.verdict == .better, let bi = await cachedInfo(best.model.id, token: token) { entry.bestEvals = bi.evals }
                } else { entry.verdict = .upToDate }
            }
            out.append(entry)
        }
        entries = out
        record(out, totalGB: installed.reduce(0) { $0 + $1.sizeGB })
    }

    private func cachedInfo(_ id: String, token: String?) async -> (model: Model, domain: Domain?, evals: [Hub.Eval])? {
        if let c = infoCache[id] { return c }
        guard let i = await Hub.info(id: id, token: token) else { return nil }
        infoCache[id] = i
        return i
    }

    static func match(_ id: String, in models: [String: Model]) -> Model? {
        if let m = models[id] { return m }
        let low = id.lowercased()
        if let m = models.values.first(where: { $0.id.lowercased() == low }) { return m }
        let b = baseName(id)
        guard b.count >= 4 else { return nil }
        return models.values.filter { baseName($0.id) == b }.max { $0.likes < $1.likes }
    }

    private func record(_ es: [AuditEntry], totalGB: Double) {
        let known = es.filter { $0.score != nil }
        let ratios = known.map { e -> Double in
            let s = e.score ?? 0, b = e.best.map { Scoring.performance($0.model) } ?? s
            return b > 0 ? min(1, s / max(b, s)) : 1
        }
        let index = ratios.isEmpty ? 0 : ratios.reduce(0, +) / Double(ratios.count) * 100
        let snap = AuditSnapshot(
            date: Date(),
            items: es.map { AuditSnapshot.Item(id: $0.id, domain: $0.domain?.rawValue, score: $0.score, bestID: $0.best?.model.id, bestScore: $0.best.map { Scoring.performance($0.model) }) },
            index: index, upToDate: es.filter { $0.verdict == .upToDate }.count, better: es.filter { $0.verdict == .better }.count,
            unknown: es.filter { $0.verdict == .unknown }.count, totalGB: totalGB)
        // Un instantané par jour : le dernier remplace celui du jour
        if let l = history.last, Calendar.current.isDate(l.date, inSameDayAs: snap.date) { history.removeLast() }
        history.append(snap)
        history = Array(history.suffix(120))
        lastRun = snap.date
        save()
    }

    /// Modèles apparus ou retirés depuis l'instantané précédent.
    var changes: (added: [String], removed: [String]) {
        guard let c = current, let p = previous else { return ([], []) }
        let a = Set(c.items.map(\.id)), b = Set(p.items.map(\.id))
        return (a.subtracting(b).sorted(), b.subtracting(a).sorted())
    }
}
