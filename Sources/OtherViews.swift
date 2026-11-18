// mUGGINFACE — favoris, veille, téléchargements, agent IA, matériel.
import SwiftUI
import AppKit

struct PaneTitle: View {
    var text: String; var trailing: AnyView = AnyView(EmptyView())
    var body: some View { HStack { Text(text).font(.system(size: 18, weight: .bold)); Spacer(); trailing } }
}

struct FavoritesView: View {
    @Environment(\.pal) var p
    @ObservedObject var app = AppModel.shared
    var body: some View {
        let rows = app.favorites.sorted().compactMap { app.models[$0] }.map { app.row($0) }
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(text: L.t("nav.favorites"))
            if rows.isEmpty { Spacer(); Text(L.t("fav.empty")).foregroundColor(p.text2).frame(maxWidth: .infinity); Spacer() }
            else { ScrollView { LazyVStack(spacing: 8) { ForEach(rows) { ModelRow(row: $0) } } } }
        }.padding(16)
    }
}

struct WatchView: View {
    @Environment(\.pal) var p
    @ObservedObject var app = AppModel.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(text: L.t("watch.title", app.unreadCount), trailing: AnyView(Button(L.t("watch.markread")) { app.markAllRead() }.buttonStyle(.mat)))
            if app.events.isEmpty {
                Text(L.t("watch.empty")).foregroundColor(p.text2).card().frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(app.events) { e in
                            HStack(spacing: 12) {
                                Tag(text: L.t("ev." + e.kind.rawValue), kind: e.kind == .new ? .new : e.kind == .rise ? .ok : e.kind == .enter ? .ok : .plain).frame(width: 90, alignment: .leading)
                                Button { Nav.shared.open(model: e.modelID) } label: {
                                    (Text(e.modelID.split(separator: "/").last.map(String.init) ?? e.modelID).fontWeight(.semibold) + Text(" · " + eventText(e))).multilineTextAlignment(.leading)
                                }.buttonStyle(.plain)
                                Spacer()
                                Text(L.date(e.date)).font(.system(size: 12)).foregroundColor(p.text2)
                            }.padding(.vertical, 9).opacity(e.read ? 0.6 : 1)
                            Rectangle().fill(p.border).frame(height: 1)
                        }
                    }.card(12)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(text: L.t("watch.freq"))
                    Field(L.t("watch.hour")) { Picker("", selection: $prefs.scanHour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d h", $0)).tag($0) } }.labelsHidden().frame(width: 90) }
                    Toggle(L.t("watch.notify"), isOn: $prefs.notify).toggleStyle(MatSwitch())
                }.card().frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(text: L.t("watch.alerts"))
                    Toggle(L.t("watch.mydomains"), isOn: $prefs.onlyMyDomains).toggleStyle(MatSwitch())
                    Toggle(L.t("watch.compatible"), isOn: $prefs.onlyCompatible).toggleStyle(MatSwitch())
                }.card().frame(maxWidth: .infinity)
            }
        }.padding(16).font(.system(size: 13))
    }

    private func eventText(_ e: WatchEvent) -> String {
        let dom = Domain(rawValue: e.domain).map { L.t($0.titleKey) } ?? e.domain
        switch e.kind {
        case .new, .enter: return L.t("ev.text.enter", e.rank ?? 0, dom)
        case .rise: return L.t("ev.text.rise", e.from ?? 0, e.rank ?? 0, dom)
        case .removed: return L.t("ev.text.removed", dom)
        }
    }
}

struct DownloadsView: View {
    @Environment(\.pal) var p
    @ObservedObject var dl = DownloadManager.shared
    @ObservedObject var prefs = Prefs.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(text: L.t("nav.downloads"), trailing: AnyView(Text(L.t("dl.disk", gbText(Hardware.diskFree(path: prefs.modelsPath)), prefs.modelsDir)).font(.system(size: 12)).foregroundColor(p.text2)))
            if dl.items.isEmpty { Spacer(); Text(L.t("dl.empty")).foregroundColor(p.text2).frame(maxWidth: .infinity); Spacer() }
            else { ScrollView { VStack(spacing: 8) { ForEach(dl.items) { item in itemRow(item) } } } }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(text: L.t("dl.before"))
                    Text("✓ " + L.t("dl.before.disk")); Text("✓ " + L.t("dl.before.fit")); Text("✓ " + L.t("dl.before.token"))
                }.font(.system(size: 12)).card().frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(text: L.t("dl.after"))
                    Toggle(L.t("dl.after.verify"), isOn: $prefs.verifyHash).toggleStyle(MatSwitch())
                    Toggle(L.t("dl.after.agent"), isOn: $prefs.offerAgentTest).toggleStyle(MatSwitch())
                }.font(.system(size: 12)).card().frame(maxWidth: .infinity)
            }
        }.padding(16)
    }

    private func itemRow(_ it: DownloadItem) -> some View {
        HStack(spacing: 14) {
            Text(it.modelID.split(separator: "/").last.map { String($0.prefix(1)).uppercased() } ?? "?").font(.system(size: 15, weight: .bold)).foregroundColor(p.onAcc)
                .frame(width: 40, height: 40).background(p.acc).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(it.modelID.split(separator: "/").last.map(String.init) ?? it.modelID).font(.system(size: 14, weight: .semibold))
                    Text("· " + it.label).foregroundColor(p.text2)
                    stateTag(it)
                }
                Text(subtitle(it)).font(.system(size: 12)).foregroundColor(p.text2).lineLimit(2)
                if it.state != .done { Bar(value: it.progress, height: 8) }
            }
            HStack(spacing: 6) {
                switch it.state {
                case .running, .queued, .verifying: Button(L.t("dl.pause")) { dl.pause(it.id) }.buttonStyle(.mat)
                case .paused, .failed: Button(L.t("dl.resume")) { dl.resume(it.id) }.buttonStyle(.matPrimary)
                case .done:
                    Button(L.t("dl.show")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: it.destDir)]) }.buttonStyle(.mat)
                    if prefs.offerAgentTest { Button(L.t("dl.test")) { testWithAgent(it) }.buttonStyle(.mat) }
                }
                Button("✕") { dl.remove(it.id) }.buttonStyle(.mat)
            }
        }.card(12)
    }

    private func stateTag(_ it: DownloadItem) -> some View {
        switch it.state {
        case .done: return Tag(text: L.t("dl.state.done"), kind: .ok)
        case .paused: return Tag(text: L.t("dl.state.paused"), kind: .warn)
        case .failed: return Tag(text: L.t("dl.state.failed"), kind: .danger)
        case .verifying: return Tag(text: L.t("dl.state.verifying"))
        case .queued: return Tag(text: L.t("dl.state.queued"))
        case .running: return Tag(text: L.t("dl.state.running"), kind: .new)
        }
    }

    private func subtitle(_ it: DownloadItem) -> String {
        let done = gbText(Double(it.doneBytes) / 1_073_741_824), total = gbText(Double(it.totalBytes) / 1_073_741_824)
        switch it.state {
        case .done: return L.t("dl.sub.done", total, it.destDir)
        case .failed: return it.error ?? ""
        case .running:
            let sp = dl.speed
            let eta = sp > 0 ? Double(it.totalBytes - it.doneBytes) / sp : 0
            return L.t("dl.sub.running", done, total, Int(it.progress * 100), String(format: "%.0f", sp / 1_048_576), eta > 0 ? "\(Int(eta / 60)) min \(Int(eta) % 60) s" : "…")
        default: return L.t("dl.sub.paused", done, total)
        }
    }

    private func testWithAgent(_ it: DownloadItem) {
        let a = AgentBridge.shared
        a.draftPrompt = L.t("agent.testprompt", it.modelID, it.destDir, a.hardwareLine(), L.languageName)
        a.runLog = ""
        Nav.shared.pane = .agent
    }
}

struct AgentView: View {
    @Environment(\.pal) var p
    @ObservedObject var agent = AgentBridge.shared
    @ObservedObject var prefs = Prefs.shared
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(text: L.t("nav.agent"), trailing: AnyView(HStack(spacing: 8) {
                Tag(text: agentName(agent.kind), kind: ready ? .ok : .warn)
                Menu {
                    ForEach(AgentKind.allCases, id: \.self) { k in Button((agent.kind == k ? "✓ " : "") + agentName(k)) { prefs.agent = k.rawValue } }
                } label: { Text(L.t("agent.change")) }.menuStyle(.button).buttonStyle(.mat).fixedSize()
            }))
            HStack(alignment: .top, spacing: 12) { chat.frame(maxWidth: .infinity); installBox.frame(width: 380) }
        }.padding(16).font(.system(size: 13))
        .onAppear { if !agent.prefill.isEmpty { input = agent.prefill; agent.prefill = "" } }
    }

    private var ready: Bool {
        switch agent.kind { case .claudeAPI: return agent.apiKey?.isEmpty == false; case .custom: return !prefs.customAgentCmd.isEmpty; case .claudeCode: return true }
    }

    private var chat: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L.t("agent.chat"))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if agent.messages.isEmpty { Text(L.t("agent.hint")).foregroundColor(p.text2) }
                        ForEach(agent.messages) { m in bubble(m).id(m.id) }
                        if agent.busy { HStack { ProgressView().controlSize(.small); Text(L.t("agent.thinking")).foregroundColor(p.text2) } }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.onChange(of: agent.messages.count) { _ in if let l = agent.messages.last { proxy.scrollTo(l.id) } }
            }
            HStack(spacing: 8) {
                TextField(L.t("agent.placeholder"), text: $input).textFieldStyle(.plain).padding(.horizontal, 10).padding(.vertical, 8)
                    .background(p.ctl).clipShape(RoundedRectangle(cornerRadius: 8)).onSubmit(send)
                Button(L.t("agent.send")) { send() }.buttonStyle(.matPrimary).disabled(agent.busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.card()
    }

    private func bubble(_ m: ChatMessage) -> some View {
        VStack(alignment: m.role == .user ? .trailing : .leading, spacing: 6) {
            Text(m.text).textSelection(.enabled).padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundColor(m.role == .user ? p.onAcc : m.role == .system ? p.danger : p.text)
                .background(m.role == .user ? p.acc : p.ctl).clipShape(RoundedRectangle(cornerRadius: 12))
            if m.role == .agent, let id = m.modelID, AppModel.shared.models[id] != nil {
                HStack { Button(L.t("agent.seecard")) { Nav.shared.open(model: id) }.buttonStyle(.mat) }
            }
        }.frame(maxWidth: .infinity, alignment: m.role == .user ? .trailing : .leading)
    }

    private func send() {
        let q = input.trimmingCharacters(in: .whitespaces); guard !q.isEmpty, !agent.busy else { return }
        input = ""; Task { await agent.ask(q) }
    }

    private var installBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: L.t("agent.install"))
            if agent.draftPrompt.isEmpty { Text(L.t("agent.install.hint")).foregroundColor(p.text2) }
            else {
                TextEditor(text: $agent.draftPrompt).font(.system(size: 11.5, design: .monospaced)).scrollContentBackground(.hidden)
                    .padding(6).background(p.ctl).clipShape(RoundedRectangle(cornerRadius: 8)).frame(minHeight: 150, maxHeight: 220)
                Field(L.t("agent.workdir")) { Text(prefs.modelsDir).fontWeight(.semibold) }
                Field(L.t("agent.dest")) { Text(agentName(agent.kind)).fontWeight(.semibold) }
                HStack {
                    Button(L.t("btn.copy")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(agent.draftPrompt, forType: .string) }.buttonStyle(.mat)
                    Button(L.t("agent.send.install")) { Task { await agent.sendDraft() } }.buttonStyle(.matPrimary).disabled(agent.busy).frame(maxWidth: .infinity)
                }
                Text(L.t("agent.safety")).font(.system(size: 11)).foregroundColor(p.text2)
                if agent.busy { HStack { ProgressView().controlSize(.small); Text(L.t("agent.running")).foregroundColor(p.text2) } }
                if let e = agent.lastError { Text(e).font(.system(size: 12)).foregroundColor(p.danger).textSelection(.enabled) }
                if !agent.runLog.isEmpty && !agent.busy {
                    ScrollView { Text(agent.runLog).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 160).padding(8).background(p.ctl).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Spacer(minLength: 0)
        }.card()
    }
}

func agentName(_ k: AgentKind) -> String {
    switch k { case .claudeCode: return "Claude Code"; case .claudeAPI: return L.t("agent.api"); case .custom: return L.t("agent.custom") }
}

struct HardwareView: View {
    @Environment(\.pal) var p
    @ObservedObject var app = AppModel.shared
    @ObservedObject var prefs = Prefs.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(text: L.t("nav.hardware"))
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle(text: L.t("hw.detected"))
                Field(L.t("hw.chip")) { Text(app.hw.chip).fontWeight(.semibold) }
                Field(L.t("hw.mem")) { Text(gbText(app.hw.memGB)).fontWeight(.semibold) }
                Field(L.t("hw.bandwidth")) { Text(L.t("unit.gbs", Int(app.hw.bandwidthGBs))).fontWeight(.semibold) }
                Field(L.t("hw.disk")) { Text(gbText(app.hw.diskFreeGB)).fontWeight(.semibold) }
                Field(L.t("hw.usable")) { Text(gbText(app.usableGB)).fontWeight(.semibold) }
            }.card()
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: L.t("hw.adjust"))
                Field(L.t("hw.reserved")) { Stepper(value: $prefs.reservedGB, in: 4...64, step: 2) { Text(gbText(prefs.reservedGB)).fontWeight(.semibold) }.onChange(of: prefs.reservedGB) { _ in app.objectWillChange.send() } }
                Field(L.t("hw.manual")) {
                    Stepper(value: $prefs.manualMemGB, in: 0...512, step: 8) { Text(prefs.manualMemGB == 0 ? L.t("hw.auto") : gbText(prefs.manualMemGB)).fontWeight(.semibold) }
                        .onChange(of: prefs.manualMemGB) { _ in app.applyManualMemory() }
                }
                Text(L.t("hw.note")).font(.system(size: 11)).foregroundColor(p.text2)
            }.card()
            Spacer()
        }.frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity).padding(16).font(.system(size: 13))
    }
}
