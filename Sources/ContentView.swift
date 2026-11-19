// mUGGINFACE — fenêtre principale : barre du haut, navigation latérale, volets.
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case reco, favorites, watch, downloads, agent, hardware, settings
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .reco: return "sparkles"; case .favorites: return "star"; case .watch: return "bell"; case .downloads: return "arrow.down.circle"
        case .agent: return "bubble.left.and.text.bubble.right"; case .hardware: return "cpu"; case .settings: return "gearshape"
        }
    }
}

@MainActor
final class Nav: ObservableObject {
    static let shared = Nav()
    @Published var pane: Pane = .reco
    @Published var detailID: String?
    func open(model id: String) { pane = .reco; detailID = id }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > b.maxX, x > b.minX { x = b.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

struct ContentView: View {
    @Environment(\.pal) var p
    @ObservedObject var nav = Nav.shared
    @ObservedObject var app = AppModel.shared
    @ObservedObject var dl = DownloadManager.shared

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 8) {
                sidebar.background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.card))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
                paneView.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.win))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            }.padding(.horizontal, 8).padding(.bottom, 8)
        }
        .background(p.bg).foregroundColor(p.text)
        .ignoresSafeArea(.container, edges: .top)   // la barre du haut partage la ligne des boutons de fenêtre
        .frame(minWidth: 1000, minHeight: 660)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            BrandName(size: 15)
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(app.scanError == nil ? p.ok : p.warn).frame(width: 8, height: 8)
                Text(statusText).font(.system(size: 12)).foregroundColor(p.text2)
                if app.scanning { Spinner() }
                Button(L.t("btn.refresh")) { Task { await app.scan() } }.buttonStyle(.mat).disabled(app.scanning)
            }
        }
        .padding(.horizontal, 16).padding(.leading, 62).frame(height: 30).padding(.top, 0).padding(.bottom, 8)   // centré sur l'axe des boutons de fenêtre
    }

    private var statusText: String {
        if app.scanning { return L.t("veille.scanning") }
        if let e = app.scanError, app.lastScan == nil { return L.t("veille.error", e) }
        guard let d = app.lastScan else { return L.t("veille.never") }
        if Date().timeIntervalSince(d) < 60 { return L.t("veille.now") }
        let f = RelativeDateTimeFormatter(); f.locale = L.locale; f.unitsStyle = .short
        return L.t("veille.last", f.localizedString(for: d, relativeTo: Date()))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            navItem(.reco, count: nil)
            navItem(.favorites, count: app.favorites.isEmpty ? nil : app.favorites.count, brand: false)
            navItem(.watch, count: app.unreadCount == 0 ? nil : app.unreadCount, brand: true)
            navItem(.downloads, count: dl.activeCount == 0 ? nil : dl.activeCount, brand: true)
            navItem(.agent, count: nil)
            navItem(.hardware, count: nil)
            Rectangle().fill(p.border).frame(height: 1).padding(.vertical, 8).padding(.horizontal, 4)
            navItem(.settings, count: nil)
            Button { About.show() } label: {
                HStack { Image(systemName: "info.circle").frame(width: 18); Text(L.t("menu.about.short")); Spacer() }
                    .font(.system(size: 13)).foregroundColor(p.text2).padding(.horizontal, 10).padding(.vertical, 8)
            }.buttonStyle(.plain)
            Spacer()
        }
        .padding(10).frame(width: 214)
    }

    private func navItem(_ pane: Pane, count: Int?, brand: Bool = false) -> some View {
        let on = nav.pane == pane
        return Button { nav.pane = pane; if pane != .reco { nav.detailID = nil } } label: {
            HStack {
                Image(systemName: pane.symbol).frame(width: 18)
                Text(L.t("nav." + pane.rawValue)).lineLimit(1)
                Spacer()
                if let c = count {
                    Text("\(c)").font(.system(size: 11, weight: .bold)).foregroundColor(brand ? .white : p.text2)
                        .padding(.horizontal, 7).background(brand ? p.brand : Color.clear).clipShape(Capsule())
                }
            }
            .font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundColor(on ? p.text : p.text2)
            .padding(.horizontal, 10).padding(.vertical, 8).background(on ? p.ctl : Color.clear).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.buttonStyle(.plain)
    }

    /// Règle Socle : rien n'est collé à gauche ; le contenu se centre dans sa zone, à une largeur de lecture limitée.
    private func centered<V: View>(_ maxW: CGFloat, @ViewBuilder _ v: () -> V) -> some View {
        v().frame(maxWidth: maxW, maxHeight: .infinity, alignment: .topLeading).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var paneView: some View {
        switch nav.pane {
        case .reco: centered(900) { if let id = nav.detailID { DetailView(id: id) } else { RecoView() } }
        case .favorites: centered(820) { FavoritesView() }
        case .watch: centered(820) { WatchView() }
        case .downloads: centered(820) { DownloadsView() }
        case .agent: centered(1000) { AgentView() }
        case .hardware: HardwareView()
        case .settings: SettingsView()
        }
    }
}
