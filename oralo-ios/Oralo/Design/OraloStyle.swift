import SwiftUI

enum OraloStyle {
    static let ink = Color(red: 0.055, green: 0.06, blue: 0.09)
    static let canvas = Color("Canvas")
    static let violet = Color(red: 0.72, green: 0.70, blue: 1)
    static let readingAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.74, green: 0.72, blue: 1, alpha: 1)
            : UIColor(red: 0.32, green: 0.30, blue: 0.83, alpha: 1)
    })
}

struct OraloGlassSurface: ViewModifier {
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduced

    func body(content: Content) -> some View {
        if reduced { content.background(Color(uiColor: .secondarySystemBackground), in: .capsule) }
        else if #available(iOS 26, *) { content.glassEffect(.regular.interactive(interactive), in: .capsule) }
        else { content.background(.regularMaterial, in: .capsule) }
    }
}

struct OraloAction: View {
    let title: String
    let symbol: String
    var prominent = false
    var compact = false
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduced

    private var button: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.title3.weight(.medium))
                if !compact { Text(title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8) }
            }
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(maxWidth: compact ? 44 : .infinity, minHeight: compact ? 44 : 56)
            .contentShape(.capsule)
        }.accessibilityLabel(title)
    }

    @ViewBuilder var body: some View {
        if #available(iOS 26, *), !reduced {
            if prominent { button.buttonStyle(.glassProminent).buttonBorderShape(.capsule) }
            else { button.buttonStyle(.glass).buttonBorderShape(.capsule) }
        } else {
            if prominent { button.buttonStyle(.borderedProminent).buttonBorderShape(.capsule) }
            else {
                button.buttonStyle(.bordered).buttonBorderShape(.capsule)
                    .background(Color(uiColor: .secondarySystemBackground), in: .capsule)
            }
        }
    }
}

struct OraloGlassGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        if #available(iOS 26, *) { GlassEffectContainer(spacing: 12) { content } }
        else { content }
    }
}
