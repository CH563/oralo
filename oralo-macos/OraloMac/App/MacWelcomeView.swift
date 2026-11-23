import SwiftUI
import AppKit

struct MacWelcomeView: View {
    let model: MacAppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appearsActive) private var appearsActive
    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(spacing: 24) {
            Spacer(minLength: 28)
            if let url = Bundle.main.url(forResource: "Oralo", withExtension: "icns"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 100, height: 100).accessibilityHidden(true)
            }
            Text("Oralo").font(.system(size: 24, weight: .bold, design: .rounded))
            VStack(spacing: 8) {
                Text(MacCopy.text("自然地讲，", "Speak naturally."))
                Text(MacCopy.text("按你的节奏。", "At your pace."))
                    .foregroundStyle(MacStyle.accent)
            }.font(.system(size: 44, weight: .bold, design: .rounded)).tracking(-1)
                .multilineTextAlignment(.center).accessibilityIdentifier("welcome-headline")
            Text(MacCopy.text("跟随你的声音，也接住你的临场发挥。", "Follows your voice. Finds your place when you go off script."))
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { model.route = .library } label: {
                Label(MacCopy.text("进入稿库", "Open your scripts"), systemImage: "arrow.right")
                    .font(.headline).padding(.horizontal, 22).padding(.vertical, 7)
                    // An inactive native prominent button loses its accent fill.
                    .foregroundStyle(appearsActive ? Color.white : Color.primary)
            }.oraloActionStyle(prominent: true).controlSize(.large)
                .keyboardShortcut(.defaultAction).accessibilityIdentifier("welcome-continue")
                .padding(.top, 8)
            Spacer(minLength: 28)
            Toggle(MacCopy.text("启动时显示欢迎页", "Show welcome at launch"), isOn: $preferences.showWelcome)
                .toggleStyle(.checkbox).font(.caption).foregroundStyle(.secondary)
                .fixedSize().accessibilityIdentifier("welcome-at-launch")
        }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacStyle.canvas(scheme))
    }
}
