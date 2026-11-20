// mUGGINFACE — volet Audit : modèles installés sur ce Mac comparés aux meilleurs candidats, avec historique daté.
import SwiftUI
import AppKit

struct AuditView: View {
    @Environment(\.pal) var p
    @ObservedObject var audit = AuditStore.shared
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var app = AppModel.shared
    @ObservedObject var ai = AuditAgentStore.shared
    @State private var confirmExec = false
    @State private var rollbackID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(text: L.t("audit.title"), trailing: AnyView(runButton))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if audit.entries.isEmpty && !audit.running {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.t("audit.empty")).foregroundColor(p.text2)
                            if let c = audit.current { Text(L.t("audit.last", L.date(c.date))).font(.system(size: 12)).foregroundColor(p.text2) }
                        }.frame(maxWidth: .infinity, alignment: .leading).card()
                    } else {
                        summary
                        historyCard
                        ForEach(domainsPresent, id: \.rawValue) { section($0) }
                        if !unclassified.isEmpty { sectionCard(title: L.t("audit.other"), items: unclassified) }
                    }
                    if !audit.entries.isEmpty { agentCard; planCard }
                    foldersCard
                }
            }
        }.padding(16).font(.system(size: 13))
        .task { if audit.entries.isEmpty { await audit.run() } }
        .alert(L.t("audit.plan.exec.confirm.title"), isPresented: $confirmExec) {
            Button(L.t("audit.plan.exec")) { Task { await ai.execute() } }
            Button(L.t("btn.cancel"), role: .cancel) {}
        } message: { Text(L.t("audit.plan.exec.confirm.msg", prefs.auditInstr.count + 1)) }
        .alert(L.t("audit.plan.rollback.title"), isPresented: Binding(get: { rollbackID != nil }, set: { if !$0 { rollbackID = nil } })) {
            Button(L.t("audit.plan.rollback"), role: .destructive) { if let id = rollbackID { ai.rollback(id) }; rollbackID = nil }
            Button(L.t("btn.cancel"), role: .cancel) { rollbackID = nil }
        } message: { Text(L.t("audit.plan.rollback.msg")) }
    }

    private var runButton: some View {
        HStack(spacing: 8) {
            if audit.running { Spinner(kind: .scanning); Text(L.t("audit.running")).font(.system(size: 12)).foregroundColor(p.text2) }
            Button(L.t("audit.run")) { Task { await audit.run() } }.buttonStyle(.matPrimary).disabled(audit.running)
        }
    }

    // MARK: Résumé

    private var summary: some View {
        let c = audit.current
        let delta: Double? = (c != nil && audit.previous != nil) ? c!.index - audit.previous!.index : nil
        return HStack(alignment: .top, spacing: 12) {
            stat(value: "\(audit.entries.count)", label: L.t("audit.sum.installed"), sub: String(format: "%.1f Go", audit.entries.reduce(0) { $0 + $1.installed.sizeGB }))
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: L.t("audit.sum.index"))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.0f %%", c?.index ?? 0)).font(.system(size: 26, weight: .bold))
                    if let d = delta, abs(d) >= 0.5 { Tag(text: String(format: "%+.0f pts", d), kind: d > 0 ? .ok : .warn) }
                }
                Text(L.t("audit.sum.index.help")).font(.system(size: 11)).foregroundColor(p.text2)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).card()
            stat(value: "\(audit.entries.filter { $0.verdict == .better }.count)", label: L.t("audit.sum.better"),
                 sub: L.t("audit.sum.uptodate", audit.entries.filter { $0.verdict == .upToDate }.count))
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func stat(value: String, label: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: label)
            Text(value).font(.system(size: 26, weight: .bold))
            Text(sub).font(.system(size: 11)).foregroundColor(p.text2)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).card()
    }

    // MARK: Historique

    private var historyCard: some View {
        let h = Array(audit.history.suffix(14))
        let ch = audit.changes
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: L.t("audit.history"))
            if h.count < 2 {
                Text(L.t("audit.hist.none")).font(.system(size: 12)).foregroundColor(p.text2)
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(h) { s in
                        VStack(spacing: 3) {
                            Text(String(format: "%.0f", s.index)).font(.system(size: 10)).foregroundColor(p.text2)
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(s.date == h.last?.date ? p.brand : p.acc.opacity(0.55))
                                .frame(width: 22, height: max(4, 70 * s.index / 100))
                            Text(s.date.formatted(Date.FormatStyle().day().month(.defaultDigits).locale(L.locale))).font(.system(size: 9.5)).foregroundColor(p.text2)
                        }
                    }
                    Spacer()
                }.frame(height: 100)
            }
            if !ch.added.isEmpty { Text(L.t("audit.hist.added", ch.added.map { Self.short($0) }.joined(separator: ", "))).font(.system(size: 12)).foregroundColor(p.ok) }
            if !ch.removed.isEmpty { Text(L.t("audit.hist.removed", ch.removed.map { Self.short($0) }.joined(separator: ", "))).font(.system(size: 12)).foregroundColor(p.text2) }
        }.frame(maxWidth: .infinity, alignment: .topLeading).card()
    }

    static func short(_ id: String) -> String { id.split(separator: "/").last.map(String.init) ?? id }

    // MARK: Liste par domaine

    private var domainsPresent: [Domain] { Domain.allCases.filter { d in audit.entries.contains { $0.domain == d } } }
    private var unclassified: [AuditEntry] { audit.entries.filter { $0.domain == nil } }
    private func section(_ d: Domain) -> some View { sectionCard(title: L.t(d.titleKey), items: audit.entries.filter { $0.domain == d }) }

    private func sectionCard(title: String, items: [AuditEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: title).padding(.bottom, 6)
            ForEach(items) { e in
                row(e)
                if e.id != items.last?.id { Rectangle().fill(p.border).frame(height: 1) }
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading).card()
    }

    private func row(_ e: AuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(Self.short(e.installed.id)).fontWeight(.semibold).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                Tag(text: L.t("audit.src." + e.installed.source)).frame(width: 140, alignment: .leading)
                Text(String(format: "%.1f Go", e.installed.sizeGB)).font(.system(size: 12)).foregroundColor(p.text2).frame(width: 64, alignment: .trailing)
                Text(e.score.map { String(format: "%.1f · %@", $0, L.t("audit.est")) } ?? "").font(.system(size: 12)).foregroundColor(p.text2).frame(width: 104, alignment: .trailing)
                Group {
                    switch e.verdict {
                    case .upToDate: Tag(text: L.t("audit.v.ok"), kind: .ok)
                    case .better: Tag(text: L.t("audit.v.better"), kind: .warn)
                    case .unknown: Tag(text: L.t("audit.v.unknown"))
                    }
                }.frame(width: 120, alignment: .trailing)
            }
            if e.verdict == .better, let b = e.best {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 11)).foregroundColor(p.text2)
                    Button { Nav.shared.open(model: b.model.id) } label: { Text(Self.short(b.model.id)).fontWeight(.semibold).foregroundColor(p.brand) }.buttonStyle(.plain)
                    if let g = e.gain { Tag(text: String(format: "+%.0f %%", g * 100), kind: .ok) }
                    Tag(text: L.t(b.fit.level.tagKey), kind: b.fit.level == .smooth ? .ok : .plain)
                    if let r = b.fit.ramGB { Text(String(format: "%.0f Go", r)).font(.system(size: 12)).foregroundColor(p.text2) }
                    Spacer()
                }
            }
            if let c = e.commonEval {
                Text(L.t("audit.common", c.name, String(format: "%.2f", c.mine), String(format: "%.2f", c.best))).font(.system(size: 11.5)).foregroundColor(p.text2)
            } else if !e.evals.isEmpty {
                Text(L.t("audit.measured", e.evals.count)).font(.system(size: 11.5)).foregroundColor(p.text2)
            }
        }.padding(.vertical, 8)
    }

    // MARK: Dossiers

    private var foldersCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: L.t("audit.folders"))
            Text(L.t("audit.folders.help")).font(.system(size: 11.5)).foregroundColor(p.text2)
            ForEach(prefs.auditDirs, id: \.self) { d in
                HStack {
                    Text(d).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(L.t("btn.remove")) { prefs.auditDirs = prefs.auditDirs.filter { $0 != d } }.buttonStyle(.mat)
                }
            }
            HStack {
                Button(L.t("audit.folder.add")) { addFolder() }.buttonStyle(.mat)
                Spacer()
            }
            Toggle(L.t("audit.auto"), isOn: $prefs.auditAuto).toggleStyle(MatSwitch())
            Text(L.t("audit.note")).font(.system(size: 11)).foregroundColor(p.text2)
        }.frame(maxWidth: .infinity, alignment: .topLeading).card()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = false
        if panel.runModal() == .OK, let u = panel.url {
            let d = u.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            if !prefs.auditDirs.contains(d) { prefs.auditDirs.append(d) }
        }
    }

    // MARK: Analyse de l'agent

    private var agentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: L.t("audit.ai.title"))
                Spacer()
                if ai.busyAnalysis { Spinner(kind: .thinking); Text(L.t("audit.ai.working")).font(.system(size: 12)).foregroundColor(p.text2) }
                Button(L.t(ai.analysis == nil ? "audit.ai.run" : "audit.ai.rerun")) { Task { await ai.analyze() } }.buttonStyle(.matPrimary).disabled(ai.busyAnalysis)
            }
            if let a = ai.analysis {
                Text((try? AttributedString(markdown: a, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(a))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Text(L.t("audit.ai.by", ai.analysisDate.map { L.date($0) } ?? "", ai.analysisAgent ?? "")).font(.system(size: 11)).foregroundColor(p.text2)
            } else {
                Text(L.t("audit.ai.empty")).font(.system(size: 12)).foregroundColor(p.text2)
            }
            if let e = ai.error { Text(e).font(.system(size: 12)).foregroundColor(p.danger) }
        }.frame(maxWidth: .infinity, alignment: .topLeading).card()
    }

    // MARK: Plan de mise à jour

    private var planCard: some View {
        let ups = ai.upgradeCandidates
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: L.t("audit.plan.title"))
            Text(L.t("audit.plan.help")).font(.system(size: 11.5)).foregroundColor(p.text2)
            if ups.isEmpty {
                Text(L.t("audit.plan.none")).font(.system(size: 12)).foregroundColor(p.text2)
            } else {
                ForEach(ups) { e in
                    Toggle(isOn: Binding(get: { ai.draftTargets.contains(e.id) }, set: { on in if on { ai.draftTargets.insert(e.id) } else { ai.draftTargets.remove(e.id) } })) {
                        HStack(spacing: 6) {
                            Text(Self.short(e.installed.id)).fontWeight(.semibold)
                            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundColor(p.text2)
                            Text(Self.short(e.best?.model.id ?? "")).foregroundColor(p.brand).fontWeight(.semibold)
                            if let g = e.gain { Tag(text: String(format: "+%.0f %%", g * 100), kind: .ok) }
                        }
                    }.toggleStyle(MatSwitch())
                }
                HStack {
                    if ai.busyPlan { Spinner(kind: .thinking); Text(L.t("audit.plan.preparing")).font(.system(size: 12)).foregroundColor(p.text2) }
                    Spacer()
                    Button(L.t("audit.plan.prepare")) { Task { await ai.preparePlan() } }.buttonStyle(.mat).disabled(ai.busyPlan || ai.draftTargets.isEmpty)
                }
            }
            if !ai.draftPlan.isEmpty {
                SectionTitle(text: L.t("audit.plan.review"))
                TextEditor(text: $ai.draftPlan).font(.system(size: 12)).scrollContentBackground(.hidden).padding(6)
                    .background(p.ctl).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous)).frame(height: 220)
                instrFiles
                if !ai.canExecute { Text(L.t("audit.plan.noapi")).font(.system(size: 12)).foregroundColor(p.warn) }
                HStack {
                    if ai.busyExec { Spinner(kind: .working); Text(L.t("audit.plan.exec.running")).font(.system(size: 12)).foregroundColor(p.text2) }
                    Spacer()
                    Button(L.t("audit.plan.exec")) { confirmExec = true }.buttonStyle(.matPrimary).disabled(ai.busyExec || !ai.canExecute)
                }
            }
            if let n = ai.notice { Text(n).font(.system(size: 12)).foregroundColor(p.ok).textSelection(.enabled) }
            if !ai.plans.isEmpty { planHistory }
        }.frame(maxWidth: .infinity, alignment: .topLeading).card()
    }

    private var instrFiles: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: L.t("audit.plan.files"))
            Text(L.t("audit.plan.files.help")).font(.system(size: 11)).foregroundColor(p.text2)
            ForEach(prefs.auditInstr, id: \.self) { f in
                HStack {
                    Text(f).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(L.t("btn.remove")) { prefs.auditInstr = prefs.auditInstr.filter { $0 != f } }.buttonStyle(.mat)
                }
            }
            Button(L.t("audit.plan.files.add")) { addInstr() }.buttonStyle(.mat)
        }
    }

    private var planHistory: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: L.t("audit.plan.history")).padding(.vertical, 6)
            ForEach(ai.plans) { pl in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(L.date(pl.date)).fontWeight(.semibold)
                        Tag(text: L.t("audit.plan.status." + pl.status.rawValue), kind: pl.status == .executed ? .ok : pl.status == .failed ? .danger : .plain)
                        Text(L.t("audit.plan.journal", pl.downloads.count)).font(.system(size: 12)).foregroundColor(p.text2)
                        Spacer()
                        Button(L.t("audit.plan.reveal")) { ai.reveal(pl.id) }.buttonStyle(.mat)
                        if pl.status == .executed || pl.status == .failed { Button(L.t("audit.plan.rollback")) { rollbackID = pl.id }.buttonStyle(.mat) }
                    }
                    if let r = pl.result, !r.isEmpty { Text(r).font(.system(size: 11.5)).foregroundColor(p.text2).lineLimit(4).textSelection(.enabled) }
                }.padding(.vertical, 8)
                if pl.id != ai.plans.last?.id { Rectangle().fill(p.border).frame(height: 1) }
            }
        }
    }

    private func addInstr() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for u in panel.urls {
                let d = u.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                if !prefs.auditInstr.contains(d) { prefs.auditInstr.append(d) }
            }
        }
    }
}
