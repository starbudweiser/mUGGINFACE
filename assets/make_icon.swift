import AppKit
let size = 1024
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
    let k: CGFloat = 1024.0 / 18.0   // même dessin que l'icône de la barre de menus (App.swift, menuIcon), à l'échelle
    let body = NSBezierPath(roundedRect: r.insetBy(dx: 0.5 * k, dy: 0.5 * k), xRadius: 4.5 * k, yRadius: 4.5 * k)
    NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.24, alpha: 1), ending: NSColor(srgbRed: 0.85, green: 0.38, blue: 0.17, alpha: 1))?.draw(in: body, angle: -90)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14 * k, weight: .heavy), .foregroundColor: NSColor.white]
    let s = NSAttributedString(string: "m", attributes: attrs)
    let sz = s.size()
    s.draw(at: NSPoint(x: (r.width - sz.width) / 2, y: (r.height - sz.height) / 2 + 0.5 * k))
    NSColor(srgbRed: 1, green: 0.84, blue: 0.2, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 13.0 * k, y: 2.64 * k, width: 2.29 * k, height: 2.29 * k)).fill()   // pastille jaune : sans elle macOS (style sombre) noircit l'icône
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
