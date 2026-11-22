import Foundation
import OraloCore

/// Dynamic system/error strings are localized at the UI boundary, never inside the audio callback.
enum AppCopy {
    static var chinese: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true }
    static var traditional: Bool { Bundle.main.preferredLocalizations.first == "zh-Hant" }
    static func bilingual(_ zh: String, _ en: String) -> String {
        let fallback = chinese ? (traditional ? zh.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? zh : zh) : en
        return Bundle.main.localizedString(forKey: en, value: fallback, table: nil)
    }
    static func text(_ key: String) -> String { Bundle.main.localizedString(forKey: key, value: nil, table: nil) }
    static func error(_ error: Error) -> String {
        if let cocoa = error as? CocoaError {
            switch cocoa.code {
            case .fileWriteOutOfSpace: return text("Storage is full. Free some space and try again.")
            case .fileReadNoPermission, .fileWriteNoPermission: return text("The files are unavailable. Unlock this device and try again.")
            default: return text("The operation could not finish. Try again.")
            }
        }
        let key = error.localizedDescription
        let localized = text(key)
        return localized
    }
}

extension ScriptDocument {
    var localizedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppCopy.text("Untitled script") : displayTitle }
}
