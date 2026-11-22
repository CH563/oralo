import OraloCore
import SwiftUI

struct ScriptMetricsView: View {
    let text: String
    var preferences = ReadingPreferencesStore.shared
    @State private var metrics = ScriptMetrics(text: "")
    private var counts: String {
        let chars = metrics.characters.formatted(), words = metrics.words.formatted()
        if metrics.words == 0 { return AppCopy.bilingual("\(chars) 字", "\(chars) characters") }
        if metrics.characters == 0 { return AppCopy.bilingual("\(words) 英文词", "\(words) words") }
        return AppCopy.bilingual("\(chars) 字 · \(words) 英文词", "\(chars) characters · \(words) words")
    }
    private var estimate: String {
        switch metrics.duration(preferences: preferences.value) {
        case .empty: return AppCopy.bilingual("添加正文后估算", "Add text for an estimate")
        case .underOneMinute: return AppCopy.bilingual("约 1 分钟以内", "Est. under 1 min")
        case .minutes(let value): return AppCopy.bilingual("约 \(value) 分钟", "Est. \(value) min")
        case .range(let low, let high): return AppCopy.bilingual("约 \(low)–\(high) 分钟", "Est. \(low)–\(high) min")
        }
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { Text(counts); Label(estimate, systemImage: "clock") }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) { Text(counts); Label(estimate, systemImage: "clock") }
        }.font(.caption).foregroundStyle(.secondary)
            .accessibilityElement(children: .combine).accessibilityIdentifier("script-metrics")
            .task(id: text) {
                let content = text
                let value = await Task.detached(priority: .userInitiated) { ScriptMetrics(text: content) }.value
                guard !Task.isCancelled else { return }
                metrics = value
            }
    }
}

struct SpeakingEstimateSettings: View {
    var preferences = ReadingPreferencesStore.shared
    private func t(_ zh: String, _ en: String) -> String { AppCopy.bilingual(zh, en) }
    var body: some View {
        Form {
            Section {
                LabeledContent(t("中文", "Chinese"), value: t("\(Int(preferences.value.chineseCharactersPerMinute)) 字 / 分钟", "\(Int(preferences.value.chineseCharactersPerMinute)) characters / min"))
                Slider(value: Binding(get: { preferences.value.chineseCharactersPerMinute }, set: { value in preferences.update { $0.chineseCharactersPerMinute = value } }), in: 160...320, step: 10) {
                    Text(t("中文估算语速", "Chinese estimate pace"))
                }.accessibilityIdentifier("estimate-chinese-pace")
                LabeledContent(t("英文", "English"), value: t("\(Int(preferences.value.englishWordsPerMinute)) 词 / 分钟", "\(Int(preferences.value.englishWordsPerMinute)) words / min"))
                Slider(value: Binding(get: { preferences.value.englishWordsPerMinute }, set: { value in preferences.update { $0.englishWordsPerMinute = value } }), in: 100...220, step: 10) {
                    Text(t("英文估算语速", "English estimate pace"))
                }.accessibilityIdentifier("estimate-english-pace")
            } footer: {
                Text(t("按正文朗读估算，不含自由发挥、问答和长停顿。数字和缩写的读法也会影响时长。", "Estimated from reading the script. Ad-libs, questions and long pauses add time. Numbers and abbreviations can take longer to say."))
            }
            Section {
                Text(t("这里只调整预计时长，AI 仍跟随你的语速。", "This changes the estimate only. AI following stays at your pace."))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(t("恢复默认估算", "Reset estimate pace")) {
                    preferences.update { $0.chineseCharactersPerMinute = 240; $0.englishWordsPerMinute = 140 }
                }
            }
        }.navigationTitle(t("预计演讲时长", "Speaking estimate")).navigationBarTitleDisplayMode(.inline)
    }
}

struct PresentationOptionsView: View {
    var preferences = ReadingPreferencesStore.shared
    @Environment(\.dismiss) private var dismiss
    private func t(_ zh: String, _ en: String) -> String { AppCopy.bilingual(zh, en) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(t("左右镜像", "Mirror text"), isOn: Binding(get: { preferences.value.mirrorsText }, set: { value in preferences.update { $0.mirrorsText = value } }))
                        .accessibilityIdentifier("mirror-text")
                    Text(t("接着讲，自在一点。", "Your words. Your pace."))
                        .font(.title2.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 20)
                        .scaleEffect(x: preferences.value.mirrorsText ? -1 : 1, y: 1)
                        .accessibilityLabel(t("镜像效果预览", "Mirror preview"))
                } footer: {
                    Text(t("用于镜面提词设备。正文、注音和高亮一起翻转；按钮保持正常，开关不会改变阅读位置。", "For a teleprompter mirror. Text, readings and highlights flip together. Controls stay readable and your position is kept."))
                }
            }.navigationTitle(t("演讲选项", "Presentation options")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("完成", "Done")) { dismiss() }.accessibilityIdentifier("close-presentation-options") } }
        }.tint(OraloStyle.readingAccent)
    }
}
