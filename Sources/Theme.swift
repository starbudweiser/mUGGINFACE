// mUGGINFACE — design Flat Mat (clair / sombre) : palette, cartes, boutons, puces, étiquettes, interrupteur.
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

struct Palette {
    var bg, card, ctl, text, text2, acc, onAcc, brand, ok, warn, danger, border: Color
    static let light = Palette(bg: Color(hex: 0xF4F1EC), card: .white, ctl: Color(hex: 0xEBE6DE), text: Color(hex: 0x26231E), text2: Color(hex: 0x7B756A),
                               acc: Color(hex: 0x26231E), onAcc: Color(hex: 0xF4F1EC), brand: Color(hex: 0xD9622B), ok: Color(hex: 0x3F8F5A),
                               warn: Color(hex: 0xB7791F), danger: Color(hex: 0xB93A2E), border: Color(hex: 0xE3DDD2))
    static let dark = Palette(bg: Color(hex: 0x1D1B18), card: Color(hex: 0x272420), ctl: Color(hex: 0x33302A), text: Color(hex: 0xF1EDE5), text2: Color(hex: 0x9D968A),
                              acc: Color(hex: 0xF1EDE5), onAcc: Color(hex: 0x1D1B18), brand: Color(hex: 0xF08A52), ok: Color(hex: 0x6FCF8F),
                              warn: Color(hex: 0xE0B04A), danger: Color(hex: 0xF0796C), border: Color(hex: 0x38342D))
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.light }
extension EnvironmentValues { var pal: Palette { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } } }

/// Racine : applique le thème choisi (auto / clair / sombre) et injecte la palette.
struct ThemeRoot<Content: View>: View {
    @ObservedObject var prefs = Prefs.shared
    @Environment(\.colorScheme) private var scheme
    let content: Content
    init(@ViewBuilder _ c: () -> Content) { content = c() }
    var body: some View {
        let dark: Bool = {
            switch prefs.appearance { case .light: return false; case .dark: return true; case .auto: return scheme == .dark }
        }()
        content
            .environment(\.pal, dark ? .dark : .light)
            .preferredColorScheme(prefs.appearance == .auto ? nil : (dark ? .dark : .light))
    }
}

struct MatCard: ViewModifier {
    @Environment(\.pal) var p
    var pad: CGFloat = 14
    func body(content: Content) -> some View {
        content.padding(pad).background(p.card).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.border, lineWidth: 1))
    }
}
extension View { func card(_ pad: CGFloat = 14) -> some View { modifier(MatCard(pad: pad)) } }

struct MatButton: ButtonStyle {
    @Environment(\.pal) var p
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundColor(primary ? p.onAcc : p.text)
            .background(primary ? p.acc : p.ctl)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
extension ButtonStyle where Self == MatButton {
    static var mat: MatButton { MatButton() }
    static var matPrimary: MatButton { MatButton(primary: true) }
}

struct Tag: View {
    enum Kind { case plain, new, ok, warn, danger }
    @Environment(\.pal) var p
    var text: String; var kind: Kind = .plain
    var body: some View {
        let (bg, fg): (Color, Color) = {
            switch kind {
            case .plain: return (p.ctl, p.text2)
            case .new: return (p.brand, .white)
            case .ok: return (p.ok.opacity(0.2), p.ok)
            case .warn: return (p.warn.opacity(0.2), p.warn)
            case .danger: return (p.danger.opacity(0.2), p.danger)
            }
        }()
        Text(text).font(.system(size: 10.5, weight: .semibold)).foregroundColor(fg)
            .padding(.horizontal, 8).padding(.vertical, 2).background(bg).clipShape(Capsule())
    }
}

struct Chip: View {
    @Environment(\.pal) var p
    var text: String; var on: Bool; var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) { if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }; Text(text) }
                .font(.system(size: 12.5, weight: on ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundColor(on ? p.onAcc : p.text).background(on ? p.acc : p.ctl).clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}

struct Bar: View {
    @Environment(\.pal) var p
    var value: Double; var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(p.ctl)
                Capsule().fill(p.acc).frame(width: max(0, g.size.width * min(1, max(0, value))))
            }
        }.frame(height: height)
    }
}

struct MatSwitch: ToggleStyle {
    @Environment(\.pal) var p
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? p.acc : p.ctl).frame(width: 36, height: 20)
                Circle().fill(configuration.isOn ? p.onAcc : p.text2).frame(width: 16, height: 16).padding(2)
            }
            .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { configuration.isOn.toggle() } }
        }
    }
}

struct SectionTitle: View {
    @Environment(\.pal) var p
    var text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundColor(p.text2) }
}

/// « mUGGINFACE » avec son « m » dans la couleur du logo.
struct BrandName: View {
    @Environment(\.pal) var p
    var size: CGFloat = 15
    var body: some View {
        (Text("m").foregroundColor(p.brand) + Text("UGGINFACE").foregroundColor(p.text)).font(.system(size: size, weight: .bold))
    }
}

struct Field: View {
    @Environment(\.pal) var p
    var label: String
    var content: AnyView
    init<V: View>(_ label: String, @ViewBuilder _ c: () -> V) { self.label = label; content = AnyView(c()) }
    var body: some View {
        HStack { Text(label).foregroundColor(p.text2); Spacer(); content }.font(.system(size: 13)).padding(.vertical, 3)
    }
}
