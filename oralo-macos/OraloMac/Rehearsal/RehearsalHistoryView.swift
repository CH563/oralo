import SwiftUI
import OraloCore

struct RehearsalHistoryView: View {
    let model: MacAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var filter = 0
    @State private var deleting: RehearsalRecord?
    private var records: [RehearsalRecord] {
        model.rehearsals.records.filter {
            (model.historyScriptID == nil || $0.scriptID == model.historyScriptID) &&
            (filter == 0 || (filter == 1 ? $0.kind == .rehearsal : $0.kind == .presentation))
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(MacCopy.text("排练与演讲记录", "Session history")).font(.title2.bold())
                Spacer()
                Button(MacCopy.text("完成", "Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            HSplitView {
                VStack(spacing: 12) {
                    Picker(MacCopy.text("记录类型", "Session type"), selection: $filter) {
                        Text(MacCopy.text("全部", "All")).tag(0)
                        Text(MacCopy.text("排练", "Rehearsal")).tag(1)
                        Text(MacCopy.text("演讲", "Talks")).tag(2)
                    }.pickerStyle(.segmented).padding([.top, .horizontal], 12)
                    List(selection: $selected) {
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(model.rehearsals.snapshots[record.snapshotID]?.document.displayTitle ?? MacCopy.text("讲稿", "Script")).font(.headline).lineLimit(2)
                                Text(record.startedAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                Text("\(record.kind == .rehearsal ? MacCopy.text("排练", "Rehearsal") : MacCopy.text("演讲", "Presentation")) · \(MacCopy.duration(record.activeDuration))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5).tag(record.id)
                        }
                    }.listStyle(.sidebar)
                }.frame(minWidth: 210, idealWidth: 250, maxWidth: 300)
                Group {
                    if let record = records.first(where: { $0.id == selected }), let snapshot = model.rehearsals.snapshots[record.snapshotID] {
                        RehearsalDetailView(model: model, record: record, snapshot: snapshot, delete: { deleting = record })
                    } else {
                        ContentUnavailableView(MacCopy.text("从一次排练开始", "Start with a rehearsal"), systemImage: "waveform.path", description: Text(MacCopy.text("这里保留本机的演讲时间与复盘线索。", "Your local session timing and review notes appear here.")))
                    }
                }.frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            }
            if let message = model.rehearsals.error {
                HStack {
                    Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    if let recorder = model.windows.lastRecorder, recorder.saveError != nil {
                        Button(MacCopy.text("重试保存", "Retry save")) { Task { await recorder.flush(); if recorder.saveError == nil { model.error = nil } } }
                    }
                }.padding(12)
            }
        }.frame(width: 860, height: 650).oraloActionStyle()
            .preferredColorScheme(model.preferences.colorScheme)
            .onAppear { selected = model.reviewID ?? records.first?.id }
            .onChange(of: filter) { selected = records.first?.id }
            .alert(MacCopy.text("删除这条记录？", "Delete this session?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button(MacCopy.text("删除", "Delete"), role: .destructive) {
                    guard let record = deleting else { return }
                    Task { model.windows.discardFinishedRecorder(); await model.rehearsals.delete(record); selected = records.first?.id; deleting = nil }
                }
                Button(MacCopy.text("取消", "Cancel"), role: .cancel) { deleting = nil }
            } message: { Text(MacCopy.text("删除记录及不再被引用的历史快照，保留当前讲稿。", "Removes the session and unreferenced snapshots. The current script stays.")) }
    }
}

private struct RehearsalDetailView: View {
    let model: MacAppModel
    let record: RehearsalRecord
    let snapshot: RehearsalSnapshot
    let delete: () -> Void
    @State private var allPassages = false
    @State private var showOriginal = false
    private var reviewable: [RehearsalEvent] { record.events.filter(\.isReviewable) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(snapshot.document.displayTitle).font(.title.bold()).textSelection(.enabled)
                    Text(record.startedAt, format: .dateTime.year().month().day().hour().minute()).foregroundStyle(.secondary)
                    if record.status == .unfinished {
                        Label(MacCopy.text("未完成 · 保留了最后一次记录", "Unfinished · last checkpoint saved"), systemImage: "pause.circle").font(.callout)
                    }
                }
                HStack(spacing: 22) {
                    metric(MacCopy.text("开讲用时", "Speaking"), value: MacCopy.duration(record.activeDuration))
                    metric(MacCopy.text("暂停", "Paused"), value: MacCopy.duration(record.pausedDuration))
                    metric(MacCopy.text("手动选句", "Manual cues"), value: "\(record.manualCount)")
                    metric(MacCopy.text("自由发挥", "Off script"), value: "\(record.holdCount)")
                }
                HStack {
                    Button(MacCopy.text("再次排练", "Rehearse again"), systemImage: "arrow.clockwise") {
                        guard let document = model.library.documents.first(where: { $0.id == record.scriptID }) else { return }
                        model.showingHistory = false
                        Task {
                            await model.open(document)
                            try? await Task.sleep(for: .milliseconds(250))
                            await model.start(rehearsal: true)
                        }
                    }.disabled(!model.canManageData)
                    Button(MacCopy.text("查看初稿", "Initial draft")) { showOriginal = true }
                        .disabled(snapshot.document.originalText == nil)
                    Spacer()
                    Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                        .accessibilityLabel(MacCopy.text("删除记录", "Delete session")).help(MacCopy.text("删除记录", "Delete session"))
                        .disabled(!model.canManageData)
                }
                Divider()
                Text(MacCopy.text("值得回看的地方", "Places to revisit")).font(.title3.bold())
                Text(MacCopy.text("停顿和重读只是复盘线索，不代表读错。不会保存录音或完整转写。", "Pauses and rereads are review cues, not pronunciation judgments. Audio and full transcripts are never saved."))
                    .font(.callout).foregroundStyle(.secondary)
                if !record.usedVoice {
                    Text(MacCopy.text("本次没有语音证据，仅展示时间和手动操作。", "No voice evidence was captured. This session shows timing and manual actions only."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if reviewable.isEmpty {
                    Label(MacCopy.text("没有记录到需要回看的片段。", "No review cues were recorded."), systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(reviewable) { event in
                        if let cue = snapshot.document.segments.first(where: { $0.id == event.cueID }) {
                            ReviewPassageCard(model: model, record: record, cue: cue,
                                heading: "\(MacCopy.event(event.kind)) · \(MacCopy.duration(event.activeOffset))" + (event.duration > 0 ? " · \(MacCopy.duration(event.duration))" : ""))
                        }
                    }
                }
                if record.kind == .rehearsal {
                    DisclosureGroup(MacCopy.text("逐句检查读音", "Review pronunciation sentence by sentence"), isExpanded: $allPassages) {
                        LazyVStack(spacing: 12) {
                            ForEach(snapshot.document.segments) { cue in
                                ReviewPassageCard(model: model, record: record, cue: cue, heading: MacCopy.text("人工读音检查", "Pronunciation check"))
                            }
                        }.padding(.top, 12)
                    }
                }
            }.padding(24)
        }.sheet(isPresented: $showOriginal) {
            OriginalDraftView(document: snapshot.document)
        }
    }
    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReviewPassageCard: View {
    let model: MacAppModel
    let record: RehearsalRecord
    let cue: ScriptSegment
    let heading: String
    private var decision: PronunciationReview? { record.pronunciationReviews?.first { $0.cueID == cue.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading).font(.caption).foregroundStyle(.secondary)
            Text(cue.text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            ViewThatFits {
                HStack { actions }
                VStack(alignment: .leading) { actions }
            }
            if let decision {
                HStack {
                    Label(MacCopy.reviewStatus(decision.status), systemImage: "checkmark.circle").font(.caption)
                    Spacer()
                    Button(MacCopy.text("撤销标记", "Undo mark")) {
                        Task { _ = await model.rehearsals.setPronunciationReview(nil, cueID: cue.id, recordID: record.id) }
                    }.controlSize(.small).disabled(!model.canManageData)
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 14))
    }
    @ViewBuilder private var actions: some View {
        Button(MacCopy.text("编辑原句", "Edit passage")) {
            Task { await model.editReviewedPassage(record: record, cueID: cue.id) }
        }.disabled(!model.canManageData)
        if record.kind == .rehearsal {
            Button(MacCopy.text("检查是否需要注音", "Check pronunciation")) {
                Task { await model.editReviewedPassage(record: record, cueID: cue.id, pronunciation: true) }
            }.disabled(!model.canManageData)
            Menu {
                Button(MacCopy.text("已检查，不需添加", "Checked, no reading needed")) { mark(.kept) }
                Button(MacCopy.text("暂时忽略", "Skip for now")) { mark(.ignored) }
            } label: { Image(systemName: "ellipsis") }.help(MacCopy.text("标记检查结果", "Mark review result"))
                .accessibilityLabel(MacCopy.text("标记检查结果", "Mark review result")).disabled(!model.canManageData)
        }
    }
    private func mark(_ status: PronunciationReview.Status) {
        Task { _ = await model.rehearsals.setPronunciationReview(PronunciationReview(cueID: cue.id, status: status), cueID: cue.id, recordID: record.id) }
    }
}

struct EditorReviewBanner: View {
    let model: MacAppModel
    let editor: ScriptEditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = model.passageNotice {
                HStack { Text(notice).font(.callout); Spacer(); Button(MacCopy.text("知道了", "Dismiss")) { model.passageNotice = nil } }
            }
            if let reading = editor.reattachingReading {
                HStack {
                    Text(MacCopy.text("重新关联「\(reading.term)」：请在正文选中对应词语，再点读音。", "Relink “\(reading.term)”: select its word in the script, then choose Pronunciation.")).font(.callout)
                    Spacer()
                    Button(MacCopy.text("取消", "Cancel")) { editor.reattachingReading = nil }
                }
            }
            if let context = model.reviewContext {
                Text(MacCopy.text("读音由你确认：选中词语添加拼音或音标，也可标记无需添加。", "You decide: select a word to add pinyin or IPA, or mark it as checked."))
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(MacCopy.text("不需添加", "No reading needed")) { Task { await model.completeReadingReview(.kept) } }
                    Button(MacCopy.text("暂时忽略", "Skip for now")) { Task { await model.completeReadingReview(.ignored) } }
                    Button(MacCopy.text("返回复盘", "Back to review")) {
                        model.reviewID = context.recordID; model.showingHistory = true; model.reviewContext = nil
                    }
                }.controlSize(.small)
            }
        }
    }
}
