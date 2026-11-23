import AVFoundation
import SwiftUI
import OraloCore

struct ReadingSelection: Identifiable {
    let id = UUID()
    let range: NSRange
    var replacing: Pronunciation? = nil
}

@MainActor @Observable final class MacPronunciationPlayer {
    private let synthesizer = AVSpeechSynthesizer()
    var error: String?
    func play(term: String, kind: Pronunciation.Kind) {
        stop(); error = nil
        guard let voice = AVSpeechSynthesisVoice(language: kind == .pinyin ? "zh-CN" : "en-US") else {
            error = MacCopy.text("此语言的系统语音不可用，仍可保存注音。", "The system voice is unavailable. You can still save the reading."); return
        }
        let utterance = AVSpeechUtterance(string: term)
        utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        synthesizer.speak(utterance)
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

struct ReadingSheet: View {
    let editor: ScriptEditorModel
    let selection: ReadingSelection
    var willPlay: () -> Void = {}
    var didSave: (Pronunciation) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var reading = ""
    @State private var reference: PronunciationReference?
    @State private var player = MacPronunciationPlayer()
    @State private var error: String?
    @State private var saving = false
    @State private var showInPresentation = true
    private var existing: Pronunciation? { selection.replacing ?? editor.document.pronunciation(at: selection.range) }
    private var range: NSRange { selection.replacing != nil ? selection.range : (existing?.span?.nsRange ?? selection.range) }
    private var term: String { (try? editor.document.pronunciationSelection(range)) ?? "" }
    private var kind: Pronunciation.Kind { PronunciationCopy.kind(for: term) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(MacCopy.text("读音辅助", "Pronunciation")).font(.title2.bold())
            Text(term).font(.title.bold())
            TextField(kind == .pinyin ? MacCopy.text("中文拼音", "Pinyin") : "IPA", text: $reading)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("pronunciation-field")
            HStack {
                Button(MacCopy.text("试听原词", "Listen to word"), systemImage: "speaker.wave.2") { willPlay(); player.play(term: term, kind: kind) }
                    .accessibilityIdentifier("pronunciation-listen")
                Text(MacCopy.text("系统朗读原词；手工注音不改变合成发音。", "System voice reads the word; custom notation does not change synthesis."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle(MacCopy.text("演讲时显示注音", "Show reading while speaking"), isOn: $showInPresentation)
            if let reference { Text(reference.source).font(.caption).foregroundStyle(.secondary) }
            if let message = error ?? player.error { Text(message).foregroundStyle(.red).font(.callout) }
            HStack {
                if let existing {
                    Button(MacCopy.text("移除注音", "Remove reading"), role: .destructive) {
                        editor.change { $0.removePronunciation(existing.id) }
                        saveAndClose()
                    }.disabled(saving)
                }
                Spacer()
                Button(MacCopy.text("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(MacCopy.text("保存", "Save")) {
                    let value = Pronunciation(id: existing?.id ?? UUID(), span: TextSpan(range), term: term,
                        reading: reading, kind: kind, referenceReading: reference?.candidates.first,
                        source: reference?.source ?? "manual", showInPresentation: showInPresentation, context: contextText)
                    saving = true
                    Task {
                        if await editor.savePronunciation(value) { editor.reattachingReading = nil; didSave(value); dismiss() }
                        else { error = editor.actionError ?? editor.error }
                        saving = false
                    }
                }.oraloActionStyle(prominent: true).disabled(reading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                    .keyboardShortcut(.defaultAction).accessibilityIdentifier("pronunciation-save")
            }
        }
        .padding(28).frame(width: 500).tint(MacStyle.accent).oraloActionStyle()
        .task {
            let result = await PronunciationLookup.shared.reference(for: term, kind: kind)
            showInPresentation = existing?.showInPresentation ?? true
            reference = result; reading = existing?.reading ?? result.candidates.first ?? ""
        }
        .onDisappear { player.stop() }
    }
    private var contextText: String {
        let text = editor.document.text
        guard let selected = Range(range, in: text) else { return "" }
        let start = text.index(selected.lowerBound, offsetBy: -20, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(selected.upperBound, offsetBy: 20, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end])
    }
    private func saveAndClose() {
        saving = true
        Task {
            if await editor.flush() { dismiss() } else { error = editor.error }
            saving = false
        }
    }
}
