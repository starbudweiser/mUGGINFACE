// mUGGINFACE — recommandations : liste filtrée par domaines et matériel, fiche détaillée d'un modèle.
import SwiftUI
import AppKit

func fitKind(_ l: FitLevel) -> Tag.Kind {
    switch l { case .smooth: return .ok; case .ok: return .ok; case .limit: return .warn; case .heavy: return .danger; case .unknown: return .plain }
}
func gbText(_ g: Double?) -> String {
    guard let g = g else { return "?" }
    if g < 1 { return L.t("unit.mb", String(format: "%.0f", g * 1024)) }
    return g < 10 ? L.t("unit.gb", String(format: "%.1f", g)) : L.t("unit.gb", String(format: "%.0f", g))
}
func compact(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1f M", Double(n) / 1_000_000) }
    if n >= 1000 { return String(format: "%.0f k", Double(n) / 1000) }
    return "\(n)"
}

struct RecoView: View {
    @Environment(\.pal) var p
    @ObservedObject var app = AppModel.shared
    @ObservedObject var prefs = Prefs.shared
    @State private var search = ""

    var body: some View {
        let rows = app.rows(domains: prefs.domains, search: search)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(text: L.t("reco.domains"))
                    FlowLayout(spacing: 6) {
                        ForEach(Domain.allCases) { d in
                            Chip(text: L.t(d.titleKey), on: prefs.domains.contains(d)) { toggle(d) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle(text: L.t("reco.hw"))
                    Field(L.t("hw.chip")) { Text(app.hw.chip).fontWeight(.semibold) }
                    Field(L.t("hw.mem")) { Text(L.t("unit.gbof", Int(app.usableGB), Int(app.hw.memGB))).fontWeight(.semibold) }
                    Field(L.t("hw.disk")) { Text(gbText(app.hw.diskFreeGB)).fontWeight(.semibold) }
                }.card(12).frame(width: 300)
            }
            HStack(spacing: 8) {
                HStack { Image(systemName: "magnifyingglass").foregroundColor(p.text2); TextField(L.t("reco.search"), text: $search).textFieldStyle(.plain) }
                    .padding(.horizontal, 10).padding(.vertical, 7).background(p.ctl).clipShape(RoundedRectangle(cornerRadius: 8))
                Menu {
                    ForEach([5.0, 10, 20, 40, 80, 0], id: \.self) { v in
                        Button(v == 0 ? L.t("filter.nolimit") : L.t("unit.gb", String(format: "%.0f", v))) { prefs.maxWeightGB = v }
                    }
                } label: { Text(L.t("filter.weight", prefs.maxWeightGB == 0 ? L.t("filter.nolimit") : L.t("unit.gb", String(format: "%.0f", prefs.maxWeightGB)))) }
                    .menuStyle(.button).buttonStyle(.mat).fixedSize()
                Button { prefs.openLicenseOnly.toggle() } label: { Text(L.t(prefs.openLicenseOnly ? "filter.license.on" : "filter.license.off")) }.buttonStyle(.mat)
                Menu {
                    ForEach(["mlx", "gguf", "safetensors"], id: \.self) { f in
                        Button((prefs.formats.contains(f) ? "✓ " : "") + f.uppercased()) {
                            var s = prefs.formats; if s.contains(f) { s.remove(f) } else { s.insert(f) }; if s.isEmpty { s = [f] }; prefs.formats = s
                        }
                    }
                } label: { Text(L.t("filter.format")) }.menuStyle(.button).buttonStyle(.mat).fixedSize()
                Menu {
                    ForEach(SortKey.allCases, id: \.self) { k in Button((prefs.sort == k ? "✓ " : "") + L.t("sort." + k.rawValue)) { prefs.sort = k } }
                } label: { Text(L.t("sort.label", L.t("sort." + prefs.sort.rawValue))) }.menuStyle(.button).buttonStyle(.mat).fixedSize()
            }
            if rows.isEmpty { empty } else {
                ScrollView {
                    LazyVStack(spacing: 8) { ForEach(rows.prefix(80)) { r in ModelRow(row: r) } }
                }
                HStack {
                    Text(L.t("reco.count", min(rows.count, 80), rows.count)).foregroundColor(p.text2)
                    Spacer()
                    Text(L.t("reco.scoreNote")).foregroundColor(p.text2)
                }.font(.system(size: 12))
            }
        }
        .padding(16)
    }

    private func toggle(_ d: Domain) {
        var s = prefs.domains
        if s.contains(d) { s.remove(d) } else { s.insert(d) }
        prefs.domains = s
        if s.contains(d), !app.models.values.contains(where: { $0.hasDomain(d) }) { Task { await app.scan(domains: [d]) } }
    }

    @ViewBuilder private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            if app.scanning { Spinner(kind: .scanning, size: 16); Text(L.t("veille.scanning")).foregroundColor(p.text2) }
            else if let e = app.scanError { Text(L.t("veille.error", e)).foregroundColor(p.warn); Button(L.t("btn.retry")) { Task { await app.scan() } }.buttonStyle(.matPrimary) }
            else { Text(L.t("reco.empty")).foregroundColor(p.text2) }
            Spacer()
        }.frame(maxWidth: .infinity)
    }
}

struct ModelRow: View {
    @Environment(\.pal) var p
    var row: Row
    @ObservedObject var app = AppModel.shared
    var body: some View {
        let m = row.model
        Button { Nav.shared.open(model: m.id) } label: {
            HStack(spacing: 14) {
                Text(m.initial).font(.system(size: 15, weight: .bold)).foregroundColor(p.onAcc).frame(width: 40, height: 40).background(p.acc).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(m.shortName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        if app.isNew(m) { Tag(text: L.t("tag.new"), kind: .new) }
                        Tag(text: m.format.uppercased())
                        if m.gated { Tag(text: L.t("tag.gated"), kind: .warn) }
                    }
                    Text("\(m.author) · \(m.license ?? L.t("lic.unknown")) · ↓ \(compact(m.downloads)) · ♥ \(compact(m.likes))")
                        .font(.system(size: 12)).foregroundColor(p.text2).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("row.weight", gbText(m.weightsGB), gbText(row.fit.ramGB))).font(.system(size: 12)).foregroundColor(p.text2)
                    Bar(value: (row.fit.ramGB ?? 0) / max(1, app.usableGB))
                }.frame(width: 160)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.1f", row.score)).font(.system(size: 22, weight: .bold))
                    Tag(text: L.t(row.fit.level.tagKey), kind: fitKind(row.fit.level))
                }.frame(width: 110, alignment: .trailing)
            }
            .card(12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct DetailView: View {
    @Environment(\.pal) var p
    let id: String
    @ObservedObject var app = AppModel.shared
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var dl = DownloadManager.shared
    @State private var variants: [Variant] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var notice: String?
    @State private var copied = false

    var body: some View {
        if let m = app.models[id] { content(m) } else { VStack { Text(id); Button(L.t("btn.back")) { Nav.shared.detailID = nil }.buttonStyle(.mat) }.padding() }
    }

    private func content(_ m: Model) -> some View {
        let r = app.row(m)
        let rec = recommended()
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button { Nav.shared.detailID = nil } label: { Label(L.t("btn.back"), systemImage: "chevron.left") }.buttonStyle(.plain).foregroundColor(p.text2)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(m.shortName).font(.system(size: 20, weight: .bold))
                            if app.isNew(m) { Tag(text: L.t("tag.new"), kind: .new) }
                            if m.gated { Tag(text: L.t("tag.gated"), kind: .warn) }
                        }
                        Text(L.t("detail.sub", m.author, m.lastModified.map { L.date($0) } ?? "?", m.license ?? L.t("lic.unknown"), compact(m.downloads))).font(.system(size: 12)).foregroundColor(p.text2)
                    }
                    Spacer()
                    Button { app.toggleFavorite(m.id) } label: { Label(L.t(app.favorites.contains(m.id) ? "btn.unfav" : "btn.fav"), systemImage: app.favorites.contains(m.id) ? "star.fill" : "star") }.buttonStyle(.mat)
                    Button { AgentBridge.shared.prefill = L.t("agent.ask.model", m.id); Nav.shared.pane = .agent } label: { Label(L.t("btn.askAgent"), systemImage: "sparkles") }.buttonStyle(.mat)
                    Button { NSWorkspace.shared.open(URL(string: "https://huggingface.co/\(m.id)")!) } label: { Text(L.t("btn.openHF")) }.buttonStyle(.mat)
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionTitle(text: L.t("detail.score"))
                        Text(String(format: "%.1f", r.score)).font(.system(size: 26, weight: .bold)) + Text(" / 10").font(.system(size: 13)).foregroundColor(p.text2)
                        Text(L.t("detail.score.sub", String(format: "%.1f", Scoring.performance(m)))).font(.system(size: 12)).foregroundColor(p.text2)
                    }.card().frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        SectionTitle(text: L.t("detail.onmac"))
                        Text(L.t(r.fit.level.tagKey)).font(.system(size: 26, weight: .bold)).foregroundColor(r.fit.level == .heavy ? p.danger : r.fit.level == .limit ? p.warn : p.ok)
                        Text(fitSub(r)).font(.system(size: 12)).foregroundColor(p.text2)
                    }.card().frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        SectionTitle(text: L.t("detail.facts"))
                        Field(L.t("detail.params")) { Text(m.paramsB.map { String(format: "%.1f B", $0) } ?? "?").fontWeight(.semibold) }
                        Field(L.t("detail.likes")) { Text(compact(m.likes)).fontWeight(.semibold) }
                        Field(L.t("detail.format")) { Text(m.format.uppercased() + " · " + String(format: "%.1f", m.bits) + " bits").fontWeight(.semibold) }
                        Text(L.t("detail.estimated")).font(.system(size: 11)).foregroundColor(p.text2)
                    }.card().frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: L.t("detail.variants"))
                    if loading { HStack { Spinner(kind: .loading); Text(L.t("detail.loading")).foregroundColor(p.text2) } }
                    else if let e = loadError { Text(L.t("veille.error", e)).foregroundColor(p.warn) }
                    else if variants.isEmpty { Text(L.t("detail.novariant")).foregroundColor(p.text2) }
                    ForEach(variants) { v in variantRow(m, v, recommended: v.id == rec?.id) }
                    if let n = notice { Text(n).font(.system(size: 12)).foregroundColor(p.warn) }
                }.card()
                if let v = rec ?? variants.first {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(text: L.t("detail.command"))
                        Text(Hub.installCommand(id: m.id, variant: v, dir: prefs.modelsDir)).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    }.card()
                }
            }.padding(16)
        }
        .task(id: id) { await load() }
    }

    private func fitSub(_ r: Row) -> String {
        var s = r.fit.ramGB.map { L.t("detail.ram", gbText($0), gbText(app.usableGB)) } ?? L.t("detail.sizeunknown")
        if let t = r.fit.tokensPerSec { s += " · " + L.t("detail.tps", Int(t.rounded())) }
        return s
    }

    private func variantRow(_ m: Model, _ v: Variant, recommended: Bool) -> some View {
        let f = Scoring.fit(weightsGB: v.gb, domain: nil, hw: app.hw, reservedGB: prefs.reservedGB)
        return HStack(spacing: 10) {
            Text(Hub.displayLabel(v.label)).fontWeight(.semibold)
            Text(gbText(v.gb)).foregroundColor(p.text2)
            Tag(text: L.t(f.level.tagKey), kind: fitKind(f.level))
            if recommended { Tag(text: L.t("tag.recommended"), kind: .ok) }
            Spacer()
            Button(copied ? L.t("btn.copied") : L.t("btn.copy")) {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(Hub.installCommand(id: m.id, variant: v, dir: prefs.modelsDir), forType: .string); copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }.buttonStyle(.mat)
            Button(L.t("btn.sendAgent")) {
                AgentBridge.shared.prepareInstall(model: m, variant: v); Nav.shared.pane = .agent
                if !prefs.confirmBeforeSend { Task { await AgentBridge.shared.sendDraft() } }
            }.buttonStyle(.mat)
            Button(L.t("btn.download")) {
                notice = dl.enqueue(model: m, variant: v)
                if notice == nil { Nav.shared.pane = .downloads }
            }.buttonStyle(.matPrimary)
        }
        .font(.system(size: 13)).padding(.vertical, 4)
    }

    private func recommended() -> Variant? {
        let usable = app.usableGB
        let ok = variants.filter { Scoring.fit(weightsGB: $0.gb, domain: nil, hw: app.hw, reservedGB: prefs.reservedGB).level != .heavy && $0.gb * 1.1 + 1.5 <= usable * 0.85 }
        return ok.max { $0.totalBytes < $1.totalBytes }
    }

    private func load() async {
        loading = true; loadError = nil; variants = []
        do { variants = Hub.variants(from: try await Hub.files(of: id, token: app.token)) }
        catch { loadError = error.localizedDescription }
        loading = false
    }
}
