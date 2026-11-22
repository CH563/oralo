import OraloCore
import SwiftUI

struct PronunciationReviewRequest: Identifiable {
    let id = UUID()
    let cueID: UUID
    let snapshot: RehearsalSnapshot
    let recordID: UUID
}

struct PronunciationReviewView: View {
    @Bindable var editor: ScriptEditorModel
    let request: PronunciationReviewRequest
    let again: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PronunciationRequest?
    @State private var selecting = false
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var saving = false
    @State private var error: String?
    @State private var previousReview: PronunciationReview?
    @State private var canUndo = false
    @State private var undoDocument = false
    @State private var pendingMark: PronunciationReview?
    private var store: RehearsalStore { editor.library.rehearsals }
    private var record: RehearsalRecord? { store.records.first { $0.id == request.recordID } }
    private var review: PronunciationReview? { record?.pronunciationReviews?.first { $0.cueID == request.cueID } }
    private var currentRange: TextSpan? { request.snapshot.editRange(cueID: request.cueID, in: editor.document) }
    private var focus: ScriptTextFocus? { currentRange.map { ScriptTextFocus(id: request.id, range: $0.nsRange) } }
    private func t(_ zh: String, _ en: String) -> String { AppCopy.bilingual(zh, en) }
    private var status: String? {
        guard let review else { return nil }
        switch review.status {
        case .ignored: return t("已忽略这次记录", "Ignored for this record")
        case .kept: return t("已保留当前读音", "Kept current readings")
        case .added:
            guard editor.document.pronunciations.contains(where: { $0.id == review.pronunciationID && $0.isAnchored(in: editor.document.text) }) else {
                return t("提示已更改，请再确认", "The hint changed. Check it again.")
            }
            return t("已添加读音提示", "Reading hint saved")
        }
    }
    private var matches: [TextSpan] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, term.count <= 40 else { return [] }
        let source = editor.document.text as NSString
        var remaining = currentRange?.nsRange ?? NSRange(location: 0, length: source.length)
        var found: [TextSpan] = []
        while remaining.length > 0 && found.count < 8 {
            let range = source.range(of: term, range: remaining)
            guard range.location != NSNotFound else { break }
            if (try? editor.document.pronunciationSelection(range)) != nil { found.append(TextSpan(range)) }
            remaining = NSRange(location: NSMaxRange(range), length: NSMaxRange(remaining) - NSMaxRange(range))
        }
        return found
    }
    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("选一个想核对的词", "Choose a word to check")).font(.title2.bold())
                    Text(t("长按选词，再点「读音」。这里由你选择要核对的词，不代表系统判断读错。", "Select a word, then choose Pronunciation. You decide what to check; this is not an automatic error finding."))
                        .font(.footnote).foregroundStyle(.secondary)
                    if currentRange == nil {
                        Label(t("讲稿已变化，请在当前正文重新选词。", "The script changed. Select the word in the current text."), systemImage: "clock.arrow.circlepath")
                            .font(.footnote).foregroundStyle(.orange).accessibilityIdentifier("pronunciation-review-script-changed")
                    }
                    TextField(t("也可以输入要查找的字词", "Or type a word to find"), text: $search)
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .focused($searchFocused)
                        .accessibilityIdentifier("review-word-search")
                    if !search.isEmpty {
                        if matches.isEmpty { Text(t("没有匹配，请确认当前正文中的写法。", "No match. Check the spelling in the current script.")).font(.footnote).foregroundStyle(.secondary) }
                        ForEach(Array(matches.enumerated()), id: \.element.location) { index, span in
                            Button { open(span.nsRange) } label: {
                                HStack {
                                    Text(context(for: span.nsRange)).lineLimit(2).multilineTextAlignment(.leading)
                                    Spacer(); Image(systemName: "character.phonetic")
                                }.font(.subheadline).frame(minHeight: 44)
                            }.accessibilityIdentifier("review-word-match-\(index)")
                        }
                    }
                }.padding(.horizontal, 24).padding(.top, 18)
                PronunciationTextEditor(document: editor.document, editing: $selecting, change: { _ in }, edit: { _, _ in }, selectReading: open, focus: focus, allowsEditing: false)
                    .frame(height: 300)
                    .accessibilityIdentifier("review-pronunciation-text")
                if let status { Label(status, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(OraloStyle.readingAccent).padding(.horizontal, 24).accessibilityIdentifier("pronunciation-review-status") }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.orange).padding(.horizontal, 24).accessibilityIdentifier("pronunciation-review-error")
                    if pendingMark != nil { Button(t("重试保存记录", "Retry saving review")) { Task { await retryMark() } }.padding(.horizontal, 24) }
                }
                actions.padding(.horizontal, 24).padding(.bottom, 12)
            }
            }.scrollDismissesKeyboard(.interactively).background(OraloStyle.canvas)
                .navigationTitle(t("核对读音", "Check pronunciation")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(t("完成", "Done")) { dismiss() }.disabled(saving).accessibilityIdentifier("close-pronunciation-review")
                } }
                .sheet(item: $selection) { value in
                    PronunciationSheet(request: value, save: saveReading, remove: removeReading)
                }
                .interactiveDismissDisabled(saving)
        }.tint(OraloStyle.readingAccent)
    }
    private var actions: some View {
        VStack(spacing: 8) {
            if canUndo { Button(t("撤销这次处理", "Undo this review")) { Task { await undo() } }.accessibilityIdentifier("undo-pronunciation-review") }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { decisionButtons }.fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 4) { decisionButtons }
            }
            SessionPrimary(title: t("再排一次", "Rehearse again"), symbol: "arrow.clockwise", id: "pronunciation-review-rehearse", action: again)
        }.disabled(saving || pendingMark != nil || record == nil)
    }
    @ViewBuilder private var decisionButtons: some View {
        Button(t("保留当前读音", "Keep current readings")) { Task { await decide(.kept) } }.frame(minHeight: 44).accessibilityIdentifier("keep-pronunciation-review")
        Button(t("这次忽略", "Ignore this time")) { Task { await decide(.ignored) } }.frame(minHeight: 44).accessibilityIdentifier("ignore-pronunciation-review")
    }
    private func context(for range: NSRange) -> String {
        let source = editor.document.text as NSString
        let contextRange = NSRange(location: max(0, range.location - 16), length: min(source.length, NSMaxRange(range) + 20) - max(0, range.location - 16))
        return source.substring(with: source.rangeOfComposedCharacterSequences(for: contextRange)).replacingOccurrences(of: "\n", with: " ")
    }
    private func open(_ range: NSRange) {
        guard !saving, pendingMark == nil else { return }
        do {
            let existing = editor.document.pronunciation(at: range)
            let span = existing?.span?.nsRange ?? range
            let term = try editor.document.pronunciationSelection(span)
            selecting = false; searchFocused = false
            selection = PronunciationRequest(span: TextSpan(span), term: term, context: context(for: span), existing: existing)
        } catch { self.error = AppCopy.error(error) }
    }
    private func historicalSpan(for range: TextSpan?) -> TextSpan? {
        guard let range, let currentRange,
              let old = request.snapshot.document.segmentSpans().first(where: { $0.0 == request.cueID })?.1,
              range.location >= currentRange.location, NSMaxRange(range.nsRange) <= NSMaxRange(currentRange.nsRange) else { return nil }
        return TextSpan(NSRange(location: old.location + range.location - currentRange.location, length: range.length))
    }
    private func saveReading(_ value: Pronunciation) async -> String? {
        guard record != nil else { return AppCopy.error(LocalDataError.staleWriter) }
        saving = true; defer { saving = false }
        previousReview = review; error = nil
        let before = editor.document.pronunciations
        guard await editor.savePronunciation(value) else { return editor.error ?? editor.actionError ?? t("保存失败，请重试。", "Could not save. Try again.") }
        undoDocument = before != editor.document.pronunciations; canUndo = true
        let mark = PronunciationReview(cueID: request.cueID, span: historicalSpan(for: value.span), pronunciationID: value.id, status: .added)
        if !(await store.setPronunciationReview(mark, cueID: request.cueID, recordID: request.recordID)) {
            // The manuscript did save. Retry only the record update, never add another hint.
            pendingMark = mark; error = t("注音已保存，记录状态未保存，请重试。", "Your hint is saved. The review status could not be saved. Please retry.")
        }
        return nil
    }
    private func removeReading(_ id: UUID) async -> String? {
        saving = true; defer { saving = false }
        previousReview = review
        let before = editor.document.pronunciations
        editor.change { $0.removePronunciation(id) }
        undoDocument = before != editor.document.pronunciations; canUndo = undoDocument
        return await editor.flush() ? nil : editor.error ?? t("保存失败，请重试。", "Could not save. Try again.")
    }
    private func retryMark() async {
        guard let pendingMark else { return }
        saving = true; defer { saving = false }
        if await store.setPronunciationReview(pendingMark, cueID: request.cueID, recordID: request.recordID) { self.pendingMark = nil; error = nil }
        else { error = store.error }
    }
    private func decide(_ status: PronunciationReview.Status) async {
        saving = true; defer { saving = false }
        let previous = review
        let mark = PronunciationReview(cueID: request.cueID, status: status)
        if await store.setPronunciationReview(mark, cueID: request.cueID, recordID: request.recordID) {
            previousReview = previous; undoDocument = false; canUndo = true; error = nil
        } else { error = store.error }
    }
    private func undo() async {
        saving = true; defer { saving = false }
        if undoDocument { editor.undo(); undoDocument = false }
        guard await editor.flush() else { error = editor.error; return }
        if await store.setPronunciationReview(previousReview, cueID: request.cueID, recordID: request.recordID) { canUndo = false; error = nil }
        else { error = store.error }
    }
}
