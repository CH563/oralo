import SwiftUI

struct AppEntryView: View {
    @AppStorage private var completed: Bool

    init() {
        var preferences = UserDefaults.standard
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-library=") }),
           let id = UUID(uuidString: String(argument.dropFirst("--ui-library=".count))),
           let isolated = UserDefaults(suiteName: "com.ch563.oralo.ui.\(id.uuidString)") {
            preferences = isolated
        }
        #endif
        _completed = AppStorage(wrappedValue: false, "welcome.completed.v1", store: preferences)
    }

    var body: some View {
        if completed { ScriptLibraryView() }
        else { WelcomeView { completed = true } }
    }
}
