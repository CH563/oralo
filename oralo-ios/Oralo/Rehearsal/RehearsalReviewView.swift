import OraloCore
import SwiftUI
import UIKit

nonisolated enum SessionCopy {
    @MainActor static func reason(_ event: RehearsalEvent) -> String {
        func t(_ zh: String, _ en: String) -> String { AppCopy.bilingual(zh, en) }
        switch event.kind {
        case .silence: return t("停顿约 \(Int(event.duration.rounded())) 秒", "Quiet for about \(Int(event.duration.rounded())) seconds")
        case .reread: return t("重读了这句", "Repeated this passage")
        case .hold: return t("跟随保持位置 \(Int(event.duration)) 秒", "Position held for \(Int(event.duration)) seconds")
        case .previous: return t("手动回到此句", "Moved back here manually")
        case .next: return t("手动切到此句", "Moved forward here manually")
        default: return t("手动接回此句", "Picked up here manually")
        }
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }
}

struct SessionPresentation: Identifiable {
    let id = UUID()
    let snapshot: ScriptSnapshot
    let model: SpeechPrototypeModel
    let mode: SpeechPrototypeView.StartMode
    let recorder: RehearsalRecorder
    init(document: ScriptDocument, kind: RehearsalRecord.Kind, mode: SpeechPrototypeView.StartMode,
         backend: SpeechPrototypeModel.Backend, store: RehearsalStore) throws {
        snapshot = try document.snapshot(); self.mode = mode
        model = try SpeechPrototypeModel(snapshot: snapshot); model.backend = backend
        recorder = RehearsalRecorder(document: document, kind: kind, input: mode == .manual ? .manual : .voice, store: store)
    }
}

struct RehearsalFlowView: View {
    let request: SessionPresentation
    let current: ScriptDocument
    let edit: (UUID?, RehearsalSnapshot) -> Void
    var checkPronunciation: ((UUID, RehearsalSnapshot, UUID) -> Void)? = nil
    let again: () -> Void
    @State private var showingReview = false
    @State private var leaveAction: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if showingReview, let record = request.recorder.record {
                NavigationStack {
                    RehearsalReviewView(record: record, snapshot: request.recorder.snapshot, current: current,
                                        recorder: request.recorder, edit: { cue, snapshot in leave { edit(cue, snapshot) } },
                                        checkPronunciation: { cue, snapshot, recordID in leave { checkPronunciation?(cue, snapshot, recordID) } },
                                        again: { leave(again) }, done: { leave { dismiss() } })
                }
            } else {
                SpeechPrototypeView(model: request.model, startMode: request.mode,
                                    title: request.snapshot.title, pauseAfter: request.snapshot.pauseAfter,
                                    pronunciations: request.snapshot.pronunciations, recorder: request.recorder) {
                    if request.recorder.record == nil { dismiss() } else { showingReview = true }
                }
            }
        }.tint(OraloStyle.readingAccent)
            .onAppear { request.recorder.store.activeSessions.insert(request.id) }
            .onDisappear { request.recorder.store.activeSessions.remove(request.id) }
            .confirmationDialog(PronunciationCopy.text("记录尚未保存", "Record not saved yet"), isPresented: Binding(get: { leaveAction != nil }, set: { if !$0 { leaveAction = nil } }), titleVisibility: .visible) {
                Button(PronunciationCopy.text("放弃未保存部分并离开", "Leave without unsaved changes"), role: .destructive) { let action = leaveAction; leaveAction = nil; action?() }
                Button(PronunciationCopy.text("返回重试保存", "Go back and retry"), role: .cancel) { leaveAction = nil }
            } message: { Text(PronunciationCopy.text("已保存的部分会保留，未保存的记录离开后无法恢复。讲稿和注音不受影响。", "Any saved checkpoint is kept. Unsaved record changes cannot be recovered after leaving. Your script and readings are safe.")) }
    }
    private func leave(_ action: @escaping () -> Void) {
        if request.recorder.saved { action() } else { leaveAction = action }
    }
}

struct RehearsalReviewView: View {
    let record: RehearsalRecord
    let snapshot: RehearsalSnapshot
    let current: ScriptDocument
    var recorder: RehearsalRecorder?
    let edit: (UUID?, RehearsalSnapshot) -> Void
    var checkPronunciation: ((UUID, RehearsalSnapshot, UUID) -> Void)? = nil
    let again: () -> Void
    let done: () -> Void
    @State private var selectedID: UUID?
    @Environment(\.dynamicTypeSize) private var typeSize
    private func t(_ zh: String, _ en: String) -> String { PronunciationCopy.text(zh, en) }
    private var events: [RehearsalEvent] { record.events.filter(\.isReviewable).sorted { $0.activeOffset < $1.activeOffset } }
    private var selectedEvent: RehearsalEvent? { events.first(where: { $0.id == selectedID }) ?? events.first }
    private var saved: Bool { recorder?.saved ?? true }
    private var title: String { record.kind == .rehearsal ? t("排练复盘", "Rehearsal review") : t("演讲回看", "Presentation review") }
    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 900 && !typeSize.isAccessibilitySize {
                HStack(spacing: 0) {
                    summary(split: true).frame(width: 350)
                    Divider()
                    if let event = selectedEvent {
                        ReviewPassageView(event: event, snapshot: snapshot, current: current, embedded: true, edit: edit, checkPronunciation: checkPronunciation, record: record)
                            .id(event.id)
                    } else {
                        ContentUnavailableView(t("按自己的节奏，再试一次", "Try again at your pace"), systemImage: "text.bubble",
                            description: Text(t("有需要时再排一次。回看线索会出现在这里。", "Rehearse when you like. Passages to revisit will appear here.")))
                    }
                }
            } else { summary(split: false).frame(maxWidth: 760).frame(maxWidth: .infinity) }
        }
        .background(OraloStyle.canvas).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(t("完成", "Done"), action: done).accessibilityIdentifier("close-review") } }
    }
    @ViewBuilder private func eventLink<Label: View>(_ event: RehearsalEvent, split: Bool, @ViewBuilder label: () -> Label) -> some View {
        if split {
            Button { selectedID = event.id } label: { label() }
                .accessibilityAddTraits(selectedEvent?.id == event.id ? .isSelected : [])
        } else {
            NavigationLink { ReviewPassageView(event: event, snapshot: snapshot, current: current, edit: edit, checkPronunciation: checkPronunciation, record: record)
                .navigationTitle(t("回看原句", "Revisit passage")) } label: { label() }
        }
    }
    private var reviewActions: some View {
        VStack(spacing: 8) {
            SessionPrimary(title: t("再排一次", "Rehearse again"), symbol: "arrow.clockwise", id: "rehearse-again", action: again)
            Button(t("返回讲稿", "Back to script"), action: done).frame(minHeight: 44).accessibilityIdentifier("review-back-script")
        }.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 12).background(OraloStyle.canvas)
    }
    private func summary(split: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Label(snapshot.document.localizedTitle + " · " + record.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "doc.text")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(saved ? (record.kind == .rehearsal ? t("讲过一遍，\n更有底气。", "One rehearsal.\nA little more confidence.") : t("这次演讲，\n已保存。", "Your talk,\nsaved.")) : recorder?.saving == true ? t("正在保存\n这次记录…", "Saving your\nrecord…") : t("这次记录，\n还未保存。", "Your record\nis not saved yet."))
                        .font(.largeTitle.bold()).accessibilityIdentifier("review-save-state")
                    if record.status == .unfinished {
                        Label(t("未完成 · 保留到最后一次保存的位置", "Unfinished · Kept through the last save"), systemImage: "pause.circle")
                            .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("review-unfinished")
                    }
                    if let recorder, recorder.saveError != nil {
                        Text(t("记录仍在本页，退出前请重试保存。讲稿和注音不受影响。", "Your record is still on this screen. Retry before leaving. Your script and readings are safe."))
                            .font(.footnote).foregroundStyle(.orange)
                        Button(t("重试保存", "Retry saving")) { Task { await recorder.flush() } }.accessibilityIdentifier("retry-session-save")
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) { metrics }
                    VStack(alignment: .leading, spacing: 20) { metrics }
                }.padding(.vertical, 12)
                if record.kind == .rehearsal, let checkPronunciation {
                    NavigationLink {
                        List(snapshot.document.segments) { segment in
                            Button {
                                checkPronunciation(segment.id, snapshot, record.id)
                            } label: {
                                Text(segment.text).font(.body).foregroundStyle(.primary).padding(.vertical, 8)
                            }.accessibilityIdentifier("check-passage-\(segment.id)")
                        }.navigationTitle(t("选择要核对的句子", "Choose a passage"))
                    } label: {
                        Label(t("核对读音", "Check pronunciation"), systemImage: "character.phonetic").frame(minHeight: 44)
                    }.accessibilityIdentifier("review-pronunciation-passages")
                }
                Divider()
                VStack(alignment: .leading, spacing: 18) {
                    Text(events.isEmpty ? t("这次没有需要回看的记录。", "No passages were marked this time.") : t("这些句子，可以再看看", "A few passages to revisit")).font(.title3.bold())
                    if events.isEmpty {
                        Text(t("有需要时再排一次。没有记录不代表没有停顿，也不是演讲评分。", "Rehearse again whenever you like. An empty list is not a score or a judgment about pauses."))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(events) { event in
                        if let cue = snapshot.document.segments.first(where: { $0.id == event.cueID }) {
                            eventLink(event, split: split) {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 9) {
                                        Text(SessionCopy.duration(event.activeOffset) + " · " + SessionCopy.reason(event)).font(.caption).foregroundStyle(OraloStyle.readingAccent)
                                        Text(cue.text).font(.body.weight(.medium)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }.padding(.vertical, 8).contentShape(.rect)
                                    .padding(.horizontal, split ? 10 : 0)
                                    .background(split && selectedEvent?.id == event.id ? OraloStyle.readingAccent.opacity(0.10) : .clear, in: .rect(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityIdentifier("review-event-\(event.id)")
                            Divider()
                        }
                    }
                    Text(record.usedVoice ? t("停顿可能是在思考，重读也可能是强调。音量与识别只提供回看线索，并非完整记录或演讲评分。", "A pause can be a moment to think; a repeat can add emphasis. Audio levels and recognition offer review cues, not a complete record or a score.") : t("本次没有可用的语音跟随记录，仅展示实际时长和手动切句。", "No voice-following events were recorded. Only elapsed active time and manual cues are shown."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(24)
        }
        .safeAreaInset(edge: .bottom) { reviewActions }
    }
    @ViewBuilder private var metrics: some View {
        metric(SessionCopy.duration(record.activeDuration), label: t("有效时长", "Active time"), id: "review-duration")
        metric(record.manualCount.formatted(), label: t("手动切句", "Manual cues"), id: "review-manual-count")
        if record.usedVoice { metric(record.holdCount.formatted(), label: t("跟随保持", "Position holds"), id: "review-hold-count") }
    }
    private func metric(_ value: String, label: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(value).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit().accessibilityIdentifier(id)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReviewPassageView: View {
    let event: RehearsalEvent
    let snapshot: RehearsalSnapshot
    let current: ScriptDocument
    var embedded = false
    let edit: (UUID?, RehearsalSnapshot) -> Void
    var checkPronunciation: ((UUID, RehearsalSnapshot, UUID) -> Void)? = nil
    var record: RehearsalRecord? = nil
    private func t(_ zh: String, _ en: String) -> String { PronunciationCopy.text(zh, en) }
    private var target: TextSpan? { snapshot.editRange(cueID: event.cueID, in: current) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(SessionCopy.duration(event.activeOffset) + " · " + SessionCopy.reason(event))
                    .font(.subheadline).foregroundStyle(OraloStyle.readingAccent).accessibilityIdentifier("review-event-reason")
                Text(t("回到这一句", "Back to this passage")).font(.largeTitle.bold())
                if target == nil {
                    Label(t("讲稿已更新，下面是排练时的原句。", "The script has changed. This is the passage you rehearsed."), systemImage: "clock.arrow.circlepath")
                        .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("review-script-changed")
                }
                ReviewContextText(document: snapshot.document, cueID: event.cueID)
                    .accessibilityIdentifier("historical-passage-text")
                Text(t("想一想、停一停也没关系。只调整你觉得需要的地方。", "A moment to think is fine. Change only what feels useful to you."))
                    .font(.footnote).foregroundStyle(.secondary)
                if let checkPronunciation, let record, record.kind == .rehearsal {
                    Button {
                        checkPronunciation(event.cueID, snapshot, record.id)
                    } label: {
                        Label(t("核对读音", "Check pronunciation"), systemImage: "character.phonetic").frame(minHeight: 44)
                    }.accessibilityIdentifier("review-check-pronunciation")
                    Text(t("对某个词不太确定？选中它，核对参考读音或添加提示。", "Unsure about a word? Select it to check a reference or add a reading hint."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                NavigationLink {
                    OriginalDraftView(snapshot: snapshot, cueID: event.cueID)
                } label: {
                    Label(t("对照初始原稿", "Compare initial draft"), systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline).frame(minHeight: 44)
                }.accessibilityIdentifier("compare-original")
            }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .center)
        }.background(OraloStyle.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                SessionPrimary(title: target == nil ? t("打开当前讲稿", "Open current script") : t("回到这句编辑", "Edit this passage"), symbol: "pencil", id: "edit-reviewed-passage") {
                    edit(target == nil ? nil : event.cueID, snapshot)
                }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity).background(OraloStyle.canvas)
            }
    }
}

/// Three passages, with exactly the saved occurrence-level readings. No editable history.
private struct ReviewContextText: UIViewRepresentable {
    let document: ScriptDocument
    let cueID: UUID
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    func makeUIView(context: Context) -> UITextView {
        let storage = NSTextStorage(), layout = PronunciationLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true; container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let view = UITextView(frame: .zero, textContainer: container)
        view.isEditable = false; view.isSelectable = false; view.isScrollEnabled = false
        view.backgroundColor = .clear; view.textContainerInset = .zero
        view.accessibilityIdentifier = "historical-passage-text"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) { configure(view, width: max(80, view.bounds.width)) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        configure(uiView, width: width)
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
    private func configure(_ view: UITextView, width: CGFloat) {
        guard let index = document.segments.firstIndex(where: { $0.id == cueID }) else { return }
        let result = NSMutableAttributedString()
        var readings: [Pronunciation] = []
        var focus = NSRange(location: 0, length: 0)
        var perCue: [UUID: [Pronunciation]] = [:]
        for (id, span) in document.segmentSpans() {
            for var reading in document.pronunciations where reading.isAnchored(in: document.text) {
                guard let anchor = reading.span, NSIntersectionRange(anchor.nsRange, span) == anchor.nsRange else { continue }
                reading.span?.location -= span.location
                perCue[id, default: []].append(reading)
            }
        }
        for i in max(0, index - 1)...min(document.segments.count - 1, index + 1) {
            if result.length > 0 { result.append(NSAttributedString(string: "\n\n")) }
            let segment = document.segments[i]
            let range = NSRange(location: result.length, length: segment.text.utf16.count)
            for var reading in perCue[segment.id] ?? [] {
                reading.span?.location += range.location; readings.append(reading)
            }
            result.append(NSAttributedString(string: segment.text))
            if i == index { focus = range }
        }
        let font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .systemFont(ofSize: 24))
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 10
        result.addAttributes([.font: font, .paragraphStyle: paragraph, .foregroundColor: UIColor.secondaryLabel], range: NSRange(location: 0, length: result.length))
        result.addAttributes([.foregroundColor: UIColor.label, .backgroundColor: UIColor(OraloStyle.readingAccent).withAlphaComponent(0.10)], range: focus)
        (view.layoutManager as? PronunciationLayoutManager)?.configure(readings, in: result, font: font, width: max(80, width))
        view.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        view.textStorage.setAttributedString(result)
        view.accessibilityValue = readings.map { "\($0.term): \($0.reading)" }.joined(separator: "; ")
    }
}

private struct OriginalDraftView: View {
    let snapshot: RehearsalSnapshot
    let cueID: UUID
    private func t(_ zh: String, _ en: String) -> String { PronunciationCopy.text(zh, en) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let text = snapshot.document.originalText {
                Label(t("最初保留的版本 · 只读", "Initially saved version · Read only"), systemImage: "doc.text")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 24)
                if snapshot.originalRange(cueID: cueID) == nil {
                    Text(t("无法确定这句在初始原稿中的位置，你可以查看全文。", "This passage cannot be located reliably in the initial draft. You can read the full text."))
                        .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 24)
                        .accessibilityIdentifier("original-unmapped")
                }
                OriginalDraftText(text: text, range: snapshot.originalRange(cueID: cueID), cueID: cueID)
            } else {
                ContentUnavailableView(t("没有保留初始原稿", "No initial draft available"), systemImage: "doc.text")
            }
        }.padding(.top, 20).frame(maxWidth: 800).frame(maxWidth: .infinity).background(OraloStyle.canvas)
            .navigationTitle(t("对照原稿", "Initial draft")).navigationBarTitleDisplayMode(.inline)
    }
}

private struct OriginalDraftText: UIViewRepresentable {
    let text: String
    let range: TextSpan?
    let cueID: UUID
    func makeUIView(context: Context) -> ManuscriptTextView {
        let view = ManuscriptTextView(); view.allowsEditing = false
        view.accessibilityIdentifier = "original-draft-text"
        return view
    }
    func updateUIView(_ view: ManuscriptTextView, context: Context) {
        view.refresh(ScriptDocument(id: cueID, text: text))
        if let range { view.focus(ScriptTextFocus(id: cueID, range: range.nsRange)) }
    }
}

struct RehearsalHistoryView: View {
    let store: RehearsalStore
    let current: ScriptDocument
    let edit: (UUID?, RehearsalSnapshot) -> Void
    var checkPronunciation: ((UUID, RehearsalSnapshot, UUID) -> Void)? = nil
    let again: () -> Void
    @State private var kind = RehearsalRecord.Kind.rehearsal
    @State private var deleting: RehearsalRecord?
    @Environment(\.dismiss) private var dismiss
    private func t(_ zh: String, _ en: String) -> String { PronunciationCopy.text(zh, en) }
    private var records: [RehearsalRecord] { store.records.filter { $0.scriptID == current.id && $0.kind == kind } }
    var body: some View {
        NavigationStack {
            List {
                Picker(t("记录类型", "Record type"), selection: $kind) {
                    Text(t("排练", "Rehearsal")).tag(RehearsalRecord.Kind.rehearsal)
                    Text(t("演讲", "Presentation")).tag(RehearsalRecord.Kind.presentation)
                }.pickerStyle(.segmented).listRowBackground(Color.clear)
                if let error = store.error { Text(error).foregroundStyle(.orange) }
                if store.recovered { Text(t("已恢复上次可读的备份，最新记录可能不完整。", "Recovered the last readable backup. Recent records may be incomplete.")).foregroundStyle(.secondary) }
                if records.isEmpty { Text(t("还没有这篇讲稿的记录。", "No records for this script yet.")).foregroundStyle(.secondary) }
                ForEach(records) { record in
                    if let snapshot = store.snapshots[record.snapshotID] {
                        NavigationLink {
                            RehearsalReviewView(record: record, snapshot: snapshot, current: current, edit: edit, checkPronunciation: checkPronunciation, again: again, done: { dismiss() })
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(record.startedAt, format: .dateTime.month().day().hour().minute()); Spacer(); Text(SessionCopy.duration(record.activeDuration)).monospacedDigit() }
                                Text(t("手动切句 \(record.manualCount) 次", "\(record.manualCount) manual cues") + (record.status == .unfinished ? t(" · 未完成", " · Unfinished") : ""))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }.accessibilityIdentifier("rehearsal-record-\(record.id)")
                            .swipeActions { Button(t("删除", "Delete"), role: .destructive) { deleting = record } }
                    }
                }
            }.scrollContentBackground(.hidden).background(OraloStyle.canvas)
                .navigationTitle(t("讲稿记录", "Script records")).navigationBarTitleDisplayMode(.large)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(t("完成", "Done")) { dismiss() }.accessibilityIdentifier("close-history") } }
                .confirmationDialog(t("删除这次记录？", "Delete this record?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    if let deleting { Button(t("删除记录", "Delete record"), role: .destructive) { Task { await store.delete(deleting); self.deleting = nil } } }
                } message: { Text(t("保留当前讲稿与读音标注。仅这次记录及不再使用的历史版本会被移除。", "Your current script and pronunciations are kept. This record and any unused historical version will be removed.")) }
        }.tint(OraloStyle.readingAccent)
    }
}
