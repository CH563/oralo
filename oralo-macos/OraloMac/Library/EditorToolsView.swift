import AppKit
import SwiftUI
import OraloCore

enum EditorTool: String, CaseIterable, Identifiable {
    case readings, layout, original
    var id: Self { self }
    var title: String { switch self {
    case .readings: MacCopy.text("全部注音", "All readings")
    case .layout: MacCopy.text("分句排版", "Sentence layout")
    case .original: MacCopy.text("查看初稿", "Initial draft")
    } }
}

struct EditorToolsView: View {
    let tool: EditorTool
    @Bindable var editor: ScriptEditorModel
    let model: MacAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var splitting: ScriptSegment?
    @State private var reading: ReadingSelection?
    @State private var rebuilding = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(tool.title).font(.title2.bold())
                Spacer()
                if tool == .layout {
                    Button(MacCopy.text("重新分句", "Rebuild sentences")) { rebuilding = true }
                }
                Button(MacCopy.text("完成", "Done")) { Task { if await editor.flush() { dismiss() } } }.keyboardShortcut(.cancelAction)
            }
            switch tool {
            case .original:
                Text(MacCopy.text("首次开讲前保存的初稿，仅供查看。导出使用当前讲稿正文。", "Read-only draft captured before the first session. Export uses your current script."))
                    .font(.callout).foregroundStyle(.secondary)
                ScrollView { Text(editor.document.originalText ?? MacCopy.text("首次开讲时会保留初稿。", "Your initial draft is kept when you first start a session.")).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(16) }
            case .readings: readings
            case .layout: layout
            }
            if let error = editor.actionError ?? editor.error { Text(error).foregroundStyle(.red).font(.callout) }
        }.padding(24).frame(width: 670, height: 610).oraloActionStyle()
            .preferredColorScheme(model.preferences.colorScheme)
            .sheet(item: $splitting) { segment in SplitSentenceView(segment: segment, editor: editor) }
            .sheet(item: $reading) { selection in
                ReadingSheet(editor: editor, selection: selection, willPlay: { model.windows.session?.pause() }, didSave: { value in
                    Task { await model.completeReadingReview(.added, reading: value) }
                })
            }
            .alert(MacCopy.text("重新生成分句？", "Rebuild sentence layout?"), isPresented: $rebuilding) {
                Button(MacCopy.text("重新分句", "Rebuild")) { editor.change { $0.rebuildSentences() } }
                Button(MacCopy.text("取消", "Cancel"), role: .cancel) {}
            } message: { Text(MacCopy.text("保留正文和注音，替换手动拆分、合并与暂停点。可以在备稿中撤销。", "Keeps text and readings, and replaces manual splits, merges and pause points. Undo is available in Prepare.")) }
    }
    private var readings: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if editor.document.pronunciations.isEmpty {
                    ContentUnavailableView(MacCopy.text("先选一个词", "Choose a word first"), systemImage: "character.phonetic", description: Text(MacCopy.text("在备稿正文选中词语，右键添加拼音或音标。", "Select a word in Prepare and right-click to add pinyin or IPA.")))
                }
                ForEach(editor.document.pronunciations) { value in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(value.term).font(.headline)
                                Text(value.reading).foregroundStyle(MacStyle.accent).textSelection(.enabled)
                            }
                            Spacer()
                            if value.needsReview {
                                Label(MacCopy.text("待重新关联", "Needs relinking"), systemImage: "exclamationmark.circle").font(.caption)
                            }
                        }
                        if value.needsReview, !value.context.isEmpty { Text(value.context).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                        HStack {
                            if let span = value.span, value.isAnchored(in: editor.document.text) {
                                Button(MacCopy.text("编辑 / 试听", "Edit / Listen")) { reading = ReadingSelection(range: span.nsRange) }
                                Toggle(MacCopy.text("演讲时显示", "Show when speaking"), isOn: Binding(get: { value.showInPresentation }, set: { enabled in
                                    var changed = value; changed.showInPresentation = enabled
                                    Task { _ = await editor.savePronunciation(changed) }
                                })).toggleStyle(.checkbox)
                            } else {
                                Button(MacCopy.text("在正文重新关联", "Relink in script")) {
                                    editor.reattachingReading = value; model.tool = nil
                                }
                            }
                            Spacer()
                            Button(role: .destructive) { editor.change { $0.removePronunciation(value.id) } } label: { Image(systemName: "trash") }
                                .help(MacCopy.text("移除注音", "Remove reading")).accessibilityLabel(MacCopy.text("移除注音", "Remove reading"))
                        }
                    }.padding(16).background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 14))
                }
            }
        }
    }
    private var layout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(MacCopy.text("拆分或合并只调整演讲时的分句，注音仍跟随原词。暂停点会在读完该句后停下。", "Split or merge the speaking layout while keeping readings attached to their words. Pause points stop after that sentence."))
                .font(.callout).foregroundStyle(.secondary)
            if editor.document.layoutNeedsReview {
                HStack {
                    Label(MacCopy.text("正文有改动，请检查分句。", "Text changed. Review the sentence layout."), systemImage: "exclamationmark.circle")
                    Spacer()
                    Button(MacCopy.text("确认排版", "Confirm layout")) { editor.change { $0.confirmLayout() } }
                }.font(.callout)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(editor.document.segments.enumerated()), id: \.element.id) { index, segment in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
                            Text(segment.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 12) {
                                Button(MacCopy.text("拆分", "Split"), systemImage: "scissors") { splitting = segment }.fixedSize().disabled(segment.text.count < 2)
                                Button(MacCopy.text("合并下一句", "Merge next")) { editor.change { $0.mergeWithNext(segment.id) } }.fixedSize()
                                    .disabled(index + 1 == editor.document.segments.count)
                                Spacer()
                                Toggle(MacCopy.text("读后暂停", "Pause after"), isOn: Binding(get: { segment.pauseAfter }, set: { _ in editor.change { $0.togglePause(segment.id) } }))
                                    .toggleStyle(.checkbox).fixedSize()
                            }.controlSize(.small)
                        }.padding(16).background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 14))
                    }
                }
            }
        }
    }
}

private struct SplitSentenceView: View {
    let segment: ScriptSegment
    let editor: ScriptEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection = NSRange(location: 0, length: 0)
    private var offset: Int? {
        guard selection.location > 0, selection.location < segment.text.utf16.count,
              let range = Range(NSRange(location: 0, length: selection.location), in: segment.text) else { return nil }
        return segment.text[range].count
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(MacCopy.text("选择拆分位置", "Choose a split point")).font(.title2.bold())
            Text(MacCopy.text("点击或选中第二句的开头，在所选位置之前拆分。", "Click or select the start of the second sentence. The split happens before your selection.")).foregroundStyle(.secondary)
            PassageSelectionView(text: segment.text, selection: $selection).frame(height: 180)
            HStack {
                Spacer()
                Button(MacCopy.text("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(MacCopy.text("拆分", "Split")) {
                    if let offset { editor.split(segment.id, at: offset); if editor.actionError == nil { dismiss() } }
                }.disabled(offset == nil).keyboardShortcut(.defaultAction)
            }
            if let error = editor.actionError { Text(error).foregroundStyle(.red) }
        }.padding(24).frame(width: 560).oraloActionStyle()
    }
}

private struct PassageSelectionView: NSViewRepresentable {
    let text: String
    @Binding var selection: NSRange
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = false; view.isSelectable = true; view.isRichText = false
            view.string = text; view.font = .systemFont(ofSize: 22); view.delegate = context.coordinator
            view.textContainerInset = NSSize(width: 12, height: 12)
            view.setAccessibilityLabel(MacCopy.text("选取拆分位置", "Select split point"))
        }
        return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) { context.coordinator.parent = self }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PassageSelectionView
        init(_ parent: PassageSelectionView) { self.parent = parent }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.selection = view.selectedRange()
        }
    }
}

struct OriginalDraftView: View {
    let document: ScriptDocument
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(MacCopy.text("初稿 · 只读", "Initial draft · Read only")).font(.title2.bold())
                Spacer()
                Button(MacCopy.text("完成", "Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView { Text(document.originalText ?? document.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
        }.padding(24).frame(width: 600, height: 540).oraloActionStyle()
    }
}
