import SwiftUI

struct AppEntryView: View {
    @AppStorage private var completed: Bool

    init() {
        let preferences = ReadingPreferencesStore.defaults
        _completed = AppStorage(wrappedValue: false, "welcome.completed.v1", store: preferences)
    }

    var body: some View {
        Group {
            if completed { ScriptLibraryView() }
            else { WelcomeView { completed = true } }
        }
        .onAppear {
            #if DEBUG
            // Device-lab launches only, so iterative Camera checks do not
            // require changing the user's system Auto-Lock preference.
            if ProcessInfo.processInfo.arguments.contains("--ui-keep-awake") {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            #endif
        }
    }
}
