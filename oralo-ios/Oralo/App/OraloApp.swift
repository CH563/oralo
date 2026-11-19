import SwiftUI

@main
struct OraloApp: App {
    var body: some Scene {
        WindowGroup {
            Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-prototype") || ProcessInfo.processInfo.arguments.contains("--ui-reading-replay") {
                SpeechPrototypeView()
            } else if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-library=") })
                        && !ProcessInfo.processInfo.arguments.contains("--ui-welcome") {
                ScriptLibraryView()
            } else { AppEntryView() }
            #else
            AppEntryView()
            #endif
            }
            #if DEBUG
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--ui-appearance=dark") ? .dark :
                ProcessInfo.processInfo.arguments.contains("--ui-appearance=light") ? .light : nil)
            #endif
        }
    }
}
