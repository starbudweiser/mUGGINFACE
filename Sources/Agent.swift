// mUGGINFACE — pont vers un agent IA : discussion sur les modèles et envoi d'instructions d'installation.
import Foundation

struct ChatMessage: Identifiable, Hashable {
    enum Role { case user, agent, system }
    let id = UUID()
    var role: Role
    var text: String
    var modelID: String?       // modèle cité par l'agent, pour « Voir la fiche » / « Préparer l'installation »
}

enum AgentKind: String, CaseIterable { case claudeCode, claudeAPI, custom }

@MainActor
final class AgentBridge: ObservableObject {
    static let shared = AgentBridge()
    @Published var messages: [ChatMessage] = []
    @Published var busy = false
    @Published var draftPrompt: String = ""          // invite d'installation en attente de relecture
    @Published var draftDir: String = ""
    @Published var runLog: String = ""
    @Published var lastError: String?
    @Published var prefill: String = ""
    var prefs: Prefs { Prefs.shared }
    var kind: AgentKind { AgentKind(rawValue: prefs.agent) ?? .claudeCode }

    var apiKey: String? { Keychain.get("claude-api-key") }

    // MARK: - Contexte et invites

    func hardwareLine() -> String {
        let hw = AppModel.shared.hw
        return "\(hw.chip), \(Int(hw.memGB)) Go de mémoire unifiée, \(Int(hw.diskFreeGB)) Go libres sur le disque"
    }

    func installPrompt(model: Model, variant: Variant, dir: String) -> String {
        let target = (dir as NSString).appendingPathComponent(model.shortName)
        let cmd = Hub.installCommand(id: model.id, variant: variant, dir: dir)
        return """
        Installe en local le modèle Hugging Face « \(model.id) » (variante \(variant.label), \(String(format: "%.1f", variant.gb)) Go) dans \(target).
        Mac : \(hardwareLine()).
        1. Vérifie l'espace disque disponible et la présence de l'outil `hf` (huggingface_hub).
        2. Télécharge : \(cmd)
        3. Vérifie que les fichiers sont complets, puis teste le modèle avec un court prompt (mlx-lm pour MLX, llama.cpp pour GGUF) et indique le débit mesuré en jetons par seconde.
        Demande-moi confirmation avant d'installer un outil manquant. Réponds en \(L.languageName).
        """
    }

    func chatContext() -> String {
        let app = AppModel.shared
        let doms = app.prefs.domains.map { L.t($0.titleKey) }.sorted().joined(separator: ", ")
        let top = app.rows(domains: app.prefs.domains).prefix(8).map {
            "- \($0.model.id) : \($0.model.weightsGB.map { String(format: "%.1f Go", $0) } ?? "taille inconnue"), \(L.t($0.fit.level.tagKey)), score \(String(format: "%.1f", $0.score))"
        }.joined(separator: "\n")
        return """
        Tu aides à choisir un modèle d'IA à installer en local. Réponds en \(L.languageName), brièvement, sans exécuter de commande.
        Matériel de l'utilisateur : \(hardwareLine()). Mémoire utilisable : \(Int(app.usableGB)) Go. Domaines choisis : \(doms).
        Meilleurs candidats actuels (score estimé, adéquation au Mac) :
        \(top)
        Quand tu recommandes un modèle, écris son identifiant exact « auteur/nom » tel que listé ci-dessus.
        """
    }

    // MARK: - Discussion

    func ask(_ question: String) async {
        messages.append(ChatMessage(role: .user, text: question))
        busy = true; lastError = nil
        defer { busy = false }
        let history = messages.suffix(8).map { ($0.role == .user ? "Utilisateur : " : "Assistant : ") + $0.text }.joined(separator: "\n")
        let prompt = chatContext() + "\n\nConversation :\n" + history + "\nAssistant :"
        do {
            let answer = try await run(prompt: prompt, allowTools: false)
            let ids = AppModel.shared.models.keys.filter { answer.contains($0) }
            messages.append(ChatMessage(role: .agent, text: answer, modelID: ids.first))
        } catch { lastError = error.localizedDescription; messages.append(ChatMessage(role: .system, text: error.localizedDescription)) }
    }

    func prepareInstall(model: Model, variant: Variant) {
        draftDir = prefs.modelsPath
        draftPrompt = installPrompt(model: model, variant: variant, dir: prefs.modelsPath)
        runLog = ""
    }

    /// Envoie l'invite d'installation relue par l'utilisateur ; l'agent agit avec ses propres autorisations.
    func sendDraft() async {
        let p = draftPrompt
        guard !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; lastError = nil; runLog = L.t("agent.running")
        defer { busy = false }
        do { runLog = try await run(prompt: p, allowTools: true) }
        catch { lastError = error.localizedDescription; runLog = "" }
    }

    // MARK: - Exécution

    enum AgentError: LocalizedError {
        case noClaude, noKey, noCommand, api(String), exit(Int32, String)
        var errorDescription: String? {
            switch self {
            case .noClaude: return L.t("agent.err.noclaude")
            case .noKey: return L.t("agent.err.nokey")
            case .noCommand: return L.t("agent.err.nocmd")
            case .api(let s): return L.t("agent.err.api", s)
            case .exit(let c, let o): return L.t("agent.err.exit", Int(c), String(o.suffix(400)))
            }
        }
    }

    func run(prompt: String, allowTools: Bool) async throws -> String {
        switch kind {
        case .claudeAPI: return try await callAPI(prompt)
        case .claudeCode:
            let allowed = allowTools ? " --allowedTools 'Bash(hf:*)' 'Bash(huggingface-cli:*)' 'Bash(df:*)' 'Bash(ls:*)' 'Bash(du:*)' 'Bash(mkdir:*)' 'Bash(python3 -m mlx_lm:*)' 'Bash(llama-cli:*)'" : ""
            return try await shell("claude -p \"$MUG_PROMPT\"\(allowed)", prompt: prompt, cwd: allowTools ? prefs.modelsPath : NSHomeDirectory(), stdin: nil)
        case .custom:
            let cmd = prefs.customAgentCmd.trimmingCharacters(in: .whitespaces)
            guard !cmd.isEmpty else { throw AgentError.noCommand }
            return try await shell(cmd, prompt: prompt, cwd: allowTools ? prefs.modelsPath : NSHomeDirectory(), stdin: prompt)
        }
    }

    private func callAPI(_ prompt: String) async throws -> String {
        guard let key = apiKey, !key.isEmpty else { throw AgentError.noKey }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"; req.timeoutInterval = 120
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = ["model": "claude-sonnet-5-5", "max_tokens": 1500, "messages": [["role": "user", "content": prompt]]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
            throw AgentError.api(msg)
        }
        let parts = (json?["content"] as? [[String: Any]]) ?? []
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    private func shell(_ command: String, prompt: String, cwd: String, stdin: String?) async throws -> String {
        try? FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let p = Process(), out = Pipe(), inp = Pipe()
                let errURL = FileManager.default.temporaryDirectory.appendingPathComponent("mug-agent-\(UUID().uuidString).err")
                FileManager.default.createFile(atPath: errURL.path, contents: nil)
                let errHandle = try? FileHandle(forWritingTo: errURL)
                defer { try? errHandle?.close(); try? FileManager.default.removeItem(at: errURL) }
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", command]
                p.currentDirectoryURL = URL(fileURLWithPath: cwd)
                var env = ProcessInfo.processInfo.environment
                env["MUG_PROMPT"] = prompt
                p.environment = env
                p.standardOutput = out; p.standardError = errHandle ?? out
                if stdin != nil { p.standardInput = inp } else { p.standardInput = FileHandle.nullDevice }
                do { try p.run() } catch { cont.resume(throwing: error); return }
                if let s = stdin { inp.fileHandleForWriting.write(Data(s.utf8)); try? inp.fileHandleForWriting.close() }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                var text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if p.terminationStatus != 0, let e = try? String(contentsOf: errURL, encoding: .utf8) { text = (text + "\n" + e).trimmingCharacters(in: .whitespacesAndNewlines) }
                if p.terminationStatus == 127 { cont.resume(throwing: AgentError.noClaude) }
                else if p.terminationStatus != 0 { cont.resume(throwing: AgentError.exit(p.terminationStatus, text)) }
                else { cont.resume(returning: text) }
            }
        }
    }
}
