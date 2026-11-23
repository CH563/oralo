import Observation
import SwiftUI
import OraloCore

@MainActor @Observable
final class MacPreferences {
    enum Theme: String, CaseIterable { case system, light, dark }
    enum LibraryLayout: String, CaseIterable { case grid, list }
    var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "mac.theme") } }
    var libraryLayout: LibraryLayout { didSet { defaults.set(libraryLayout.rawValue, forKey: "mac.libraryLayout") } }
    var showWelcome: Bool { didSet { defaults.set(showWelcome, forKey: "mac.showWelcome") } }
    var textAlignment: ManuscriptAlignment { didSet { defaults.set(textAlignment.rawValue, forKey: "mac.textAlignment") } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "mac.font") } }
    var lineSpacing: Double { didSet { defaults.set(lineSpacing, forKey: "mac.lineSpacing") } }
    var floatingFontSize: Double { didSet { defaults.set(floatingFontSize, forKey: "mac.floatingFont") } }
    var floatingLineSpacing: Double { didSet { defaults.set(floatingLineSpacing, forKey: "mac.floatingLineSpacing") } }
    var floatingHighlight: FloatingHighlight { didSet { defaults.set(floatingHighlight.rawValue, forKey: "mac.floatingHighlight") } }
    var floatingCustomHighlight: HighlightColor { didSet { defaults.set(floatingCustomHighlight.hex, forKey: "mac.floatingCustomHighlight") } }
    var transparency: Double { didSet { defaults.set(transparency, forKey: "mac.transparency") } }
    var mirror: Bool { didSet { defaults.set(mirror, forKey: "mac.mirror") } }
    var compatibility: Bool { didSet { defaults.set(compatibility, forKey: "mac.compatibility") } }
    var colorPanelMode: Int { didSet { defaults.set(colorPanelMode, forKey: "mac.colorPanelMode") } }
    var defaultLocale: String { didSet { defaults.set(defaultLocale, forKey: "mac.defaultLocale") } }
    var followsVoice: Bool { didSet { defaults.set(followsVoice, forKey: "mac.followsVoice") } }
    var chineseRate: Double { didSet { defaults.set(chineseRate, forKey: "mac.chineseRate") } }
    var englishRate: Double { didSet { defaults.set(englishRate, forKey: "mac.englishRate") } }
    var startingMode: PromptMode { didSet { defaults.set(startingMode.rawValue, forKey: "mac.startingMode") } }
    var floatingMode: PromptMode { didSet { defaults.set(floatingMode.rawValue, forKey: "mac.floatingMode") } }
    var fixedSpeed: Double { didSet { defaults.set(fixedSpeed, forKey: "mac.fixedSpeed") } }
    @ObservationIgnored let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let language = defaults.string(forKey: "mac.defaultLocale") ?? (MacCopy.chinese ? "zh-CN" : "en-US")
        defaultLocale = ["zh-CN", "en-US"].contains(language) ? language : "en-US"
        let savedVoiceDefault = defaults.object(forKey: "mac.followsVoice") as? Bool ?? true
        followsVoice = savedVoiceDefault
        chineseRate = (defaults.object(forKey: "mac.chineseRate") as? Double ?? 240).clamped(to: 160...320)
        englishRate = (defaults.object(forKey: "mac.englishRate") as? Double ?? 140).clamped(to: 100...220)
        startingMode = PromptMode(rawValue: defaults.string(forKey: "mac.startingMode") ?? (savedVoiceDefault ? "voice" : "manual")) ?? .voice
        floatingMode = PromptMode(rawValue: defaults.string(forKey: "mac.floatingMode") ?? "voice") ?? .voice
        fixedSpeed = (defaults.object(forKey: "mac.fixedSpeed") as? Double ?? 1).clamped(to: 0.5...2)
        theme = Theme(rawValue: defaults.string(forKey: "mac.theme") ?? "system") ?? .system
        libraryLayout = LibraryLayout(rawValue: defaults.string(forKey: "mac.libraryLayout") ?? "grid") ?? .grid
        showWelcome = defaults.object(forKey: "mac.showWelcome") as? Bool ?? true
        textAlignment = ManuscriptAlignment(rawValue: defaults.string(forKey: "mac.textAlignment") ?? "left") ?? .left
        fontSize = (defaults.object(forKey: "mac.font") as? Double ?? 40).clamped(to: 24...72)
        lineSpacing = (defaults.object(forKey: "mac.lineSpacing") as? Double ?? 12).clamped(to: 0...24)
        floatingFontSize = (defaults.object(forKey: "mac.floatingFont") as? Double ?? 28).clamped(to: 18...48)
        floatingLineSpacing = (defaults.object(forKey: "mac.floatingLineSpacing") as? Double ?? 5).clamped(to: 0...24)
        floatingHighlight = FloatingHighlight(rawValue: defaults.string(forKey: "mac.floatingHighlight") ?? "indigo") ?? .indigo
        floatingCustomHighlight = defaults.string(forKey: "mac.floatingCustomHighlight").flatMap(HighlightColor.init(hex:)) ?? HighlightColor(rgb: 0x5056F5)
        mirror = defaults.bool(forKey: "mac.mirror")
        compatibility = defaults.bool(forKey: "mac.compatibility")
        let savedColorMode = defaults.object(forKey: "mac.colorPanelMode") as? Int ?? 6
        colorPanelMode = (0...7).contains(savedColorMode) ? savedColorMode : 6
        transparency = (defaults.object(forKey: "mac.transparency") as? Double ?? 0.35).clamped(to: 0...0.80)
    }
    var estimates: ReadingPreferences { ReadingPreferences(chineseCharactersPerMinute: chineseRate, englishWordsPerMinute: englishRate) }
    func resetReading() {
        fontSize = 40; lineSpacing = 12; floatingFontSize = 28; floatingLineSpacing = 5
        floatingHighlight = .indigo; floatingCustomHighlight = HighlightColor(rgb: 0x5056F5)
        transparency = 0.35; mirror = false; compatibility = false; textAlignment = .left
        followsVoice = true; defaultLocale = MacCopy.chinese ? "zh-CN" : "en-US"
        chineseRate = 240; englishRate = 140; fixedSpeed = 1; startingMode = .voice; floatingMode = .voice; colorPanelMode = 6
        defaults.removeObject(forKey: "mac.floatingFrame")
    }
    func resetAll() {
        resetReading(); theme = .system; libraryLayout = .grid; showWelcome = true
    }
    var colorScheme: ColorScheme? { switch theme { case .system: nil; case .light: .light; case .dark: .dark } }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { isFinite ? min(range.upperBound, max(range.lowerBound, self)) : range.lowerBound }
}
