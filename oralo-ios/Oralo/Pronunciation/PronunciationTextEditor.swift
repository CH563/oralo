import OraloCore
import SwiftUI
import UIKit

struct ScriptTextFocus {
    var id = UUID()
    let range: NSRange
    var beginEditing = false
}

struct PronunciationTextEditor: UIViewRepresentable {
    let document: ScriptDocument
    @Binding var editing: Bool
    let change: (String) -> Void
    let edit: (NSRange, String) -> Void
    let selectReading: (NSRange) -> Void
    var focus: ScriptTextFocus? = nil
    var allowsEditing = true

    func makeUIView(context: Context) -> ManuscriptTextView {
        let view = ManuscriptTextView()
        view.allowsEditing = allowsEditing
        view.delegate = context.coordinator
        view.onReading = { context.coordinator.open($0, in: view) }
        return view
    }
    func updateUIView(_ view: ManuscriptTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronizeText(document.text)
        view.allowsEditing = allowsEditing
        view.refresh(document)
        if let focus { view.focus(focus) }
        context.coordinator.resignIfNeeded(view)
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PronunciationTextEditor
        private var pending: (old: String, range: NSRange, replacement: String)?
        private var resignationQueued = false
        private var submittedText: String
        func synchronizeText(_ text: String) { submittedText = text }

        // UIKit asks SwiftUI for its next responder. Resigning during updateUIView
        // recursively updates that same graph on iOS 27; leave this transaction first.
        func resignIfNeeded(_ view: UITextView) {
            guard !parent.editing, view.isFirstResponder, !resignationQueued else { return }
            resignationQueued = true
            Task { @MainActor [weak self, weak view] in
                guard let self else { return }
                defer { self.resignationQueued = false }
                if !self.parent.editing, let view, view.isFirstResponder { view.resignFirstResponder() }
            }
        }
        init(_ parent: PronunciationTextEditor) { self.parent = parent; submittedText = parent.document.text }

        // A real text-selection gesture must mark editing immediately; otherwise a
        // keyboard layout update can resign the responder before the second tap.
        // Programmatic review focus already runs outside updateUIView/layoutSubviews.
        func textViewDidBeginEditing(_ textView: UITextView) { parent.editing = true }
        func textViewDidEndEditing(_ textView: UITextView) { syncEditing(textView) }
        private func syncEditing(_ textView: UITextView) {
            Task { @MainActor [weak self, weak textView] in
                guard let self, let textView else { return }
                if self.parent.editing != textView.isFirstResponder { self.parent.editing = textView.isFirstResponder }
            }
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.markedTextRange == nil, let view = textView as? ManuscriptTextView {
                view.finishComposition()
            }
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            pending = (textView.text, range, text)
            return true
        }
        func textViewDidChange(_ textView: UITextView) {
            if let pending, pending.old == submittedText,
               let range = Range(pending.range, in: pending.old),
               pending.old.replacingCharacters(in: range, with: pending.replacement) == textView.text {
                parent.edit(pending.range, pending.replacement)
            } else { parent.change(textView.text) }
            submittedText = textView.text
            pending = nil
        }

        func open(_ range: NSRange, in view: UITextView) {
            view.resignFirstResponder(); parent.editing = false
            parent.selectReading(range)
        }

        private func menu(_ textView: UITextView, range: NSRange, actions: [UIMenuElement]) -> UIMenu? {
            guard (try? parent.document.pronunciationSelection(range)) != nil else { return nil }
            let action = UIAction(title: PronunciationCopy.text("读音", "Pronunciation"), image: UIImage(systemName: "character.phonetic")) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.open(range, in: textView)
            }
            return UIMenu(children: [action] + actions)
        }
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            menu(textView, range: range, actions: suggestedActions)
        }
        @available(iOS 26, *)
        func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard ranges.count == 1, let range = ranges.first?.rangeValue else { return nil }
            return menu(textView, range: range, actions: suggestedActions)
        }
    }
}

final class ManuscriptTextView: UITextView, UIGestureRecognizerDelegate {
    var onReading: ((NSRange) -> Void)?
    var allowsEditing = true {
        didSet { if oldValue != allowsEditing { isEditable = allowsEditing } }
    }
    private var document: ScriptDocument?
    private var lastWidth: CGFloat = 0
    private var lastCategory: UIContentSizeCategory?
    private var deferredRefresh = false
    private var updating = false
    private var tappedSpan: NSRange?
    private var pendingFocus: ScriptTextFocus?
    private var lastFocusID: UUID?
    private let rubyLayout: PronunciationLayoutManager
    // Document undo (including annotations) is exposed by the editor, not a separate
    // text-only stack that could restore the words without their occurrence anchors.
    override var undoManager: UndoManager? { nil }

    init() {
        let storage = NSTextStorage(), layout = PronunciationLayoutManager()
        rubyLayout = layout
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true; container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        backgroundColor = .clear
        textContainerInset = UIEdgeInsets(top: 12, left: 24, bottom: 28, right: 24)
        adjustsFontForContentSizeCategory = true
        keyboardDismissMode = .interactive
        let toolbar = UIToolbar()
        toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace),
                         UIBarButtonItem(title: PronunciationCopy.text("完成", "Done"), style: .done, target: self, action: #selector(endTyping))]
        toolbar.sizeToFit()
        inputAccessoryView = toolbar
        accessibilityLabel = PronunciationCopy.text("讲稿正文", "Script text")
        accessibilityIdentifier = "saved-script-editor"
        let tap = UITapGestureRecognizer(target: self, action: #selector(tappedReading(_:)))
        tap.delegate = self; tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    @objc private func endTyping() { resignFirstResponder() }

    func refresh(_ document: ScriptDocument) {
        let changed = self.document?.text != document.text || self.document?.pronunciations != document.pronunciations
        self.document = document
        if isEditable != allowsEditing { isEditable = allowsEditing }
        guard !updating else { return }
        guard markedTextRange == nil else { deferredRefresh = true; return }
        let width = bounds.width
        guard changed || deferredRefresh || width != lastWidth || lastCategory != traitCollection.preferredContentSizeCategory else { return }
        updating = true; deferredRefresh = false
        defer { updating = false }
        lastWidth = width; lastCategory = traitCollection.preferredContentSizeCategory
        let selection = selectedRange, offset = contentOffset
        let font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .systemFont(ofSize: 24))
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 10; paragraph.paragraphSpacing = 18
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
        let string = NSMutableAttributedString(string: document.text, attributes: attributes)
        rubyLayout.configure(document.pronunciations, in: string, font: font, width: max(80, width - 48))
        textStorage.setAttributedString(string)
        typingAttributes = attributes
        selectedRange = NSRange(location: min(selection.location, string.length), length: min(selection.length, max(0, string.length - selection.location)))
        setContentOffset(offset, animated: false)
    }

    func focus(_ request: ScriptTextFocus) {
        guard lastFocusID != request.id else { return }
        pendingFocus = request; setNeedsLayout()
    }

    override func layoutSubviews() {
        if let document, bounds.width != lastWidth { refresh(document) }
        super.layoutSubviews()
        if let request = pendingFocus, bounds.height > 0, bounds.width > 0,
           request.range.location >= 0, NSMaxRange(request.range) <= textStorage.length {
            pendingFocus = nil; lastFocusID = request.id
            layoutManager.ensureLayout(for: textContainer)
            selectedRange = request.range
            scrollRangeToVisible(request.range)
            if request.beginEditing && isEditable {
                let expectedText = document?.text
                Task { @MainActor [weak self] in
                    guard let self, self.lastFocusID == request.id, self.document?.text == expectedText else { return }
                    self.becomeFirstResponder()
                    self.selectedRange = request.range
                    self.scrollRangeToVisible(request.range)
                }
            }
        }
    }

    func finishComposition() {
        guard deferredRefresh, !updating, let document else { return }
        refresh(document)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        tappedSpan = nil
        guard !isFirstResponder, let document, textStorage.length > 0 else { return true }
        let point = touch.location(in: self)
        let local = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer)
        if glyph < layoutManager.numberOfGlyphs,
           layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).contains(local) {
            let index = layoutManager.characterIndexForGlyph(at: glyph)
            tappedSpan = document.pronunciation(at: NSRange(location: index, length: 1))?.span?.nsRange
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    @objc private func tappedReading(_ gesture: UITapGestureRecognizer) {
        if let tappedSpan { onReading?(tappedSpan) }
    }
}
