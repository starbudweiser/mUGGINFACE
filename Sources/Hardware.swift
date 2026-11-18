// mUGGINFACE — détection du matériel (puce, mémoire, disque) et débit mémoire estimé.
import Foundation

enum Hardware {
    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    /// Débit mémoire théorique (Go/s) d'après le nom de la puce ; valeur prudente par défaut.
    static func bandwidth(chip: String) -> Double {
        guard let re = try? NSRegularExpression(pattern: "M(\\d)\\s*(Pro|Max|Ultra)?"),
              let m = re.firstMatch(in: chip, range: NSRange(chip.startIndex..., in: chip)),
              let gen = Int((chip as NSString).substring(with: m.range(at: 1))) else { return 100 }
        let tier = m.range(at: 2).location == NSNotFound ? "" : (chip as NSString).substring(with: m.range(at: 2))
        let table: [Int: [String: Double]] = [
            1: ["": 68, "Pro": 200, "Max": 400, "Ultra": 800],
            2: ["": 100, "Pro": 200, "Max": 400, "Ultra": 800],
            3: ["": 100, "Pro": 150, "Max": 400, "Ultra": 800],
            4: ["": 120, "Pro": 273, "Max": 546, "Ultra": 819],
            5: ["": 153, "Pro": 307, "Max": 614, "Ultra": 1100],
        ]
        return table[gen]?[tier] ?? 100
    }

    static func detect(modelsDir: String) -> HardwareInfo {
        let chip = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        let mem = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return HardwareInfo(chip: chip, memGB: (mem * 10).rounded() / 10, diskFreeGB: diskFree(path: modelsDir), bandwidthGBs: bandwidth(chip: chip))
    }

    static func diskFree(path: String) -> Double {
        var url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        while !FileManager.default.fileExists(atPath: url.path), url.path != "/" { url.deleteLastPathComponent() }
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Double(v?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_073_741_824
    }
}

/// Trousseau : jeton Hugging Face et clé API Claude (jamais en clair sur le disque).
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "fr.stephan.mugginface"
    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ account: String, _ value: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let v = value, !v.isEmpty, let data = v.data(using: .utf8) else { return }
        var add = base; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}
