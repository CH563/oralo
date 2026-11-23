import AppKit
import SwiftUI

/// Persist an opaque sRGB value rather than archiving a platform color object.
struct HighlightColor: Equatable {
    let rgb: UInt32
    init(rgb: UInt32) { self.rgb = rgb & 0xFFFFFF }
    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let rgb = UInt32(digits, radix: 16) else { return nil }
        self.init(rgb: rgb)
    }
    var hex: String { String(format: "#%06X", rgb) }
    var nsColor: NSColor {
        NSColor(srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
                blue: Double(rgb & 255) / 255, alpha: 1)
    }
    init?(nsColor: NSColor) {
        guard let color = nsColor.usingColorSpace(.sRGB) else { return nil }
        let red = UInt32(Double(color.redComponent).clamped(to: 0...1) * 255 + 0.5)
        let green = UInt32(Double(color.greenComponent).clamped(to: 0...1) * 255 + 0.5)
        let blue = UInt32(Double(color.blueComponent).clamped(to: 0...1) * 255 + 0.5)
        self.init(rgb: (red << 16) | (green << 8) | blue)
    }
}

enum FloatingHighlight: String, CaseIterable, Identifiable {
    case indigo, blue, green, amber, rose, custom
    var id: Self { self }
    var title: String {
        switch self {
        case .indigo: MacCopy.text("靛蓝", "Indigo")
        case .blue: MacCopy.text("蓝色", "Blue")
        case .green: MacCopy.text("绿色", "Green")
        case .amber: MacCopy.text("琥珀", "Amber")
        case .rose: MacCopy.text("玫红", "Rose")
        case .custom: MacCopy.text("自定义", "Custom")
        }
    }
    func color(dark: Bool, custom: HighlightColor) -> NSColor {
        switch self {
        case .indigo:
            dark ? NSColor(red: 0.74, green: 0.72, blue: 1, alpha: 1)
                : NSColor(red: 0.314, green: 0.337, blue: 0.961, alpha: 1)
        case .blue: HighlightColor(rgb: dark ? 0x8FBFFF : 0x2165D6).nsColor
        case .green: HighlightColor(rgb: dark ? 0x88D9AB : 0x16794F).nsColor
        case .amber: HighlightColor(rgb: dark ? 0xFFD071 : 0xA05B00).nsColor
        case .rose: HighlightColor(rgb: dark ? 0xFF9BBD : 0xC03970).nsColor
        case .custom: custom.nsColor
        }
    }
}
