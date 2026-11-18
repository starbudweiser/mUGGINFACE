// mUGGINFACE — réglages : général, Hugging Face, agent IA, mise à jour.
import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(\.pal) var p
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var upd = Updater.shared
    @State private var hfToken = ""
    @State private var apiKey = ""
    @State private var hfSaved = Keychain.get("hf-token") != nil
    @State private var keySaved = Keychain.get("claude-api-key") != nil
    @State private var login = AppModel.shared.launchAtLogin

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PaneTitle(text: L.t("nav.settings"))
                HStack(alignment: .top, spacing: 12) { general.frame(maxWidth: .infinity); hf.frame(maxWidth: .infinity) }
                HStack(alignment: .top, spacing: 12) { agentBox.frame(maxWidth: .infinity); update.frame(maxWidth: .infinity) }
            }.padding(16).font(.system(size: 13))
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: L.t("set.general"))
            Field(L.t("set.language")) { Text(L.t("set.language.auto", L.languageName)).foregroundColor(p.text2) }
            Field(L.t("set.appearance")) {
                Picker("", selection: $prefs.appearance) { ForEach(Appearance.allCases, id: \.self) { Text(L.t("appearance." + $0.rawValue)).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            Field(L.t("set.showin")) {
                Picker("", selection: $prefs.showIn) { ForEach(ShowIn.allCases, id: \.self) { Text(L.t("showin." + $0.rawValue)).tag($0) } }.labelsHidden().frame(width: 200)
            }
            Toggle(L.t("set.login"), isOn: Binding(get: { login }, set: { login = $0; AppModel.shared.setLaunchAtLogin($0) })).toggleStyle(MatSwitch()).padding(.vertical, 3)
            Field(L.t("set.modelsdir")) {
                HStack { Text(prefs.modelsDir).fontWeight(.semibold).lineLimit(1); Button(L.t("btn.choose")) { chooseDir() }.buttonStyle(.mat) }
            }
        }.card()
    }

    private var hf: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Hugging Face")
            Text(L.t("set.hf.help")).font(.system(size: 12)).foregroundColor(p.text2)
            HStack {
                SecureField(hfSaved ? L.t("set.keychain.saved") : "hf_…", text: $hfToken).textFieldStyle(.roundedBorder)
                Button(L.t("btn.save")) { Keychain.set("hf-token", hfToken); hfSaved = !hfToken.isEmpty; hfToken = "" }.buttonStyle(.mat).disabled(hfToken.isEmpty)
                if hfSaved { Button(L.t("btn.remove")) { Keychain.set("hf-token", nil); hfSaved = false }.buttonStyle(.mat) }
            }
            Text(L.t("set.privacy")).font(.system(size: 11)).foregroundColor(p.text2)
        }.card()
    }

    private var agentBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: L.t("nav.agent"))
            Field(L.t("agent.default")) {
                Picker("", selection: $prefs.agent) { ForEach(AgentKind.allCases, id: \.self) { Text(agentName($0)).tag($0.rawValue) } }.labelsHidden().frame(width: 200)
            }
            if prefs.agent == AgentKind.custom.rawValue {
                TextField(L.t("agent.custom.ph"), text: $prefs.customAgentCmd).textFieldStyle(.roundedBorder)
                Text(L.t("agent.custom.help")).font(.system(size: 11)).foregroundColor(p.text2)
            }
            if prefs.agent == AgentKind.claudeAPI.rawValue {
                HStack {
                    SecureField(keySaved ? L.t("set.keychain.saved") : "sk-ant-…", text: $apiKey).textFieldStyle(.roundedBorder)
                    Button(L.t("btn.save")) { Keychain.set("claude-api-key", apiKey); keySaved = !apiKey.isEmpty; apiKey = "" }.buttonStyle(.mat).disabled(apiKey.isEmpty)
                }
            }
            Toggle(L.t("agent.confirm"), isOn: $prefs.confirmBeforeSend).toggleStyle(MatSwitch())
        }.card()
    }

    private var update: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: L.t("upd.title"))
            Toggle(L.t("upd.auto"), isOn: $prefs.autoUpdate).toggleStyle(MatSwitch())
            HStack {
                Text(L.t("upd.version", upd.currentVersion)).foregroundColor(p.text2)
                Spacer()
                Text(statusText).font(.system(size: 12)).foregroundColor(p.text2)
                Button(L.t("upd.check")) { Task { await upd.check() } }.buttonStyle(.mat)
                if case .available = upd.state { Button(L.t("upd.install")) { Task { await upd.install() } }.buttonStyle(.matPrimary) }
            }
        }.card()
    }

    private var statusText: String {
        switch upd.state {
        case .idle: return ""
        case .checking: return L.t("upd.checking")
        case .upToDate: return L.t("upd.uptodate")
        case .available(let v): return L.t("upd.available", v)
        case .downloading: return L.t("upd.downloading")
        case .failed(let e): return e
        }
    }

    private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let u = panel.url { prefs.modelsDir = u.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
    }
}
