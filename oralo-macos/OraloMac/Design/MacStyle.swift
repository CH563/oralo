import SwiftUI
import OraloCore

enum MacCopy {
    static func error(_ error: Error) -> String {
        if let cocoa = error as? CocoaError, cocoa.code == .fileWriteOutOfSpace { return text("储存空间不足，请腾出空间后重试。", "Storage is full. Free some space and try again.") }
        return text(error.localizedDescription)
    }
    static func text(_ english: String) -> String {
        guard chinese, let translated = MacErrorCopy.translations[english] else { return english }
        return text(translated, english)
    }
    static var chinese: Bool { (Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first)?.hasPrefix("zh") == true }
    static var traditional: Bool { (Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first).map { $0.contains("Hant") || $0.hasPrefix("zh-TW") || $0.hasPrefix("zh-HK") || $0.hasPrefix("zh-MO") } ?? false }
    static var sampleLanguage: String { chinese ? (traditional ? "zh-Hant" : "zh-Hans") : "en" }
    static func text(_ zh: String, _ en: String) -> String {
        guard chinese else { return en }
        return traditional ? zh.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? zh : zh
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
    }
    static func event(_ kind: RehearsalEvent.Kind) -> String {
        switch kind {
        case .previous: text("上一句", "Back")
        case .next: text("下一句", "Next")
        case .selection: text("手动选句", "Manual cue")
        case .hold: text("自由发挥", "Off script")
        case .silence: text("较长停顿", "Long pause")
        case .reread: text("重读", "Reread")
        case .interruption: text("识别中断", "Recognition interrupted")
        case .manualMode: text("切换手动", "Switched to manual")
        }
    }
    static func reviewStatus(_ status: PronunciationReview.Status) -> String {
        switch status {
        case .added: text("已添加注音", "Reading added")
        case .kept: text("已检查，无需添加", "Checked, no addition needed")
        case .ignored: text("已暂时忽略", "Skipped for now")
        }
    }
    @MainActor static func metrics(_ text: String, preferences: MacPreferences? = nil) -> String {
        let metrics = ScriptMetrics(text: text)
        guard metrics.characters + metrics.words > 0 else {
            return Self.text("0 字 · 时长待估算", "0 words · Duration —")
        }
        let minutes = max(1, Int(metrics.estimatedMinutes(preferences: preferences?.estimates ?? ReadingPreferences()).rounded(.up)))
        var parts: [String] = []
        if metrics.characters > 0 { parts.append(chinese ? "\(metrics.characters) 字" : "\(metrics.characters) characters") }
        if metrics.words > 0 { parts.append(chinese ? "\(metrics.words) 词" : "\(metrics.words) \(metrics.words == 1 ? "word" : "words")") }
        parts.append(chinese ? "约 \(minutes) 分钟" : "About\u{00A0}\(minutes)\u{00A0}min")
        let result = parts.joined(separator: " · ")
        return Self.text(result, result)
    }
}

enum MacStyle {
    static let accent = Color(red: 0.314, green: 0.337, blue: 0.961)
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.067, green: 0.078, blue: 0.129)
            : Color(red: 0.980, green: 0.969, blue: 0.945)
    }
}

extension View {
    @ViewBuilder func oraloActionStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { self.buttonStyle(.glassProminent).tint(MacStyle.accent) }
            else { self.buttonStyle(.glass).tint(nil) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent).tint(MacStyle.accent) }
            else { self.buttonStyle(.bordered).tint(nil) }
        }
    }
    @ViewBuilder func oraloGlass() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            self.background(.regularMaterial, in: .rect(cornerRadius: 20))
        }
    }
}

struct SoundWave: View {
    let levels: [Float]
    let active: Bool
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, value in
                Capsule().fill(active ? MacStyle.accent : Color.secondary.opacity(0.35))
                    .frame(width: 3, height: active ? max(3, CGFloat(value) * 23) : 3)
            }
        }
        .frame(height: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MacCopy.text("麦克风音量", "Microphone level"))
        .accessibilityIdentifier("sound-wave")
        .accessibilityValue(active ? MacCopy.text("正在收音", "Listening") : MacCopy.text("已暂停", "Paused"))
    }
}
