import AppKit
import SwiftUI
import OraloCore

struct ManuscriptEditor: NSViewRepresentable {
    let editor: ScriptEditorModel
    var alignment: ManuscriptAlignment = .left
    let reading: (NSRange) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let view = ManuscriptTextView()
        view.delegate = context.coordinator
        view.onReading = reading
        view.autoresizingMask = [.width]
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.editor = editor
        guard let view = scroll.documentView as? ManuscriptTextView else { return }
        view.onReading = reading
        view.refresh(editor.document, alignment: alignment.native)
        if let request = editor.reveal, context.coordinator.revealed != request.id,
           NSMaxRange(request.range) <= (view.string as NSString).length {
            context.coordinator.revealed = request.id
            Task { @MainActor [weak view] in
                await Task.yield()
                guard let view, editor.reveal?.id == request.id, !view.hasMarkedText(),
                      NSMaxRange(request.range) <= (view.string as NSString).length else { return }
                view.layoutSubtreeIfNeeded()
                view.setSelectedRange(request.range); view.scrollRangeToVisible(request.range)
                view.window?.makeFirstResponder(view)
            }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var revealed: UUID?
        var editor: ScriptEditorModel
        private var pending: (String, NSRange, String)?
        init(editor: ScriptEditorModel) { self.editor = editor }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, !view.hasMarkedText() else { return }
            let range = view.selectedRange()
            guard range != editor.selectedRange else { return }
            Task { @MainActor [weak self] in
                guard let self, view.selectedRange() == range else { return }
                self.editor.selectedRange = range
            }
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            pending = (textView.string, affectedCharRange, replacementString ?? "")
            return true
        }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, !view.hasMarkedText() else { return }
            if let (old, range, replacement) = pending, old == editor.document.text,
               let r = Range(range, in: old), old.replacingCharacters(in: r, with: replacement) == view.string {
                editor.editText(range, replacement: replacement)
            } else {
                // IME commits can span several delegate edits. Preserve unaffected anchors.
                let old = Array(editor.document.text), new = Array(view.string)
                let prefix = zip(old, new).prefix { $0 == $1 }.count
                let suffix = zip(old.dropFirst(prefix).reversed(), new.dropFirst(prefix).reversed()).prefix { $0 == $1 }.count
                let range = NSRange(location: String(old.prefix(prefix)).utf16.count,
                    length: String(old.dropFirst(prefix).dropLast(suffix)).utf16.count)
                editor.editText(range, replacement: String(new.dropFirst(prefix).dropLast(suffix)))
            }
            pending = nil
        }
    }
}

final class ManuscriptTextView: NSTextView {
    var onReading: ((NSRange) -> Void)?
    private var document: ScriptDocument?
    private var requestedAlignment: NSTextAlignment = .left
    private var renderedAlignment: NSTextAlignment?
    private var lastWidth: CGFloat = 0
    private let ruby = PronunciationLayoutManager()
    override var undoManager: UndoManager? { nil } // Document undo also restores pronunciation anchors.
    init() {
        let storage = NSTextStorage()
        storage.addLayoutManager(ruby)
        let container = NSTextContainer(containerSize: CGSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true; container.lineFragmentPadding = 0
        ruby.addTextContainer(container)
        super.init(frame: CGRect(x: 0, y: 0, width: 600, height: 500), textContainer: container)
        isRichText = false; isEditable = true; isSelectable = true; drawsBackground = false
        isVerticallyResizable = true; isHorizontallyResizable = false
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainerInset = CGSize(width: 24, height: 24)
        setAccessibilityIdentifier("script-editor")
        setAccessibilityLabel(MacCopy.text("讲稿正文", "Script text"))
        isAutomaticQuoteSubstitutionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    func refresh(_ next: ScriptDocument, alignment: NSTextAlignment? = nil, force: Bool = false) {
        if let alignment { requestedAlignment = alignment }
        let changed = document?.text != next.text || document?.pronunciations != next.pronunciations
        document = next
        guard !hasMarkedText(), force || changed || bounds.width != lastWidth || renderedAlignment != requestedAlignment else { return }
        lastWidth = bounds.width
        renderedAlignment = requestedAlignment
        let selection = selectedRange()
        let font = NSFont.systemFont(ofSize: 24)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 10; paragraph.paragraphSpacing = 16; paragraph.alignment = requestedAlignment
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        let string = NSMutableAttributedString(string: next.text, attributes: attrs)
        ruby.configure(next.pronunciations, in: string, font: font, width: max(80, bounds.width - 48))
        textStorage?.setAttributedString(string)
        typingAttributes = attrs
        let start = min(selection.location, string.length)
        setSelectedRange(NSRange(location: start, length: min(selection.length, string.length - start)))
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let document, newSize.width != lastWidth { refresh(document) }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let document { refresh(document, force: true) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if let document, (try? document.pronunciationSelection(selectedRange())) != nil {
            let action = NSMenuItem(title: MacCopy.text("添加 / 编辑读音", "Add / edit pronunciation"), action: #selector(openReading), keyEquivalent: "")
            action.target = self
            menu.insertItem(.separator(), at: 0); menu.insertItem(action, at: 0)
        }
        return menu
    }
    @objc func openReading() { onReading?(selectedRange()) }
}
