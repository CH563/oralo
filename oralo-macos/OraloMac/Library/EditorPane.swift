import SwiftUI
import OraloCore

struct EditorPane: View {
    @Bindable var editor: ScriptEditorModel
    let model: MacAppModel
    @Binding var selection: ReadingSelection?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(MacCopy.text("讲稿标题", "Script title"), text: Binding(get: { editor.document.title }, set: { value in editor.change { $0.title = value } }))
                        .font(.system(size: 28, weight: .bold)).textFieldStyle(.plain).accessibilityIdentifier("script-title")
                    Label(editor.saving ? MacCopy.text("正在保存…", "Saving…") : editor.dirty ? MacCopy.text("等待保存", "Unsaved changes") : MacCopy.text("已保存在本机", "Saved on this Mac"),
                          systemImage: editor.dirty ? "circle.dotted" : "checkmark.circle")
                        .font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("save-status")
                    Text(MacCopy.metrics(editor.document.text, preferences: model.preferences)).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()

            }.padding(.horizontal, 28).padding(.top, 24)
            ViewThatFits(in: .horizontal) {
                editorControls(compact: false)
                editorControls(compact: true)
            }.padding(.horizontal, 28)
            EditorReviewBanner(model: model, editor: editor).padding(.horizontal, 28)
            Divider().padding(.horizontal, 28)
            ManuscriptEditor(editor: editor, alignment: model.preferences.textAlignment) { selection = ReadingSelection(range: $0, replacing: editor.reattachingReading) }.padding(.horizontal, 4)
            if let error = editor.error ?? editor.actionError {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, 28)
            }
            HStack {
                Text(MacCopy.text("选中词语，右键添加拼音或音标。", "Select a word, then right-click to add pinyin or IPA.")).font(.caption).foregroundStyle(.secondary)
                Spacer()

            }.padding(.horizontal, 28).padding(.bottom, 18)
        }.oraloActionStyle()
    }
    private func editorControls(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Picker(MacCopy.text("演讲语言", "Speech language"), selection: Binding(get: { editor.document.localeID }, set: { value in
                editor.change { $0.localeID = value }
            })) {
                Text("普通话").tag("zh-CN")
                Text("English (US)").tag("en-US")
            }.labelsHidden().frame(width: 132, alignment: .leading)
                .accessibilityIdentifier("speech-language")
                .help(MacCopy.text("演讲语言", "Speech language"))
            Spacer(minLength: 12)
            ManuscriptAlignmentPicker(preferences: model.preferences)
            Button {
                let range = editor.selectedRange
                if (try? editor.document.pronunciationSelection(range)) != nil { selection = ReadingSelection(range: range, replacing: editor.reattachingReading) }
            } label: {
                if compact { Image(systemName: "character.phonetic") }
                else { Label(MacCopy.text("读音", "Pronunciation"), systemImage: "character.phonetic") }
            }.fixedSize()
                .accessibilityLabel(MacCopy.text("读音", "Pronunciation"))
                .help(MacCopy.text("先选中正文中的词语，也可右键添加读音。", "Select a word in the script, or right-click to add its reading."))
                .disabled((try? editor.document.pronunciationSelection(editor.selectedRange)) == nil)
                .accessibilityIdentifier("open-pronunciation")
            Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(editor.history.isEmpty)
                .help(MacCopy.text("撤销", "Undo")).accessibilityLabel(MacCopy.text("撤销", "Undo"))
            Button(MacCopy.text("保存", "Save")) { Task { _ = await editor.flush() } }
                .fixedSize().accessibilityIdentifier("save-script")
        }
    }

}
