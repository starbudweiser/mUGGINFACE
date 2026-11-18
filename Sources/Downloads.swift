// mUGGINFACE — téléchargements intégrés : file d'attente, pause / reprise (Range), vérification SHA-256.
import Foundation
import CryptoKit

struct DownloadItem: Codable, Identifiable {
    enum State: String, Codable { case queued, running, paused, verifying, done, failed }
    var id = UUID()
    var modelID: String
    var label: String
    var files: [RepoFile]
    var destDir: String
    var state: State = .queued
    var doneBytes: Int64 = 0
    var error: String?
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    var progress: Double { totalBytes > 0 ? min(1, Double(doneBytes) / Double(totalBytes)) : 0 }
}

/// Télécharge un fichier avec reprise : écrit dans un fichier .part, ne transmet jamais le jeton à un autre domaine.
final class FileTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var cont: CheckedContinuation<Void, Error>?
    private var status = 0
    private var offset: Int64 = 0
    var onBytes: ((Int64) -> Void)?
    var onReset: (() -> Void)?

    override init() {
        super.init()
        let q = OperationQueue(); q.maxConcurrentOperationCount = 1
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: q)
    }

    func run(url: URL, part: URL, token: String?, offset: Int64) async throws {
        self.offset = offset
        if !FileManager.default.fileExists(atPath: part.path) { FileManager.default.createFile(atPath: part.path, contents: nil) }
        handle = try FileHandle(forWritingTo: part)
        try handle?.seek(toOffset: UInt64(offset))
        var req = Hub.request(url, token: token)
        req.timeoutInterval = 60
        if offset > 0 { req.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            self.cont = c
            let t = session.dataTask(with: req)
            self.task = t
            t.resume()
        }
    }

    func cancel() { task?.cancel() }

    private func finish(_ err: Error?) {
        try? handle?.close(); handle = nil
        guard let c = cont else { return }
        cont = nil
        if let e = err { c.resume(throwing: e) } else { c.resume() }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest req: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var n = req
        if req.url?.host != task.originalRequest?.url?.host { n.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(n)
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200, offset > 0 { try? handle?.truncate(atOffset: 0); try? handle?.seek(toOffset: 0); offset = 0; onReset?() }
        completionHandler(status == 200 || status == 206 ? .allow : .cancel)
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        try? handle?.write(contentsOf: data)
        onBytes?(Int64(data.count))
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let e = error { finish((e as NSError).code == NSURLErrorCancelled && status != 0 && status != 200 && status != 206 ? HubError.http(status) : e) }
        else if status != 200 && status != 206 { finish(HubError.http(status)) }
        else { finish(nil) }
    }
}

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var speed: Double = 0           // octets / s du téléchargement en cours
    private var transfer: FileTransfer?
    private var currentID: UUID?
    private var pumping = false
    private var lastTick = Date(), tickBytes: Int64 = 0

    private var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "fr.stephan.mugginface")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("downloads.json")
    }

    init() {
        if let d = try? Data(contentsOf: file), let i = try? JSONDecoder().decode([DownloadItem].self, from: d) {
            items = i.map { var x = $0; if x.state == .running || x.state == .verifying || x.state == .queued { x.state = .paused }; return x }
        }
    }

    private func save() { if let d = try? JSONEncoder().encode(items) { try? d.write(to: file, options: .atomic) } }
    private func idx(_ id: UUID) -> Int? { items.firstIndex { $0.id == id } }
    var active: DownloadItem? { items.first { $0.state == .running || $0.state == .verifying } }
    var activeCount: Int { items.filter { $0.state == .running || $0.state == .verifying || $0.state == .queued }.count }

    func enqueue(model: Model, variant: Variant) -> String? {
        let dest = (Prefs.shared.modelsPath as NSString).appendingPathComponent(model.shortName)
        let need = Double(variant.totalBytes) / 1_073_741_824
        if Hardware.diskFree(path: Prefs.shared.modelsPath) < need * 1.05 + 0.5 { return L.t("dl.err.disk", need) }
        if items.contains(where: { $0.modelID == model.id && $0.label == variant.label && $0.state != .done && $0.state != .failed }) { return nil }
        items.insert(DownloadItem(modelID: model.id, label: variant.label, files: variant.files, destDir: dest), at: 0)
        save(); pump()
        return nil
    }

    func pause(_ id: UUID) {
        guard let i = idx(id) else { return }
        if items[i].state == .running { transfer?.cancel() }
        items[i].state = .paused; save()
    }
    func resume(_ id: UUID) { if let i = idx(id) { items[i].state = .queued; items[i].error = nil; save(); pump() } }
    func remove(_ id: UUID) {
        guard let i = idx(id) else { return }
        if items[i].state == .running { transfer?.cancel() }
        let it = items[i]
        if it.state != .done { for f in it.files { try? FileManager.default.removeItem(atPath: (it.destDir as NSString).appendingPathComponent(f.path) + ".part") } }
        items.remove(at: i); save()
    }

    private func pump() {
        guard !pumping else { return }
        guard let next = items.last(where: { $0.state == .queued }) ?? items.first(where: { $0.state == .queued }) else { return }
        pumping = true
        currentID = next.id
        Task { await self.process(next.id); self.pumping = false; self.currentID = nil; self.pump() }
    }

    private func set(_ id: UUID, _ f: (inout DownloadItem) -> Void) { if let i = idx(id) { f(&items[i]) } }

    private func process(_ id: UUID) async {
        guard let it0 = items.first(where: { $0.id == id }) else { return }
        set(id) { $0.state = .running; $0.error = nil }
        let token = AppModel.shared.token
        let dir = it0.destDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // Octets déjà présents (fichiers terminés + parties) pour la progression.
        var done: Int64 = 0
        for f in it0.files {
            let final = (dir as NSString).appendingPathComponent(f.path)
            if let a = try? FileManager.default.attributesOfItem(atPath: final), (a[.size] as? Int64) == f.size { done += f.size }
            else if let a = try? FileManager.default.attributesOfItem(atPath: final + ".part") { done += (a[.size] as? Int64) ?? 0 }
        }
        set(id) { $0.doneBytes = done }
        for f in it0.files {
            guard items.first(where: { $0.id == id })?.state == .running else { return }
            let final = (dir as NSString).appendingPathComponent(f.path)
            if let a = try? FileManager.default.attributesOfItem(atPath: final), (a[.size] as? Int64) == f.size { continue }
            try? FileManager.default.createDirectory(atPath: (final as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            let part = URL(fileURLWithPath: final + ".part")
            let have = ((try? FileManager.default.attributesOfItem(atPath: part.path))?[.size] as? Int64) ?? 0
            let url = URL(string: "\(Hub.base)/\(it0.modelID)/resolve/main/\(f.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? f.path)")!
            let t = FileTransfer()
            transfer = t
            t.onBytes = { [weak self] n in Task { @MainActor in self?.bytes(id, n) } }
            t.onReset = { [weak self] in Task { @MainActor in self?.set(id) { $0.doneBytes = max(0, $0.doneBytes - have) } } }
            do { try await t.run(url: url, part: part, token: token, offset: have) }
            catch {
                if items.first(where: { $0.id == id })?.state == .paused { speed = 0; return }
                let msg = (error as? HubError).map { e -> String in
                    if case .http(let c) = e, c == 401 || c == 403 { return L.t("dl.err.auth") }
                    return e.localizedDescription } ?? error.localizedDescription
                set(id) { $0.state = .failed; $0.error = msg }; speed = 0; save(); return
            }
            if Prefs.shared.verifyHash, let sha = f.sha256 {
                set(id) { $0.state = .verifying }
                let ok = await Self.sha256(of: part) == sha
                if !ok { try? FileManager.default.removeItem(at: part); set(id) { $0.state = .failed; $0.error = L.t("dl.err.hash") }; save(); return }
                set(id) { $0.state = .running }
            }
            try? FileManager.default.removeItem(atPath: final)
            try? FileManager.default.moveItem(atPath: part.path, toPath: final)
        }
        speed = 0
        set(id) { $0.state = .done; $0.doneBytes = $0.totalBytes }
        save()
    }

    private func bytes(_ id: UUID, _ n: Int64) {
        set(id) { $0.doneBytes += n }
        tickBytes += n
        let now = Date(), dt = now.timeIntervalSince(lastTick)
        if dt >= 1 { speed = Double(tickBytes) / dt; tickBytes = 0; lastTick = now; save() }
    }

    nonisolated static func sha256(of url: URL) async -> String? {
        await Task.detached {
            guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? h.close() }
            var hasher = SHA256()
            while let d = try? h.read(upToCount: 8 << 20), !d.isEmpty { hasher.update(data: d) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
