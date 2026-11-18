import AppKit
let size = 1024
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
    let body = NSBezierPath(roundedRect: r.insetBy(dx: 100, dy: 100), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.24, alpha: 1), ending: NSColor(srgbRed: 0.85, green: 0.38, blue: 0.17, alpha: 1))?.draw(in: body, angle: -90)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 600, weight: .heavy), .foregroundColor: NSColor.white]
    let s = NSAttributedString(string: "m", attributes: attrs)
    let sz = s.size()
    s.draw(at: NSPoint(x: (r.width - sz.width) / 2, y: (r.height - sz.height) / 2 + 8))
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
