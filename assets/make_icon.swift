import AppKit
let size = 1024
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
    let inset: CGFloat = 80
    let body = NSBezierPath(roundedRect: r.insetBy(dx: inset, dy: inset), xRadius: 190, yRadius: 190)
    NSGraphicsContext.current?.saveGraphicsState()
    let sh = NSShadow(); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -12); sh.shadowColor = NSColor.black.withAlphaComponent(0.35); sh.set()
    NSColor.black.setFill(); body.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.24, alpha: 1), ending: NSColor(srgbRed: 0.85, green: 0.36, blue: 0.15, alpha: 1))?.draw(in: body, angle: -90)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 640, weight: .heavy), .foregroundColor: NSColor.white]
    let s = NSAttributedString(string: "m", attributes: attrs)
    let sz = s.size()
    s.draw(at: NSPoint(x: (r.width - sz.width) / 2, y: (r.height - sz.height) / 2 + 20))
    // petite flèche de téléchargement
    let arrow = NSBezierPath()
    let cx: CGFloat = r.width - 250, cy: CGFloat = 250
    arrow.move(to: NSPoint(x: cx - 55, y: cy + 25)); arrow.line(to: NSPoint(x: cx, y: cy - 35)); arrow.line(to: NSPoint(x: cx + 55, y: cy + 25))
    arrow.move(to: NSPoint(x: cx, y: cy + 95)); arrow.line(to: NSPoint(x: cx, y: cy - 35))
    arrow.lineWidth = 26; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    NSColor(white: 1, alpha: 0.9).setStroke(); arrow.stroke()
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
