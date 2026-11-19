import OraloCore
import SwiftUI

struct ScriptEditorView: View {
    @State private var editor: ScriptEditorModel
    @State private var section = Section.text
    @State private var originalVisible = false
    @State private var resetLayout = false
    @State private var splitSegment: ScriptSegment?
    @State private var presentation: SessionPresentation?
    @State private var readiness: ReadinessRequest?
    @State private var pendingPresentation: SessionPresentation?
    @State private var historyVisible = false
    @State private var rehearseAfterDismiss = false
    @State private var reviewFocus: ScriptTextFocus?
    @State private var reviewNotice: String?
    @State private var preparing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var editingText = false
    @State private var readingPanel: ReadingPanel?
    @State private var reattaching: UUID?
    @State private var removedReading = false

    private enum ReadingPanel: Identifiable {
        case list, edit(PronunciationRequest)
        var id: String { switch self { case .list: "list"; case .edit(let request): request.id.uuidString } }
    }
    private func t(_ zh: String, _ en: String) -> String { PronunciationCopy.text(zh, en) }
    private enum Section: String, CaseIterable { case text = "Text", sentences = "Sentences" }

    init(document: ScriptDocument, library: ScriptLibraryStore) {
        _editor = State(initialValue: ScriptEditorModel(document: document, library: library))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(t("讲稿标题", "Script title"), text: Binding(get: { editor.document.title }, set: { value in editor.change { $0.title = value } }))
                    .font(.largeTitle.bold()).accessibilityIdentifier("script-title")
                saveStatus
                if let reviewNotice {
                    Label(reviewNotice, systemImage: reviewFocus == nil ? "clock.arrow.circlepath" : "scope")
                        .font(.footnote).foregroundStyle(OraloStyle.readingAccent).accessibilityIdentifier("review-edit-location")
                }
                if reattaching != nil {
                    HStack {
                        Text(t("选择新的字词，再点「读音」重新定位。", "Select the new word, then choose Pronunciation."))
                        Button(t("取消", "Cancel")) { reattaching = nil }
                    }.font(.footnote).foregroundStyle(.secondary)
                }
                if let error = editor.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.footnote)
                        Button(t("重试保存", "Retry save")) { Task { _ = await editor.flush() } }
                        ShareLink(item: editor.document.text) { Label(t("导出正文", "Export text"), systemImage: "square.and.arrow.up") }
                    }.foregroundStyle(.orange).accessibilityIdentifier("save-error")
                }
            }.padding(.horizontal, 24).padding(.top, 16)
            if section == .text { textEditor }
            else { ScrollView { sentenceLayout.padding(24) } }
        }
        .disabled(preparing)
        .background(OraloStyle.canvas)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(t("备稿", "Prepare")).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Scripts", systemImage: "chevron.left") {
                    editingText = false; preparing = true
                    Task {
                        defer { preparing = false }
                        if await editor.flush(finalizeOriginal: true) { dismiss() }
                    }
                }.accessibilityIdentifier("back-to-library").disabled(preparing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(t("排练一次", "Rehearse"), systemImage: "play.circle") { start(.voice, kind: .rehearsal) }
                        .accessibilityIdentifier("rehearse-script")
                    Button(t("讲稿记录", "Script records"), systemImage: "clock.arrow.circlepath") { editingText = false; historyVisible = true }
                        .accessibilityIdentifier("rehearsal-history")
                    Button(t("手动开讲", "Start manually"), systemImage: "hand.point.up.left") { start(.manual) }
                        .accessibilityIdentifier("start-manual")
                    Button(t("保存", "Save")) { editingText = false; Task { _ = await editor.flush(finalizeOriginal: true) } }
                        .accessibilityIdentifier("save-script")
                    Button(t("撤销修改", "Undo"), systemImage: "arrow.uturn.backward") { editor.undo(); removedReading = false }
                        .disabled(editor.history.isEmpty).accessibilityIdentifier("undo-edit")
                    Button(t("读音标注", "Pronunciations"), systemImage: "character.phonetic") { editingText = false; readingPanel = .list }
                        .accessibilityIdentifier("manage-pronunciations")
                    Button(section == .text ? t("分句排版", "Sentence layout") : t("返回正文", "Back to text")) {
                        editingText = false; section = section == .text ? .sentences : .text
                    }.accessibilityIdentifier("toggle-sentences")
                    Menu(t("识别语言", "Speech language")) {
                        Picker(t("识别语言", "Speech language"), selection: Binding(get: { editor.document.localeID }, set: { value in editor.change { $0.localeID = value } })) {
                            Text("中文 · Mandarin").tag("zh-CN")
                            Text("English · US").tag("en-US")
                        }
                    }
                    Button(t("查看原稿", "View original"), systemImage: "doc") { originalVisible = true }
                    ShareLink(item: editor.document.text) { Label(t("导出正文", "Export text"), systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel(t("讲稿选项", "Script options")).accessibilityIdentifier("script-options")
                    .disabled(preparing)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editingText = false }
            }
        }
        .safeAreaInset(edge: .bottom) { startActions }
        .sheet(item: $readingPanel) { panel in
            switch panel {
            case .list: pronunciationList
            case .edit(let request):
                PronunciationSheet(request: request, save: { value in
                    let success = await editor.savePronunciation(value)
                    if success { reattaching = nil; removedReading = false }
                    return success ? nil : editor.error ?? editor.actionError ?? t("保存失败，请重试。", "Could not save. Try again.")
                }, remove: { id in
                    editor.change { $0.removePronunciation(id) }
                    let success = await editor.flush()
                    if success { removedReading = true }
                    return success ? nil : editor.error
                })
            }
        }
        .sheet(isPresented: $originalVisible) { originalSheet }
        .sheet(item: $splitSegment) { segment in
            SplitSentenceView(segment: segment) { offset in editor.split(segment.id, at: offset) }
        }
        .confirmationDialog("Rebuild sentence layout?", isPresented: $resetLayout, titleVisibility: .visible) {
            Button("Rebuild and edit text") { editor.change { $0.rebuildSentences() }; section = .text }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This resets your manual splits and pause marks. Your words and original stay intact, and you can undo the change.") }
        .alert("Check your script", isPresented: Binding(get: { editor.actionError != nil }, set: { if !$0 { editor.actionError = nil } })) {
            Button("OK", role: .cancel) { editor.actionError = nil }
        } message: { Text(editor.actionError ?? "") }
        .sheet(item: $readiness, onDismiss: {
            if let pendingPresentation { presentation = pendingPresentation; self.pendingPresentation = nil }
        }) { request in
            ReadinessView(request: request) { mode, backend in
                do {
                    pendingPresentation = try SessionPresentation(document: request.document, kind: request.kind, mode: mode,
                                                                  backend: backend, store: editor.library.rehearsals)
                    readiness = nil
                } catch { editor.actionError = error.localizedDescription }
            }
        }
        .sheet(isPresented: $historyVisible, onDismiss: resumeRehearsalRequest) {
            RehearsalHistoryView(store: editor.library.rehearsals, current: editor.document, edit: editReviewedPassage) {
                rehearseAfterDismiss = true; historyVisible = false
            }
        }
        .fullScreenCover(item: $presentation, onDismiss: resumeRehearsalRequest) { request in
            RehearsalFlowView(request: request, current: editor.document, edit: editReviewedPassage) {
                rehearseAfterDismiss = true; presentation = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { _ = await editor.flush() } }
        }
    }

    private var saveStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: editor.error != nil ? "exclamationmark.circle" : editor.saving ? "arrow.triangle.2.circlepath" : editor.dirty ? "circle.dotted" : "checkmark.circle")
            Text(editor.error != nil ? t("未保存", "Not saved") : editor.saving ? t("保存中…", "Saving…") : editor.dirty ? t("等待保存…", "Waiting to save…") : t("已保存", "Saved on this iPhone"))
                .accessibilityIdentifier("save-status")
            if !editor.document.pronunciations.isEmpty {
                Button(t("· \(editor.document.pronunciations.count) 处读音", "· \(editor.document.pronunciations.count) readings")) {
                    editingText = false; readingPanel = .list
                }.accessibilityIdentifier("pronunciation-count")
            }
            if editor.document.pronunciations.contains(where: \.needsReview) {
                Text(t("待核对", "Needs review")).foregroundStyle(.orange).accessibilityIdentifier("reading-needs-review")
            }
            Spacer(minLength: 0)
            if removedReading {
                Button(t("撤销删除", "Undo removal")) { editor.undo(); removedReading = false }
                    .accessibilityIdentifier("undo-pronunciation-removal")
            }
        }.font(.caption).foregroundStyle(editor.error == nil ? Color.secondary : .orange)
    }

    private var textEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            PronunciationTextEditor(document: editor.document, editing: $editingText,
                                    change: editor.changeText, edit: editor.editText, selectReading: selectReading, focus: reviewFocus)
            if editor.document.hasCustomLayout {
                Button(t("编辑正文并重新分句", "Edit text & rebuild sentences"), systemImage: "pencil") { resetLayout = true }
                    .padding(.horizontal, 24)
            }
            Text(t("选中字词，点「读音」添加拼音或音标。", "Select a word, then choose Pronunciation to add a reading."))
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 4)
        }
    }

    private func selectReading(_ range: NSRange) {
        do {
            let existing = reattaching.flatMap { id in editor.document.pronunciations.first { $0.id == id } }
                ?? editor.document.pronunciation(at: range)
            let chosen = reattaching == nil ? existing?.span?.nsRange ?? range : range
            let term = try editor.document.pronunciationSelection(chosen)
            let source = editor.document.text as NSString
            let contextRange = NSRange(location: max(0, chosen.location - 16),
                                       length: min(source.length, NSMaxRange(chosen) + 20) - max(0, chosen.location - 16))
            let context = source.substring(with: source.rangeOfComposedCharacterSequences(for: contextRange))
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            editingText = false
            readingPanel = .edit(PronunciationRequest(span: TextSpan(chosen), term: term, context: context, existing: existing))
        } catch { editor.actionError = error.localizedDescription }
    }

    private var pronunciationList: some View {
        NavigationStack {
            List {
                if editor.document.pronunciations.isEmpty {
                    Text(t("选中正文中的字词，再点菜单里的「读音」。", "Select a word in your script and choose Pronunciation from the text menu."))
                        .foregroundStyle(.secondary)
                }
                ForEach(editor.document.pronunciations) { reading in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            if let span = reading.span { selectReading(span.nsRange) }
                            else { reattaching = reading.id; readingPanel = nil }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(reading.term).font(.headline).foregroundStyle(.primary)
                                Text(reading.reading).foregroundStyle(Color.accentColor)
                                if reading.needsReview {
                                    Text(t("原文已修改 · 点按重新选词", "Text changed · Tap to select a new word")).foregroundStyle(.orange)
                                } else if !reading.showInPresentation {
                                    Text(t("演讲时隐藏", "Hidden while speaking")).foregroundStyle(.secondary)
                                }
                            }
                        }.accessibilityIdentifier("reading-item-\(reading.term)")
                        if reading.needsReview {
                            Button(t("删除", "Remove"), role: .destructive) {
                                editor.change { $0.removePronunciation(reading.id) }; removedReading = true
                            }
                        }
                    }.padding(.vertical, 6)
                }
                SwiftUI.Section(t("读音来源", "Sources")) {
                    Text(t("中文：系统拼音转换，可自行校正。英文：离线 ipa-dict 美式音标。试听：系统单词示范音。", "Chinese: system transliteration, with manual corrections. English: offline ipa-dict US IPA. Audio: system word examples."))
                        .font(.footnote).foregroundStyle(.secondary)
                    NavigationLink(t("开源许可", "Open-source licenses")) {
                        ScrollView { Text(licenseText).font(.footnote).textSelection(.enabled).padding(24) }
                            .navigationTitle(t("开源许可", "Licenses"))
                    }
                }
            }.navigationTitle(t("读音标注", "Pronunciations")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("完成", "Done")) { readingPanel = nil } } }
        }
    }

    private var licenseText: String {
        ["Pronunciation-Credits", "IPA-Dict-LICENSE", "CMUDict-IPA-LICENSE", "CMUDict-LICENSE"].compactMap {
            guard let url = Bundle.main.url(forResource: $0, withExtension: "txt") else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }.joined(separator: "\n\n")
    }

    private var sentenceLayout: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            Text("\(editor.document.segments.count) sentences").font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("sentence-count")
            Text("Pause marks are reminders. Oralo still follows your voice, without timed scrolling.")
                .font(.footnote).foregroundStyle(.secondary)
            if editor.document.segments.isEmpty { Text("Add text to create sentences.").foregroundStyle(.secondary) }
            ForEach(Array(editor.document.segments.enumerated()), id: \.element.id) { index, segment in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        if segment.pauseAfter { Label("Pause", systemImage: "pause").font(.caption).foregroundStyle(Color.accentColor) }
                    }
                    Text(segment.text).font(.title3).textSelection(.enabled)
                    HStack(spacing: 16) {
                        Button("Split", systemImage: "scissors") { splitSegment = segment }
                            .disabled(segment.text.count < 2).accessibilityIdentifier("split-\(index)")
                        Button("Merge", systemImage: "arrow.down.to.line") { editor.change { $0.mergeWithNext(segment.id) } }
                            .disabled(index + 1 == editor.document.segments.count).accessibilityIdentifier("merge-\(index)")
                        Button(segment.pauseAfter ? "Unmark" : "Pause", systemImage: "pause") {
                            editor.change { $0.togglePause(segment.id) }
                        }.accessibilityIdentifier("pause-mark-\(index)")
                    }.font(.callout).buttonStyle(.borderless).frame(minHeight: 44)
                }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
            }
        }
    }

    private var startActions: some View {
        Button { start(.voice) } label: {
            Label(preparing ? t("保存中…", "Saving…") : t("开讲", "Start speaking"), systemImage: "arrow.up.right")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
        }
        .modifier(PreparePrimaryButton())
        .accessibilityIdentifier("start-voice")
        .padding(.horizontal, 24).padding(.vertical, 10).disabled(preparing)
    }

    private func start(_ mode: SpeechPrototypeView.StartMode, kind: RehearsalRecord.Kind = .presentation) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        editingText = false; preparing = true
        Task {
            defer { preparing = false }
            guard await editor.flush(finalizeOriginal: true) else { return }
            do {
                guard let saved = editor.library.documents.first(where: { $0.id == editor.document.id }) else {
                    throw ScriptLibraryError.conflict
                }
                _ = try saved.snapshot()
                readiness = ReadinessRequest(document: saved, kind: kind, manual: mode == .manual)
            } catch { editor.actionError = error.localizedDescription }
        }
    }

    private func resumeRehearsalRequest() {
        guard rehearseAfterDismiss else { return }
        rehearseAfterDismiss = false
        start(.voice, kind: .rehearsal)
    }

    private func editReviewedPassage(_ cueID: UUID?, snapshot: RehearsalSnapshot) {
        section = .text; editingText = false
        if let cueID, let span = snapshot.editRange(cueID: cueID, in: editor.document) {
            reviewFocus = ScriptTextFocus(range: span.nsRange, beginEditing: true)
            reviewNotice = t("已定位到回看的原句，点按即可编辑。", "At the passage you reviewed. Tap to edit.")
        } else {
            reviewFocus = nil
            reviewNotice = t("讲稿已更新，请选择要修改的位置。", "This script has changed. Choose where to edit.")
        }
        presentation = nil; historyVisible = false
    }

    private var originalSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(editor.document.originalText == nil ? "The original will be kept when you save or leave this draft." : "Kept separately from your speaking version.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(editor.document.originalText ?? editor.document.text).font(.body).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.navigationTitle("Original").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { originalVisible = false } } }
        }
    }
}

private struct SplitSentenceView: View {
    let segment: ScriptSegment
    let split: (Int) -> Void
    @State private var offset = 1
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section("Before the break") { Text(String(segment.text.prefix(offset))).font(.title3) }
                SwiftUI.Section("After the break") { Text(String(segment.text.dropFirst(offset))).font(.title3) }
                SwiftUI.Section {
                    Slider(value: Binding(get: { Double(offset) }, set: { offset = Int($0) }), in: 1...Double(max(2, segment.text.count - 1)), step: 1)
                        .disabled(segment.text.count < 3).accessibilityLabel("Split position")
                    Stepper("After character \(offset)", value: $offset, in: 1...max(1, segment.text.count - 1))
                } footer: { Text("The words stay exactly as written. Only the reading break changes.") }
            }.navigationTitle("Split sentence").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Split") { split(offset); dismiss() }.accessibilityIdentifier("confirm-split")
                    }
                }
                .onAppear { offset = max(1, segment.text.count / 2) }
        }.presentationDetents([.medium, .large])
    }
}

private struct PreparePrimaryButton: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) { content.buttonStyle(.glassProminent).buttonBorderShape(.capsule) }
        else { content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule) }
    }
}
