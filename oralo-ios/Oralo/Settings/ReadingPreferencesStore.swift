import Foundation
import Observation
import OraloCore
import SwiftUI

@MainActor @Observable
final class ReadingPreferencesStore {
    static let shared = ReadingPreferencesStore()
    static let key = "reading.preferences.v1"
    static let defaults: UserDefaults = {
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-library=") }),
           let id = UUID(uuidString: String(argument.dropFirst("--ui-library=".count))),
           let defaults = UserDefaults(suiteName: "com.ch563.oralo.ui.\(id.uuidString)") { return defaults }
        #endif
        return .standard
    }()
    private(set) var value: ReadingPreferences
    private let defaults: UserDefaults
    init(defaults: UserDefaults = ReadingPreferencesStore.defaults) {
        self.defaults = defaults
        var loaded = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ReadingPreferences.self, from: $0) } ?? ReadingPreferences()
        loaded.normalize(); value = loaded
    }
    func update(_ edit: (inout ReadingPreferences) -> Void) {
        var next = value; edit(&next); next.normalize()
        guard next != value, let encoded = try? JSONEncoder().encode(next) else { return }
        defaults.set(encoded, forKey: Self.key); value = next
    }
    func reset() { defaults.removeObject(forKey: Self.key); value = ReadingPreferences() }
    func clearAll() {
        reset(); defaults.removeObject(forKey: "welcome.completed.v1")
    }
}

extension ReadingPreferences.Appearance {
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}
