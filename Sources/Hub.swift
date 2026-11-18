// mUGGINFACE — client de l'API Hugging Face : liste des modèles par domaine, fichiers d'un modèle, variantes.
import Foundation

enum HubError: LocalizedError {
    case http(Int), network(String)
    var errorDescription: String? {
        switch self { case .http(let c): return "HTTP \(c)"; case .network(let s): return s }
    }
}

private struct APIModel: Decodable {
    var id: String
    var downloads: Int?
    var likes: Int?
    var trendingScore: Double?
    var lastModified: String?
    var createdAt: String?
    var tags: [String]?
    var gated: GatedValue?
    var safetensors: ST?
    var gguf: GG?
    struct GG: Decodable { var total: Double? }
    struct ST: Decodable { var total: Double?; var parameters: [String: Double]? }
    enum GatedValue: Decodable {
        case flag(Bool), kind(String)
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let b = try? c.decode(Bool.self) { self = .flag(b) } else { self = .kind((try? c.decode(String.self)) ?? "") }
        }
        var isGated: Bool { switch self { case .flag(let b): return b; case .kind: return true } }
    }
}

enum Hub {
    static let base = "https://huggingface.co"
    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static let isoPlain = ISO8601DateFormatter()
    static func date(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) } }

    static func request(_ url: URL, token: String?) -> URLRequest {
        var r = URLRequest(url: url)
        r.timeoutInterval = 30
        r.setValue("mUGGINFACE", forHTTPHeaderField: "User-Agent")
        if let t = token, !t.isEmpty { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        return r
    }

    static func get(_ url: URL, token: String?) async throws -> Data {
        do {
            let (data, resp) = try await URLSession.shared.data(for: request(url, token: token))
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw HubError.http(code) }
            return data
        } catch let e as HubError { throw e } catch { throw HubError.network(error.localizedDescription) }
    }

    /// Modèles d'un domaine : tendance et téléchargements, fusionnés et dédoublonnés.
    static func fetch(domain: Domain, token: String?, limit: Int = 40) async throws -> [Model] {
        var seen = Set<String>(), out: [Model] = []
        for q in domain.queries {
            for sort in ["trendingScore", "downloads"] {
                var c = URLComponents(string: "\(base)/api/models")!
                var items = [URLQueryItem(name: "pipeline_tag", value: q.pipeline), URLQueryItem(name: "sort", value: sort),
                             URLQueryItem(name: "limit", value: String(limit))]
                if let s = q.search { items.append(URLQueryItem(name: "search", value: s)) }
                for e in ["downloads", "likes", "lastModified", "createdAt", "tags", "gated", "safetensors", "trendingScore", "gguf"] {
                    items.append(URLQueryItem(name: "expand[]", value: e))
                }
                c.queryItems = items
                let data = try await get(c.url!, token: token)
                let list = try JSONDecoder().decode([APIModel].self, from: data)
                for a in list where !seen.contains(a.id) {
                    seen.insert(a.id)
                    out.append(make(a, domain: domain))
                }
            }
        }
        return out
    }

    private static func make(_ a: APIModel, domain: Domain) -> Model {
        let tags = a.tags ?? []
        let name = a.id.split(separator: "/").last.map(String.init) ?? a.id
        let format = Scoring.format(of: tags)
        var params = Scoring.paramsFromName(name)
        if params == nil, let t = a.safetensors?.total, t > 0 {
            let dt = a.safetensors?.parameters ?? [:]
            params = dt.keys.contains("U32") || dt.keys.contains("I32") ? nil : t / 1e9
        }
        if params == nil, let t = a.gguf?.total, t > 0 { params = t / 1e9 }
        let bits = Scoring.bits(name: name, tags: tags, format: format)
        let gb = params.map { $0 * bits / 8 * 1.05 }
        let license = tags.first { $0.hasPrefix("license:") }.map { String($0.dropFirst(8)) }
        return Model(id: a.id, domains: [domain.rawValue], downloads: a.downloads ?? 0, likes: a.likes ?? 0, trending: a.trendingScore ?? 0,
                     lastModified: date(a.lastModified), created: date(a.createdAt), tags: tags, gated: a.gated?.isGated ?? false,
                     paramsB: params, license: license, weightsGB: gb, format: format, bits: bits)
    }

    // MARK: - Fichiers et variantes

    private struct TreeEntry: Decodable {
        var type: String; var path: String; var size: Int64?
        var lfs: LFS?
        struct LFS: Decodable { var oid: String?; var size: Int64? }
    }

    static func files(of id: String, token: String?) async throws -> [RepoFile] {
        var all: [RepoFile] = []
        let url = URL(string: "\(base)/api/models/\(id)/tree/main?recursive=true")!
        let data = try await get(url, token: token)
        for e in try JSONDecoder().decode([TreeEntry].self, from: data) where e.type == "file" {
            all.append(RepoFile(path: e.path, size: e.lfs?.size ?? e.size ?? 0, sha256: e.lfs?.oid))
        }
        return all
    }

    /// Regroupe les fichiers en variantes installables : une par quantification GGUF, sinon le dépôt complet.
    static func variants(from files: [RepoFile]) -> [Variant] {
        let ggufs = files.filter { $0.path.lowercased().hasSuffix(".gguf") && !$0.path.lowercased().contains("mmproj") && !$0.path.lowercased().contains("imatrix") }
        let extras = files.filter { !$0.path.lowercased().hasSuffix(".gguf") && !$0.path.hasPrefix(".") && !$0.path.lowercased().hasSuffix(".md") && !$0.path.contains("/") }
        if !ggufs.isEmpty {
            var groups: [String: [RepoFile]] = [:]
            for f in ggufs { groups[quantLabel(f.path), default: []].append(f) }
            return groups.map { Variant(label: $0.key, files: $0.value.sorted { $0.path < $1.path }) }
                .sorted { $0.totalBytes < $1.totalBytes }
        }
        let hasST = files.contains { $0.path.lowercased().hasSuffix(".safetensors") }
        let drop = [".bin", ".pt", ".pth", ".onnx", ".msgpack", ".h5", ".ckpt", ".gguf", ".md", ".png", ".jpg", ".jpeg", ".gif", ".mp4"]
        let keep = files.filter { f in
            let p = f.path.lowercased()
            if f.path.hasPrefix(".") || f.path.hasPrefix("original/") { return false }
            if hasST, drop.contains(where: { p.hasSuffix($0) }) { return false }
            return !p.hasSuffix(".md") || !f.path.contains("/")
        }
        _ = extras
        return keep.isEmpty ? [] : [Variant(label: "Complet", files: keep)]
    }

    static func quantLabel(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        if let re = try? NSRegularExpression(pattern: "(?i)(I?Q\\d(?:_[A-Z0-9]+)*|BF16|F16|F32)"),
           let m = re.firstMatch(in: name, range: NSRange(location: 0, length: (name as NSString).length)) {
            return (name as NSString).substring(with: m.range).uppercased()
        }
        return (name as NSString).deletingPathExtension
    }

    static func installCommand(id: String, variant: Variant, dir: String) -> String {
        let target = "\(dir)/\(id.split(separator: "/").last ?? "")"
        var cmd = "hf download \(id)"
        if variant.label != "Complet", variant.files.count == 1 { cmd += " \"\(variant.files[0].path)\"" }
        else if variant.label != "Complet" { cmd += " --include \"*\(variant.label)*\"" }
        return cmd + " --local-dir \"\(target)\""
    }
}
