// mUGGINFACE — état de l'application : réglages, catalogue, classement, veille quotidienne.
import Foundation
import SwiftUI
import UserNotifications
import ServiceManagement

enum SortKey: String, CaseIterable { case overall, performance, light, fresh, popular }
enum Appearance: String, CaseIterable { case auto, light, dark }
enum ShowIn: String, CaseIterable { case both, dock, menubar }

@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var domainsRaw: String { didSet { d.set(domainsRaw, forKey: "domains") } }
    @Published var maxWeightGB: Double { didSet { d.set(maxWeightGB, forKey: "maxWeightGB") } }
    @Published var openLicenseOnly: Bool { didSet { d.set(openLicenseOnly, forKey: "openLicenseOnly") } }
    @Published var formatsRaw: String { didSet { d.set(formatsRaw, forKey: "formats") } }
    @Published var sort: SortKey { didSet { d.set(sort.rawValue, forKey: "sort") } }
    @Published var appearance: Appearance { didSet { d.set(appearance.rawValue, forKey: "appearance") } }
    @Published var showIn: ShowIn { didSet { d.set(showIn.rawValue, forKey: "showIn"); (NSApp.delegate as? AppDelegate)?.applyShowIn() } }
    @Published var reservedGB: Double { didSet { d.set(reservedGB, forKey: "reservedGB") } }
    @Published var modelsDir: String { didSet { d.set(modelsDir, forKey: "modelsDir") } }
    @Published var scanHour: Int { didSet { d.set(scanHour, forKey: "scanHour") } }
    @Published var notify: Bool { didSet { d.set(notify, forKey: "notify") } }
    @Published var onlyMyDomains: Bool { didSet { d.set(onlyMyDomains, forKey: "onlyMyDomains") } }
    @Published var onlyCompatible: Bool { didSet { d.set(onlyCompatible, forKey: "onlyCompatible") } }
    @Published var autoUpdate: Bool { didSet { d.set(autoUpdate, forKey: "autoUpdate") } }
    @Published var confirmBeforeSend: Bool { didSet { d.set(confirmBeforeSend, forKey: "confirmBeforeSend") } }
    @Published var agent: String { didSet { d.set(agent, forKey: "agent") } }
    @Published var customAgentCmd: String { didSet { d.set(customAgentCmd, forKey: "customAgentCmd") } }
    @Published var verifyHash: Bool { didSet { d.set(verifyHash, forKey: "verifyHash") } }
    @Published var offerAgentTest: Bool { didSet { d.set(offerAgentTest, forKey: "offerAgentTest") } }
    @Published var manualMemGB: Double { didSet { d.set(manualMemGB, forKey: "manualMemGB") } }

    init() {
        func b(_ k: String, _ def: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? def }
        func n(_ k: String, _ def: Double) -> Double { UserDefaults.standard.object(forKey: k) as? Double ?? def }
        domainsRaw = d.string(forKey: "domains") ?? "text,code,audio"
        maxWeightGB = n("maxWeightGB", 20)
        openLicenseOnly = b("openLicenseOnly", false)
        formatsRaw = d.string(forKey: "formats") ?? "mlx,gguf,safetensors"
        sort = SortKey(rawValue: d.string(forKey: "sort") ?? "") ?? .overall
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .auto
        showIn = ShowIn(rawValue: d.string(forKey: "showIn") ?? "") ?? .both
        reservedGB = n("reservedGB", 16)
        modelsDir = d.string(forKey: "modelsDir") ?? "~/Modèles"
        scanHour = Int(n("scanHour", 9))
        notify = b("notify", true)
        onlyMyDomains = b("onlyMyDomains", true)
        onlyCompatible = b("onlyCompatible", true)
        autoUpdate = b("autoUpdate", true)
        confirmBeforeSend = b("confirmBeforeSend", true)
        agent = d.string(forKey: "agent") ?? "claudeCode"
        customAgentCmd = d.string(forKey: "customAgentCmd") ?? ""
        verifyHash = b("verifyHash", true)
        offerAgentTest = b("offerAgentTest", true)
        manualMemGB = n("manualMemGB", 0)
    }

    var domains: Set<Domain> {
        get { Set(domainsRaw.split(separator: ",").compactMap { Domain(rawValue: String($0)) }) }
        set { domainsRaw = Domain.allCases.filter { newValue.contains($0) }.map(\.rawValue).joined(separator: ",") }
    }
    var formats: Set<String> {
        get { Set(formatsRaw.split(separator: ",").map(String.init)) }
        set { formatsRaw = ["mlx", "gguf", "safetensors"].filter { newValue.contains($0) }.joined(separator: ",") }
    }
    var modelsPath: String { (modelsDir as NSString).expandingTildeInPath }
}

struct Row: Identifiable {
    var model: Model
    var fit: FitResult
    var score: Double
    var id: String { model.id }
}

private struct Saved: Codable {
    var models: [String: Model] = [:]
    var firstSeen: [String: Date] = [:]
    var favorites: Set<String> = []
    var events: [WatchEvent] = []
    var lastScan: Date?
    var snapshot: [String: [String]] = [:]
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    let prefs = Prefs.shared

    @Published private(set) var models: [String: Model] = [:]
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var events: [WatchEvent] = []
    @Published private(set) var lastScan: Date?
    @Published var scanning = false
    @Published var scanError: String?
    @Published var hw: HardwareInfo
    private var firstSeen: [String: Date] = [:]
    private var snapshot: [String: [String]] = [:]
    private var timer: Timer?

    var token: String? { Keychain.get("hf-token") }

    private static var dataDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "fr.stephan.mugginface")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var file: URL { Self.dataDir.appendingPathComponent("catalog.json") }

    init() {
        hw = Hardware.detect(modelsDir: Prefs.shared.modelsPath)
        if let data = try? Data(contentsOf: file) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            if let s = try? dec.decode(Saved.self, from: data) {
                models = s.models; firstSeen = s.firstSeen; favorites = s.favorites; events = s.events; lastScan = s.lastScan; snapshot = s.snapshot
            }
        }
        applyManualMemory()
    }

    func applyManualMemory() {
        let detected = Hardware.detect(modelsDir: prefs.modelsPath)
        hw = detected
        if prefs.manualMemGB > 0 { hw.memGB = prefs.manualMemGB }
    }

    func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let s = Saved(models: models, firstSeen: firstSeen, favorites: favorites, events: events, lastScan: lastScan, snapshot: snapshot)
        if let data = try? enc.encode(s) { try? data.write(to: file, options: .atomic) }
    }

    // MARK: - Classement

    var usableGB: Double { Scoring.usableGB(hw, reservedGB: prefs.reservedGB) }

    func row(_ m: Model, domain: Domain? = nil) -> Row {
        let d = domain ?? m.domains.compactMap(Domain.init(rawValue:)).first
        let f = Scoring.fit(weightsGB: m.weightsGB, domain: d, hw: hw, reservedGB: prefs.reservedGB)
        return Row(model: m, fit: f, score: Scoring.overall(m, fit: f, hw: hw, reservedGB: prefs.reservedGB))
    }

    /// Modèles des domaines choisis, filtrés selon les réglages et triés.
    func rows(domains: Set<Domain>, search: String = "", filtered: Bool = true) -> [Row] {
        var out: [Row] = []
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        for m in models.values {
            guard let d = Domain.allCases.first(where: { domains.contains($0) && m.hasDomain($0) }) else { continue }
            if !q.isEmpty, !m.id.lowercased().contains(q) { continue }
            if filtered {
                if prefs.openLicenseOnly, !m.isOpenLicense { continue }
                if !prefs.formats.contains(m.format) { continue }
                if prefs.maxWeightGB > 0, let w = m.weightsGB, w > prefs.maxWeightGB { continue }
            }
            let r = row(m, domain: d)
            if filtered, r.fit.level == .heavy { continue }
            out.append(r)
        }
        switch prefs.sort {
        case .overall: out.sort { $0.score > $1.score }
        case .performance: out.sort { Scoring.performance($0.model) > Scoring.performance($1.model) }
        case .light: out.sort { ($0.fit.ramGB ?? 999) < ($1.fit.ramGB ?? 999) }
        case .fresh: out.sort { ($0.model.lastModified ?? .distantPast) > ($1.model.lastModified ?? .distantPast) }
        case .popular: out.sort { $0.model.downloads > $1.model.downloads }
        }
        return out
    }

    func isNew(_ m: Model) -> Bool {
        if let c = m.created, Date().timeIntervalSince(c) < 7 * 86400 { return true }
        if lastScan != nil, let f = firstSeen[m.id], Date().timeIntervalSince(f) < 3 * 86400, f > (firstSeenBaseline ?? .distantFuture) { return true }
        return false
    }
    private var firstSeenBaseline: Date? { events.isEmpty && snapshot.isEmpty ? nil : firstSeen.values.min() }

    // MARK: - Favoris et événements

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        save()
    }
    var unreadCount: Int { events.filter { !$0.read }.count }
    func markAllRead() { for i in events.indices { events[i].read = true }; save() }

    // MARK: - Veille

    func startScheduler() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        tick()
    }

    func tick() {
        guard !scanning else { return }
        let now = Date()
        if models.isEmpty || lastScan == nil { Task { await scan() }; return }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: now)
        c.hour = prefs.scanHour; c.minute = 0
        let slot = Calendar.current.date(from: c) ?? now
        let due = now >= slot ? slot : slot.addingTimeInterval(-86400)
        if let l = lastScan, l < due { Task { await scan() } }
    }

    func scan(domains only: Set<Domain>? = nil) async {
        guard !scanning else { return }
        scanning = true; scanError = nil
        defer { scanning = false }
        let doms = only ?? (prefs.domains.isEmpty ? Set(Domain.allCases) : prefs.domains)
        let firstEver = lastScan == nil
        let before = Set(models.keys)
        var errors = 0
        for d in Domain.allCases where doms.contains(d) {
            do {
                let list = try await Hub.fetch(domain: d, token: token)
                for var m in list {
                    if var old = models[m.id] {
                        var ds = Set(old.domains); ds.insert(d.rawValue)
                        m.domains = Array(ds).sorted(); old = m; models[m.id] = old
                    } else {
                        models[m.id] = m
                        firstSeen[m.id] = Date()
                    }
                }
            } catch { errors += 1; scanError = error.localizedDescription }
        }
        if errors == doms.count { return }
        applyManualMemory()
        var newEvents: [WatchEvent] = []
        let now = Date()
        for d in Domain.allCases where doms.contains(d) {
            let top = rows(domains: [d], filtered: true).prefix(10).map { $0.model.id }
            let prev = snapshot[d.rawValue] ?? []
            if !firstEver && !prev.isEmpty {
                for (i, id) in top.enumerated() {
                    if !before.contains(id) { newEvents.append(WatchEvent(date: now, kind: .new, modelID: id, domain: d.rawValue, rank: i + 1)) }
                    else if let p = prev.firstIndex(of: id) { if p - i >= 2 { newEvents.append(WatchEvent(date: now, kind: .rise, modelID: id, domain: d.rawValue, rank: i + 1, from: p + 1)) } }
                    else { newEvents.append(WatchEvent(date: now, kind: .enter, modelID: id, domain: d.rawValue, rank: i + 1)) }
                }
                for id in prev where !top.contains(id) { newEvents.append(WatchEvent(date: now, kind: .removed, modelID: id, domain: d.rawValue)) }
            }
            snapshot[d.rawValue] = Array(top)
        }
        lastScan = now
        events = Array((newEvents + events).prefix(200))
        save()
        if !newEvents.isEmpty, prefs.notify, !firstEver { notify(newEvents) }
    }

    private func notify(_ evs: [WatchEvent]) {
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert]) { ok, _ in
            guard ok else { return }
            let content = UNMutableNotificationContent()
            content.title = "mUGGINFACE"
            content.body = L.t("notif.body", evs.filter { $0.kind == .new || $0.kind == .enter }.count, evs.count)
            c.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
    }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
}
