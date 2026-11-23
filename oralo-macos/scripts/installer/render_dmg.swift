import AppKit

// Original installer artwork. Finder provides the actual draggable file icons.
// swift render_dmg.swift <output-directory> <Oralo.icns> <version-label>
guard CommandLine.arguments.count == 4 else {
    fatalError("Usage: render_dmg.swift <output-directory> <Oralo.icns> <version-label>")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let appIcon = NSImage(contentsOfFile: CommandLine.arguments[2])!
let version = CommandLine.arguments[3]
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let canvas = NSSize(width: 620, height: 408)
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let cream = color(0xFAF7F0), ink = color(0x242328), muted = color(0x75727A)
let indigo = color(0x5155ED), lilac = color(0xEBE8FF), paper = color(0xFFFEFB)
func rounded(_ rect: NSRect, _ radius: CGFloat, _ fill: NSColor, stroke: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill(); path.fill()
    if let stroke { stroke.setStroke(); path.lineWidth = 1; path.stroke() }
}
func text(_ value: String, _ rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = ink, align: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = align
    paragraph.lineBreakMode = .byClipping
    (value as NSString).draw(in: rect, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: paragraph
    ])
}
func image(_ image: NSImage, _ rect: NSRect) {
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
               respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
}
func drawScene(preview: Bool) {
    cream.setFill(); NSRect(origin: .zero, size: canvas).fill()
    text("Oralo", NSRect(x: 28, y: 24, width: 564, height: 44), size: 32, weight: .bold, align: .center)
    text("Your next line. At your pace.", NSRect(x: 28, y: 76, width: 564, height: 25), size: 14, color: muted, align: .center)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 273, y: 207))
    arrow.curve(to: NSPoint(x: 346, y: 199), controlPoint1: NSPoint(x: 296, y: 220), controlPoint2: NSPoint(x: 322, y: 195))
    arrow.move(to: NSPoint(x: 335, y: 189)); arrow.line(to: NSPoint(x: 348, y: 199))
    arrow.line(to: NSPoint(x: 333, y: 207))
    arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    indigo.setStroke(); arrow.stroke()
    text("拖入应用程序，接着讲。", NSRect(x: 28, y: 307, width: 564, height: 27), size: 18, weight: .medium, align: .center)
    text("Drag into Applications, then open Oralo there.", NSRect(x: 28, y: 340, width: 564, height: 22), size: 12, color: muted, align: .center)
    text("macOS 15+ · Apple silicon & Intel · \(version)", NSRect(x: 28, y: 372, width: 564, height: 17), size: 10, color: muted, align: .center)
    text("TEST BUILD · 未公证测试版", NSRect(x: 28, y: 391, width: 564, height: 15), size: 9, color: muted, align: .center)
    if preview {
        image(appIcon, NSRect(x: 116, y: 150, width: 96, height: 96))
        image(NSWorkspace.shared.icon(forFile: "/Applications"), NSRect(x: 408, y: 150, width: 96, height: 96))
        text("Oralo", NSRect(x: 90, y: 262, width: 148, height: 24), size: 13, align: .center)
        text("Applications", NSRect(x: 382, y: 262, width: 148, height: 24), size: 13, align: .center)
    }
}

for (filename, scale, preview) in [("background.png", 1, false), ("background@2x.png", 2, false), ("installer-preview.png", 2, true)] {
    let artwork = NSImage(size: canvas, flipped: true) { _ in drawScene(preview: preview); return true }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width) * scale,
                              pixelsHigh: Int(canvas.height) * scale, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    artwork.draw(in: NSRect(origin: .zero, size: canvas))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
}
print("Rendered installer background at 1× / 2× and a layout preview.")
