#!/usr/bin/env swift
// Package the approved iOS artwork for macOS; no network or third-party packages.
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = root.deletingLastPathComponent().appending(path: "oralo-ios/Oralo/Assets.xcassets/AppIcon.appiconset/oralo-icon-1024.png")
let resources = root.appending(path: "OraloMac/Resources")
guard let source = NSImage(contentsOf: sourceURL) else { fatalError("Approved iOS icon is missing") }
let temporary = FileManager.default.temporaryDirectory.appending(path: "OraloIcons-\(UUID().uuidString)")
let iconset = temporary.appending(path: "Oralo.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

// Keep the original artwork unchanged inside the macOS icon's rounded tile and margin.
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
        NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).addClip()
        source.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appending(path: "icon_\(size)x\(size)\(suffix).png"))
    }
}
let conversion = Process()
conversion.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
conversion.arguments = ["-c", "icns", iconset.path, "-o", resources.appending(path: "Oralo.icns").path]
try conversion.run(); conversion.waitUntilExit()
guard conversion.terminationStatus == 0 else { fatalError("Could not package the app icon") }

// A filled silhouette has enough visual weight beside other menu-bar icons.
// Quotes, reading lines and the folded corner are transparent cutouts, not white
// paint, so the system template tint remains correct on any menu-bar background.
var bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
let pdfURL = resources.appending(path: "MenuBarMark.pdf")
let context = CGContext(pdfURL as CFURL, mediaBox: &bounds, nil)!
context.beginPDFPage(nil)
context.translateBy(x: 0, y: 20); context.scaleBy(x: 1, y: -1)
let s: CGFloat = 19 / 700
context.translateBy(x: (20 - 575 * s) / 2 - 218 * s, y: (20 - 688 * s) / 2 - 161 * s)
context.scaleBy(x: s, y: s)
context.setFillColor(CGColor(gray: 0, alpha: 1))
let outline = CGMutablePath()
outline.move(to: CGPoint(x: 461, y: 161))
outline.addLine(to: CGPoint(x: 655, y: 161))
outline.addCurve(to: CGPoint(x: 793, y: 310), control1: CGPoint(x: 746, y: 161), control2: CGPoint(x: 793, y: 209))
outline.addLine(to: CGPoint(x: 793, y: 613))
outline.addCurve(to: CGPoint(x: 655, y: 788), control1: CGPoint(x: 793, y: 719), control2: CGPoint(x: 762, y: 760))
outline.addLine(to: CGPoint(x: 665, y: 849))
outline.addCurve(to: CGPoint(x: 550, y: 785), control1: CGPoint(x: 615, y: 836), control2: CGPoint(x: 581, y: 812))
outline.addCurve(to: CGPoint(x: 343, y: 799), control1: CGPoint(x: 486, y: 801), control2: CGPoint(x: 390, y: 805))
outline.addCurve(to: CGPoint(x: 218, y: 638), control1: CGPoint(x: 250, y: 793), control2: CGPoint(x: 218, y: 734))
outline.addLine(to: CGPoint(x: 218, y: 413))
outline.addCurve(to: CGPoint(x: 262, y: 302), control1: CGPoint(x: 218, y: 368), control2: CGPoint(x: 229, y: 336))
outline.addLine(to: CGPoint(x: 369, y: 195))
outline.addCurve(to: CGPoint(x: 461, y: 161), control1: CGPoint(x: 400, y: 165), control2: CGPoint(x: 425, y: 161))
outline.closeSubpath()
let mark = CGMutablePath()
mark.addPath(outline)
let fold = CGMutablePath()
fold.move(to: CGPoint(x: 438, y: 197))
fold.addCurve(to: CGPoint(x: 396, y: 289), control1: CGPoint(x: 429, y: 226), control2: CGPoint(x: 433, y: 272))
fold.addCurve(to: CGPoint(x: 277, y: 322), control1: CGPoint(x: 357, y: 307), control2: CGPoint(x: 317, y: 297))
mark.addPath(fold.copy(strokingWithWidth: 30, lineCap: .round, lineJoin: .round, miterLimit: 1))
let quote = CGMutablePath()
quote.move(to: CGPoint(x: 531, y: 428))
quote.addCurve(to: CGPoint(x: 485, y: 380), control1: CGPoint(x: 506, y: 426), control2: CGPoint(x: 485, y: 407))
quote.addCurve(to: CGPoint(x: 531, y: 329), control1: CGPoint(x: 485, y: 349), control2: CGPoint(x: 507, y: 329))
quote.addCurve(to: CGPoint(x: 581, y: 391), control1: CGPoint(x: 562, y: 329), control2: CGPoint(x: 581, y: 356))
quote.addCurve(to: CGPoint(x: 515, y: 469), control1: CGPoint(x: 581, y: 429), control2: CGPoint(x: 556, y: 460))
quote.addCurve(to: CGPoint(x: 506, y: 446), control1: CGPoint(x: 500, y: 472), control2: CGPoint(x: 493, y: 456))
quote.addCurve(to: CGPoint(x: 531, y: 428), control1: CGPoint(x: 520, y: 438), control2: CGPoint(x: 527, y: 432))
quote.closeSubpath(); mark.addPath(quote)
var shift = CGAffineTransform(translationX: 132, y: -18)
mark.addPath(quote.copy(using: &shift)!)
let lines = CGMutablePath()
lines.move(to: CGPoint(x: 328, y: 552)); lines.addLine(to: CGPoint(x: 693, y: 541))
lines.move(to: CGPoint(x: 328, y: 650)); lines.addLine(to: CGPoint(x: 632, y: 640))
mark.addPath(lines.copy(strokingWithWidth: 50, lineCap: .round, lineJoin: .round, miterLimit: 1))
context.addPath(mark); context.drawPath(using: .eoFill)
context.endPDFPage(); context.closePDF()
print("Generated Oralo.icns and MenuBarMark.pdf from the approved brand.")
