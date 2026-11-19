import SwiftUI

struct WelcomeColors {
    let dark: Bool
    var paper: Color { dark ? OraloStyle.canvas : Color(red: 250/255, green: 249/255, blue: 245/255) }
    var surface: Color { dark ? Color(red: 0.11, green: 0.12, blue: 0.18) : .white }
    var ink: Color { dark ? Color(red: 0.96, green: 0.95, blue: 0.92) : Color(red: 29/255, green: 29/255, blue: 32/255) }
    var secondary: Color { dark ? Color(red: 0.70, green: 0.71, blue: 0.77) : Color(red: 0.39, green: 0.39, blue: 0.37) }
    var marker: Color { dark ? Color(red: 0.23, green: 0.24, blue: 0.43) : Color(red: 222/255, green: 223/255, blue: 255/255) }
    var line: Color { dark ? .white.opacity(0.1) : Color(red: 228/255, green: 226/255, blue: 220/255) }
    var accent: Color { dark ? Color(red: 0.71, green: 0.72, blue: 1) : Color.accentColor }
}

nonisolated struct WelcomeMarker: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.height * 0.16))
        path.addQuadCurve(to: CGPoint(x: rect.maxX * 0.96, y: rect.height * 0.08),
                          control: CGPoint(x: rect.midX, y: -rect.height * 0.04))
        path.addQuadCurve(to: CGPoint(x: rect.maxX * 0.94, y: rect.height * 0.90),
                          control: CGPoint(x: rect.maxX * 1.04, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.03, y: rect.height * 0.94),
                          control: CGPoint(x: rect.midX, y: rect.maxY * 1.05))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.06, y: rect.height * 0.16),
                          control: CGPoint(x: -rect.width * 0.02, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
