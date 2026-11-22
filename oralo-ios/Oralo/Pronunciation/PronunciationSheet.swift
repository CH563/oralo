import OraloCore
import SwiftUI

struct PronunciationRequest: Identifiable {
    let id = UUID()
    let span: TextSpan
    let term: String
    let context: String
    var existing: Pronunciation?
}

struct PronunciationSheet: View {
    let request: PronunciationRequest
    let save: (Pronunciation) async -> String?
    let remove: (UUID) async -> String?
    @State private var reading: String
    @State private var kind: Pronunciation.Kind
    @State private var showInPresentation: Bool
    @State private var reference: PronunciationReference?
    @State private var selectedReference: String?
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var player = PronunciationPlayer()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    init(request: PronunciationRequest, save: @escaping (Pronunciation) async -> String?, remove: @escaping (UUID) async -> String?) {
        self.request = request; self.save = save; self.remove = remove
        _reading = State(initialValue: request.existing?.reading ?? "")
        _kind = State(initialValue: request.existing?.kind ?? PronunciationCopy.kind(for: request.term))
        _showInPresentation = State(initialValue: request.existing?.showInPresentation ?? true)
        _selectedReference = State(initialValue: request.existing?.referenceReading)
    }

    private func t(_ zh: String, _ en: String) -> String { PronunciationCopy.text(zh, en) }
    private var trimmed: String { reading.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var custom: Bool { !trimmed.isEmpty && trimmed != selectedReference }
    private var valid: Bool { !trimmed.isEmpty && trimmed.count <= 80 && !trimmed.contains(where: { $0.isNewline }) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(request.term).font(.largeTitle.bold()).textSelection(.enabled)
                        Text(request.context).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Menu {
                                Button(t("中文拼音", "Chinese pinyin")) { changeKind(.pinyin) }
                                Button(t("美式音标", "US English IPA")) { changeKind(.ipa) }
                            } label: { Label(kind == .pinyin ? t("拼音", "Pinyin") : t("美式音标", "US English IPA"), systemImage: "chevron.down") }
                            Spacer()
                            Text(loading ? t("查找中…", "Looking up…") : custom ? t("自定义", "Custom") : t("参考读音", "Reference"))
                        }.font(.caption).foregroundStyle(.secondary)
                        TextField(kind == .pinyin ? t("输入拼音", "Enter pinyin") : t("输入音标", "Enter IPA"), text: $reading, axis: .vertical)
                            .font(.title2.weight(.medium)).foregroundStyle(OraloStyle.readingAccent)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .lineLimit(1...4).padding(18)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
                            .accessibilityIdentifier("pronunciation-input")
                        if !loading, reference?.candidates.isEmpty != false {
                            Text(t("未找到参考读音，可以手动输入。", "No reference found. Enter your own reading."))
                                .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("pronunciation-no-match")
                        } else if let reference, reference.candidates.count > 1 {
                            Menu(t("选择其他读法", "Other pronunciations")) {
                                ForEach(reference.candidates, id: \.self) { candidate in
                                    Button(candidate) { selectedReference = candidate; reading = candidate }
                                }
                            }.font(.subheadline).accessibilityIdentifier("pronunciation-candidates")
                        }
                        if !trimmed.isEmpty && !valid {
                            Text(t("请输入 1–80 个字符，且不换行。", "Use 1–80 characters on one line."))
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                    if kind == .ipa { listening }
                    else {
                        Text(t("请确认这一处读法；多音字和姓名可以自行修改。", "Check this occurrence. You can correct names and words with multiple readings."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Divider()
                    Toggle(t("演讲时显示", "Show while speaking"), isOn: $showInPresentation)
                        .accessibilityIdentifier("pronunciation-show")
                    Text(t("仅用于此处的「\(request.term)」", "Only this occurrence of “\(request.term)”"))
                        .font(.footnote).foregroundStyle(.secondary)
                    if let existing = request.existing {
                        Button(t("删除这处读音", "Remove this reading"), role: .destructive) {
                            player.stop(); saving = true
                            Task {
                                error = await remove(existing.id); saving = false
                                if error == nil { dismiss() }
                            }
                        }.accessibilityIdentifier("pronunciation-remove")
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.orange).accessibilityIdentifier("pronunciation-error")
                    }
                }.padding(24).disabled(saving)
            }
            .background(OraloStyle.canvas)
            .navigationTitle(t("读音", "Pronunciation")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("取消", "Cancel"), systemImage: "xmark") { player.stop(); dismiss() }
                        .accessibilityIdentifier("pronunciation-cancel").disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? t("保存中…", "Saving…") : t("保存", "Save")) { commit() }
                        .disabled(!valid || saving || loading).accessibilityIdentifier("pronunciation-save")
                }
            }
        }
        .tint(OraloStyle.readingAccent)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(kind == .ipa ? 610 : 500), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
        .task(id: kind) {
            loading = true
            let result = await PronunciationLookup.shared.reference(for: request.term, kind: kind)
            guard !Task.isCancelled else { return }
            reference = result
            if selectedReference == nil { selectedReference = result.candidates.first }
            if reading.isEmpty { reading = selectedReference ?? "" }
            loading = false
        }
        .onChange(of: reading) { _, _ in player.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player.stop() } }
        .onDisappear { player.stop() }
    }

    private var listening: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    if player.playing { player.stop() } else { player.play(request.term) }
                } label: {
                    Label(player.playing ? t("停止试听", "Stop listening") : t("试听单词", "Listen to word"),
                          systemImage: player.playing ? "stop.fill" : "speaker.wave.2.fill")
                        .font(.headline).frame(minHeight: 44)
                }.disabled(custom || !player.available || loading).accessibilityIdentifier("pronunciation-listen")
                    .accessibilityValue(AppCopy.text(player.playing ? "Playing" : "Stopped"))
                Spacer()
                Text(t("美式英语", "US English")).font(.caption).foregroundStyle(.secondary)
            }
            if custom {
                Text(t("音标已修改，原示范音暂停使用。", "IPA changed. The original sample is paused."))
                    .font(.footnote).foregroundStyle(.orange)
                if let selectedReference {
                    Button(t("恢复参考读音", "Restore reference")) { reading = selectedReference }
                        .font(.footnote).accessibilityIdentifier("pronunciation-restore")
                }
            } else {
                Text(player.error ?? (!player.available ? t("美式语音暂不可用，仍可保存音标。", "US voice unavailable. You can still save IPA.") : t("系统单词示范音，仅在备稿时播放。", "System word example. Plays only while preparing.")))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func changeKind(_ value: Pronunciation.Kind) {
        guard value != kind else { return }
        player.stop(); reading = ""; reference = nil; selectedReference = nil; kind = value
    }
    private func commit() {
        player.stop(); saving = true; error = nil
        let value = Pronunciation(id: request.existing?.id ?? UUID(), span: request.span, term: request.term,
                                  reading: trimmed, kind: kind, referenceReading: selectedReference,
                                  source: custom ? "manual" : reference?.source ?? "manual",
                                  showInPresentation: showInPresentation, context: request.context)
        Task {
            error = await save(value); saving = false
            if error == nil { dismiss() }
        }
    }
}
