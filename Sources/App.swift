// mUGGINFACE — point d'entrée : fenêtre principale, menu, icône colorée dans la barre de menus.
import AppKit
import SwiftUI
import Combine

@main
@MainActor
enum Main {
    static let delegate = AppDelegate()
    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var item: NSStatusItem?
    private var bag = Set<AnyCancellable>()
    private var updTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMenu()
        applyShowIn()
        showMain()
        debugLaunch()
        AppModel.shared.startScheduler()
        let dl = DownloadManager.shared
        dl.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.refreshBadge() } }.store(in: &bag)
        AppModel.shared.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.refreshBadge() } }.store(in: &bag)
        updTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in Updater.shared.tick(busy: DownloadManager.shared.activeCount > 0) }
        }
        Updater.shared.tick(busy: false)
    }

    /// Aides d'essai, actives seulement dans la version de développement (identifiant …dev).
    private func debugLaunch() {
        guard Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true else { return }
        let d = UserDefaults.standard
        if let p = d.string(forKey: "pane"), let pane = Pane(rawValue: p) { Nav.shared.pane = pane }
        if let id = d.string(forKey: "detail") { Nav.shared.open(model: id) }
        if let q = d.string(forKey: "agentask") {
            Nav.shared.pane = .agent
            Task { @MainActor in
                await AgentBridge.shared.ask(q)
                try? (AgentBridge.shared.messages.map(\.text).joined(separator: "\n---\n")).write(toFile: "/tmp/mug_agent_out.txt", atomically: true, encoding: .utf8)
            }
        }
        if let id = d.string(forKey: "prepare") {
            Task { @MainActor in
                let files = (try? await Hub.files(of: id, token: nil)) ?? []
                if let v = Hub.variants(from: files).last, let m = AppModel.shared.models[id] { AgentBridge.shared.prepareInstall(model: m, variant: v); Nav.shared.pane = .agent }
            }
        }
        if let id = d.string(forKey: "autodl") {
            Task { @MainActor in
                let files = (try? await Hub.files(of: id, token: nil)) ?? []
                if let v = Hub.variants(from: files).first, let m = AppModel.shared.models[id] ?? Optional(Model(id: id, domains: [], downloads: 0, likes: 0, trending: 0, tags: [], gated: false, format: "mlx", bits: 4)) {
                    _ = DownloadManager.shared.enqueue(model: m, variant: v); Nav.shared.pane = .downloads
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool { if !f { showMain() }; return true }

    // MARK: - Fenêtre

    func showMain() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 733), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 1000, height: 660)
            w.contentViewController = NSHostingController(rootView: ThemeRoot { ContentView() })
            // Règle Socle : taille par défaut fixe, fenêtre centrée à chaque lancement sur l'écran du pointeur (zone utile), jamais de position restaurée.
            w.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 733), display: false)   // le contrôleur SwiftUI impose sinon sa taille idéale
            let pointer = NSEvent.mouseLocation
            if let zone = (NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
                w.setFrameOrigin(NSPoint(x: zone.midX - w.frame.width / 2, y: zone.midY - w.frame.height / 2))
            }
            window = w
        }
        window?.present()
    }

    func openPane(_ p: Pane) { Nav.shared.pane = p; Nav.shared.detailID = nil; showMain() }

    // MARK: - Dock / barre de menus

    func applyShowIn() {
        let s = Prefs.shared.showIn
        NSApp.setActivationPolicy(s == .menubar ? .accessory : .regular)
        if s == .dock { if let i = item { NSStatusBar.system.removeStatusItem(i); item = nil } }
        else if item == nil { makeStatusItem() }
        if s != .menubar { NSApp.activate() }
    }

    private func makeStatusItem() {
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = it.button {
            b.image = Self.menuIcon()
            b.imagePosition = .imageLeading
            b.target = self; b.action = #selector(statusClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        item = it
    }

    /// Silhouette « m » en couleur (choix de l'utilisateur) : carré arrondi orange et « m » blanc.
    static func menuIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5)
            NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.24, alpha: 1), ending: NSColor(srgbRed: 0.85, green: 0.38, blue: 0.17, alpha: 1))?.draw(in: path, angle: -90)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .heavy), .foregroundColor: NSColor.white]
            let s = NSAttributedString(string: "m", attributes: attrs)
            let sz = s.size()
            s.draw(at: NSPoint(x: (r.width - sz.width) / 2, y: (r.height - sz.height) / 2 + 0.5))
            NSColor(srgbRed: 1, green: 0.84, blue: 0.2, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 13.0, y: 2.64, width: 2.29, height: 2.29)).fill()
            return true
        }
        img.isTemplate = false
        return img
    }

    private func refreshBadge() {
        guard let b = item?.button else { return }
        let dl = DownloadManager.shared
        if let a = dl.active { b.title = " \(Int(a.progress * 100)) %" }
        else if AppModel.shared.unreadCount > 0 { b.title = " \(AppModel.shared.unreadCount)" }
        else { b.title = "" }
    }

    @objc private func statusClicked() {
        guard let b = item?.button else { return }
        let m = buildStatusMenu()
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: b.isFlipped ? b.bounds.maxY + 4 : -4), in: b)
    }

    private func buildStatusMenu() -> NSMenu {
        let m = NSMenu()
        let app = AppModel.shared
        let news = app.events.filter { !$0.read && ($0.kind == .new || $0.kind == .enter) }.prefix(3)
        let head = NSMenuItem(title: news.isEmpty ? L.t("menu.nonews") : L.t("watch.title", app.unreadCount), action: nil, keyEquivalent: "")
        head.isEnabled = false; m.addItem(head)
        for e in news {
            let name = e.modelID.split(separator: "/").last.map(String.init) ?? e.modelID
            let i = NSMenuItem(title: "  " + name, action: #selector(openModel(_:)), keyEquivalent: ""); i.target = self; i.representedObject = e.modelID; m.addItem(i)
        }
        if let a = DownloadManager.shared.active {
            m.addItem(.separator())
            let d = NSMenuItem(title: L.t("menu.downloading", a.modelID.split(separator: "/").last.map(String.init) ?? "", Int(a.progress * 100)), action: #selector(openDownloads), keyEquivalent: ""); d.target = self; m.addItem(d)
        }
        m.addItem(.separator())
        func add(_ t: String, _ a: Selector, _ k: String = "") { let i = NSMenuItem(title: t, action: a, keyEquivalent: k); i.target = self; m.addItem(i) }
        add(L.t("menu.open"), #selector(openMain))
        add(L.t("menu.refresh"), #selector(refreshNow))
        add(L.t("menu.settings"), #selector(openSettings))
        add(L.t("menu.about"), #selector(about))
        m.addItem(.separator())
        add(L.t("menu.quit"), #selector(quit))
        return m
    }

    @objc private func openMain() { showMain() }
    @objc private func openDownloads() { openPane(.downloads) }
    @objc private func openSettings() { openPane(.settings) }
    @objc private func refreshNow() { Task { await AppModel.shared.scan() } }
    @objc private func about() { About.show() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openModel(_ s: NSMenuItem) { if let id = s.representedObject as? String { showMain(); Nav.shared.open(model: id) } }

    // MARK: - Menu principal

    private func buildMenu() {
        let main = NSMenu()
        func item(_ t: String, _ a: Selector?, _ k: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k); i.keyEquivalentModifierMask = mods; i.target = target; return i
        }
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu()
        app.addItem(item(L.t("menu.about"), #selector(about), target: self))
        app.addItem(.separator())
        app.addItem(item(L.t("menu.settings"), #selector(openSettings), ",", target: self))
        app.addItem(.separator())
        app.addItem(item(L.t("menu.hide"), #selector(NSApplication.hide(_:)), "h"))
        app.addItem(item(L.t("menu.quit"), #selector(NSApplication.terminate(_:)), "q"))
        appItem.submenu = app
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: L.t("menu.edit"))
        edit.addItem(item(L.t("menu.undo"), Selector(("undo:")), "z"))
        edit.addItem(item(L.t("menu.redo"), Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item(L.t("menu.cut"), #selector(NSText.cut(_:)), "x"))
        edit.addItem(item(L.t("menu.copy"), #selector(NSText.copy(_:)), "c"))
        edit.addItem(item(L.t("menu.paste"), #selector(NSText.paste(_:)), "v"))
        edit.addItem(item(L.t("menu.selectall"), #selector(NSText.selectAll(_:)), "a"))
        editItem.submenu = edit
        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: L.t("menu.window"))
        win.addItem(item(L.t("menu.minimize"), #selector(NSWindow.miniaturize(_:)), "m"))
        win.addItem(item(L.t("menu.zoom"), #selector(NSWindow.zoom(_:))))
        winItem.submenu = win
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }
}
