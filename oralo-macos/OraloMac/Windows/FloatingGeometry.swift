import Foundation

/// Pure geometry: camera placement uses visibleFrame, never assumes a menu-bar/notch height.
enum FloatingGeometry {
    static let minimum = CGSize(width: 360, height: 160)
    static let standard = CGSize(width: 520, height: 240)
    static let wide = CGSize(width: 680, height: 280)
    static func clamp(_ frame: CGRect, to visible: CGRect) -> CGRect {
        let width = min(max(minimum.width, frame.width), visible.width)
        let height = min(max(minimum.height, frame.height), visible.height)
        return CGRect(x: min(max(frame.minX, visible.minX), visible.maxX - width),
                      y: min(max(frame.minY, visible.minY), visible.maxY - height), width: width, height: height)
    }
    /// Keep the header reachable on smaller screens and avoid covering the prompt when space permits.
    static func settingsFrame(beside prompt: CGRect, visible: CGRect, contentSize: CGSize = CGSize(width: 340, height: 454)) -> CGRect {
        let area = visible.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: min(contentSize.width, area.width), height: min(contentSize.height, area.height))
        let centeredX = prompt.midX - size.width / 2
        let candidates = [
            CGRect(x: centeredX, y: prompt.minY - size.height - 8, width: size.width, height: size.height),
            CGRect(x: centeredX, y: prompt.maxY + 8, width: size.width, height: size.height),
            CGRect(x: prompt.maxX + 8, y: prompt.maxY - size.height, width: size.width, height: size.height),
            CGRect(x: prompt.minX - size.width - 8, y: prompt.maxY - size.height, width: size.width, height: size.height)
        ]
        for frame in candidates {
            let clamped = CGRect(x: min(max(frame.minX, area.minX), area.maxX - size.width),
                                 y: min(max(frame.minY, area.minY), area.maxY - size.height),
                                 width: size.width, height: size.height)
            if !clamped.intersects(prompt) { return clamped }
        }
        return CGRect(x: min(max(centeredX, area.minX), area.maxX - size.width),
                      y: min(max(prompt.minY - size.height - 8, area.minY), area.maxY - size.height),
                      width: size.width, height: size.height)
    }
    static func nearCamera(size: CGSize, visible: CGRect, displayCenterX: CGFloat? = nil) -> CGRect {
        clamp(CGRect(x: (displayCenterX ?? visible.midX) - size.width / 2, y: visible.maxY - size.height - 8,
                     width: size.width, height: size.height), to: visible)
    }
    static func corner(_ corner: FloatingCorner, size: CGSize, visible: CGRect) -> CGRect {
        let origin = CGPoint(x: corner.isLeft ? visible.minX + 8 : visible.maxX - size.width - 8,
                             y: corner.isTop ? visible.maxY - size.height - 8 : visible.minY + 8)
        return clamp(CGRect(origin: origin, size: size), to: visible)
    }
    static func resize(_ frame: CGRect, size: CGSize, visible: CGRect) -> CGRect {
        clamp(CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                     width: size.width, height: size.height), to: visible)
    }
}


enum FloatingSizePreset: String, CaseIterable, Identifiable {
    case compact, standard, wide
    var id: Self { self }
    var size: CGSize {
        switch self {
        case .compact: FloatingGeometry.minimum
        case .standard: FloatingGeometry.standard
        case .wide: FloatingGeometry.wide
        }
    }
    var title: String {
        switch self {
        case .compact: MacCopy.text("紧凑", "Compact")
        case .standard: MacCopy.text("标准", "Standard")
        case .wide: MacCopy.text("宽屏", "Wide")
        }
    }
}

enum FloatingCorner: String, CaseIterable, Identifiable {
    case topLeft = "top-left", topRight = "top-right", bottomLeft = "bottom-left", bottomRight = "bottom-right"
    var id: Self { self }
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
    var title: String {
        switch self {
        case .topLeft: MacCopy.text("左上角", "Top left")
        case .topRight: MacCopy.text("右上角", "Top right")
        case .bottomLeft: MacCopy.text("左下角", "Bottom left")
        case .bottomRight: MacCopy.text("右下角", "Bottom right")
        }
    }
    var symbol: String {
        switch self {
        case .topLeft: "arrow.up.left"
        case .topRight: "arrow.up.right"
        case .bottomLeft: "arrow.down.left"
        case .bottomRight: "arrow.down.right"
        }
    }
}
