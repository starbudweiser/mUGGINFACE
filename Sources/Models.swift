// mUGGINFACE — modèles de données : domaines, modèles Hugging Face, adéquation au matériel, score.
import Foundation

enum Domain: String, CaseIterable, Codable, Identifiable {
    case text, code, image, video, audio, vision, embeddings, translation
    var id: String { rawValue }
    var titleKey: String { "dom." + rawValue }
    var symbol: String {
        switch self {
        case .text: return "text.bubble"; case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"; case .video: return "film"; case .audio: return "waveform"
        case .vision: return "eye"; case .embeddings: return "point.3.connected.trianglepath.dotted"
        case .translation: return "character.bubble"
        }
    }
    /// Requêtes envoyées au Hub : étiquette de pipeline + recherche facultative.
    var queries: [(pipeline: String, search: String?)] {
        switch self {
        case .text: return [("text-generation", nil)]
        case .code: return [("text-generation", "coder"), ("text-generation", "code")]
        case .image: return [("text-to-image", nil)]
        case .video: return [("text-to-video", nil), ("image-to-video", nil)]
        case .audio: return [("text-to-speech", nil), ("automatic-speech-recognition", nil), ("text-to-audio", nil)]
        case .vision: return [("image-text-to-text", nil)]
        case .embeddings: return [("feature-extraction", nil), ("sentence-similarity", nil)]
        case .translation: return [("translation", nil)]
        }
    }
    /// Domaines où le débit en jetons par seconde a un sens.
    var isLLM: Bool { self == .text || self == .code || self == .vision || self == .translation }
}

enum FitLevel: String, Codable {
    case smooth, ok, limit, heavy, unknown
    var tagKey: String { "fit." + rawValue }
    var rank: Int { switch self { case .smooth: return 0; case .ok: return 1; case .limit: return 2; case .unknown: return 3; case .heavy: return 4 } }
}

struct Model: Codable, Identifiable, Hashable {
    var id: String
    var domains: [String]
    var downloads: Int
    var likes: Int
    var trending: Double
    var lastModified: Date?
    var created: Date?
    var tags: [String]
    var gated: Bool
    var paramsB: Double?
    var license: String?
    var weightsGB: Double?
    var format: String            // mlx, gguf, safetensors
    var bits: Double

    var author: String { id.split(separator: "/").first.map(String.init) ?? "" }
    var shortName: String { id.split(separator: "/").last.map(String.init) ?? id }
    var initial: String { String(shortName.first.map { String($0).uppercased() } ?? "?") }
    var isOpenLicense: Bool {
        guard let l = license?.lowercased() else { return false }
        return ["apache-2.0", "mit", "bsd-3-clause", "bsd-2-clause", "cc-by-4.0", "cc0-1.0", "openrail", "openrail++", "unlicense", "isc", "cc-by-sa-4.0"].contains(l)
    }
    func hasDomain(_ d: Domain) -> Bool { domains.contains(d.rawValue) }
}

struct RepoFile: Codable, Hashable { var path: String; var size: Int64; var sha256: String? }

struct Variant: Identifiable, Hashable {
    var id: String { label }
    var label: String
    var files: [RepoFile]
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    var gb: Double { Double(totalBytes) / 1_073_741_824 }
}

struct FitResult { var level: FitLevel; var ramGB: Double?; var tokensPerSec: Double? }

enum Scoring {
    /// Mémoire utilisable par le modèle : mémoire totale moins la réserve laissée au système.
    static func usableGB(_ hw: HardwareInfo, reservedGB: Double) -> Double { max(2, hw.memGB - reservedGB) }

    static func fit(weightsGB: Double?, domain: Domain?, hw: HardwareInfo, reservedGB: Double) -> FitResult {
        guard let w = weightsGB else { return FitResult(level: .unknown, ramGB: nil, tokensPerSec: nil) }
        let ram = w * 1.10 + 1.5
        let usable = usableGB(hw, reservedGB: reservedGB)
        let level: FitLevel = ram <= usable * 0.6 ? .smooth : ram <= usable * 0.85 ? .ok : ram <= usable ? .limit : .heavy
        var tps: Double?
        if domain?.isLLM ?? true, w > 0.05 { tps = min(400, hw.bandwidthGBs * 0.7 / w) }
        return FitResult(level: level, ramGB: ram, tokensPerSec: tps)
    }

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    /// Indice de performance estimé (0 à 10) : taille du modèle, popularité, tendance, fraîcheur.
    static func performance(_ m: Model, now: Date = Date()) -> Double {
        let cap = m.paramsB.map { clamp((log2(max($0, 0.1)) + 3) / 12) } ?? 0.4
        let pop = clamp(log10(Double(m.likes) + 1) / 4)
        let dl = clamp(log10(Double(m.downloads) + 1) / 7)
        let trend = clamp(m.trending / 200)
        let age = now.timeIntervalSince(m.lastModified ?? m.created ?? now) / 86400
        let rec = clamp(1 - age / 365)
        return (0.30 * cap + 0.28 * pop + 0.22 * dl + 0.10 * trend + 0.10 * rec) * 10
    }

    /// Score global : compromis entre performance estimée et légèreté pour le matériel.
    static func overall(_ m: Model, fit: FitResult, hw: HardwareInfo, reservedGB: Double) -> Double {
        let perf = performance(m)
        guard let ram = fit.ramGB else { return perf * 0.8 }
        let light = clamp(1 - ram / usableGB(hw, reservedGB: reservedGB)) * 10
        return 0.62 * perf + 0.38 * light
    }

    // MARK: - Extraction depuis les noms et étiquettes

    static func paramsFromName(_ name: String) -> Double? {
        let ns = name as NSString
        var best: Double?
        if let re = try? NSRegularExpression(pattern: "(?<![A-DF-Za-z0-9.])(\\d+(?:\\.\\d+)?)([BbMm])(?![A-Za-z])") {
            for m in re.matches(in: name, range: NSRange(location: 0, length: ns.length)) {
                guard let v = Double(ns.substring(with: m.range(at: 1))) else { continue }
                let unit = ns.substring(with: m.range(at: 2)).lowercased()
                let b = unit == "m" ? v / 1000 : v
                if b > (best ?? 0) { best = b }
            }
        }
        return best
    }

    static func bits(name: String, tags: [String], format: String) -> Double {
        let s = (name + " " + tags.joined(separator: " ")).lowercased()
        let table: [(String, Double)] = [("nvfp4", 4.5), ("fp4", 4.5), ("2bit", 2.5), ("2-bit", 2.5), ("q2", 2.8), ("3bit", 3.5), ("3-bit", 3.5), ("q3", 3.9),
            ("4bit", 4.5), ("4-bit", 4.5), ("int4", 4.5), ("q4", 4.8), ("awq", 4.5), ("gptq", 4.5), ("5bit", 5.5), ("q5", 5.6), ("6bit", 6.5), ("q6", 6.6),
            ("8bit", 8.5), ("8-bit", 8.5), ("int8", 8.5), ("fp8", 8.5), ("q8", 8.5), ("bf16", 16), ("fp16", 16), ("f16", 16)]
        for (k, v) in table where s.contains(k) { return v }
        return format == "gguf" ? 4.8 : 16
    }

    static func format(of tags: [String]) -> String {
        if tags.contains("mlx") { return "mlx" }
        if tags.contains("gguf") { return "gguf" }
        return "safetensors"
    }
}

/// Événement de veille : ce qui a changé depuis le dernier scan.
struct WatchEvent: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case new, rise, enter, removed }
    var id = UUID()
    var date: Date
    var kind: Kind
    var modelID: String
    var domain: String
    var rank: Int?
    var from: Int?
    var read = false
}

struct HardwareInfo: Codable, Equatable {
    var chip: String
    var memGB: Double
    var diskFreeGB: Double
    var bandwidthGBs: Double
}
