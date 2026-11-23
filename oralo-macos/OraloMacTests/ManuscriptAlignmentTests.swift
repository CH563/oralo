import AppKit
import Testing
import OraloCore
@testable import OraloMac

@MainActor struct ManuscriptAlignmentTests {
    @Test func alignmentRestoresAndUnknownValuesDefaultLeft() throws {
        let name = "OraloAlignmentTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = MacPreferences(defaults: defaults)
        #expect(preferences.textAlignment == .left)
        for alignment in ManuscriptAlignment.allCases {
            preferences.textAlignment = alignment
            #expect(MacPreferences(defaults: defaults).textAlignment == alignment)
        }
        defaults.set("unsupported", forKey: "mac.textAlignment")
        #expect(MacPreferences(defaults: defaults).textAlignment == .left)
    }

    @Test func editorAlignmentMovesGlyphsWithoutChangingTextSelectionOrReadings() throws {
        var document = ScriptDocument(text: "完善 roadmap。\n继续夯实基础。")
        try document.setPronunciation(Pronunciation(span: TextSpan((document.text as NSString).range(of: "roadmap")),
            term: "roadmap", reading: "/ˈroʊdˌmæp/", kind: .ipa))
        let view = ManuscriptTextView()
        view.refresh(document)
        let selection = (document.text as NSString).range(of: "roadmap")
        view.setSelectedRange(selection)
        let ruby = try #require(view.layoutManager as? PronunciationLayoutManager)
        let container = try #require(view.textContainer)
        let range = NSRange(location: 0, length: 1)
        var positions: [CGFloat] = []
        for alignment in ManuscriptAlignment.allCases {
            view.refresh(document, alignment: alignment.native)
            ruby.ensureLayout(for: container)
            positions.append(ruby.boundingRect(forGlyphRange: range, in: container).minX)
            #expect(view.string == document.text)
            #expect(view.selectedRange() == selection)
            #expect(ruby.readings == document.pronunciations)
            #expect((view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment == alignment.native)
        }
        #expect(positions[0] < positions[1] && positions[1] < positions[2])
        view.setFrameSize(CGSize(width: 480, height: 500))
        view.viewDidChangeEffectiveAppearance()
        #expect((view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .right)
        #expect(view.string == document.text)
        // A pending presentation change must leave a Chinese composition untouched.
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        view.setMarkedText("pin", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let composing = view.string
        view.refresh(document, alignment: .center)
        #expect(view.hasMarkedText())
        #expect(view.string == composing)
        view.insertText("拼音", replacementRange: view.markedRange())
        try document.applyTextEdit(NSRange(location: document.text.utf16.count, length: 0), replacement: "拼音")
        view.refresh(document)
        #expect(view.string == document.text)
        #expect((view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment == .center)
        #expect(ruby.readings.allSatisfy { $0.isAnchored(in: view.string) })
    }

    @Test func bothReadersKeepProgressHighlightAndRubyWhenAligned() throws {
        let sample = QuickScript.sample(localization: "zh-Hans")
        var document = ScriptDocument(text: sample.text)
        try document.setPronunciation(Pronunciation(span: TextSpan((sample.text as NSString).range(of: "roadmap")),
            term: "roadmap", reading: "/ˈroʊdˌmæp/", kind: .ipa))
        let session = try MacSpeechSession(snapshot: document.snapshot())
        defer { session.pause() }
        session.select(index: 2)
        let request = UUID()
        session.receive(.started(id: request, engine: "test"))
        session.receive(.transcript(id: request, text: session.snapshot.cues[2].text, isFinal: true, deliveryDelay: 0.2))
        let position = session.readingPosition
        #expect(session.follower.reading.confirmedCharacterCount > 1)
        for floating in [false, true] {
            let scroll = ReadingScrollView(frame: CGRect(x: 0, y: 0, width: 760, height: 400))
            let view = ReadingTextView(); scroll.documentView = view
            let color = HighlightColor(rgb: 0x16794F).nsColor
            var positions: [CGFloat] = [], focusOffsets: [CGFloat] = []
            for alignment in ManuscriptAlignment.allCases {
                view.update(session: session, fontSize: 28, floating: floating, dark: false, highlightColor: color, alignment: alignment.native)
                view.fit(viewport: scroll.contentSize)
                let ruby = try #require(view.layoutManager as? PronunciationLayoutManager)
                let container = try #require(view.textContainer)
                let cueRange = (view.string as NSString).range(of: session.snapshot.cues[2].text)
                let glyph = ruby.glyphIndexForCharacter(at: cueRange.location)
                positions.append(ruby.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).minX)
                focusOffsets.append(scroll.contentView.bounds.minY)
                #expect(session.readingPosition == position)
                #expect(session.recording)
                #expect(ruby.readings.count == 1)
                #expect(ruby.readings.allSatisfy { $0.isAnchored(in: view.string) })
                #expect(!view.string.contains("/ˈroʊdˌmæp/"))
                #expect(view.textStorage?.attribute(.foregroundColor, at: cueRange.location, effectiveRange: nil) as? NSColor == color)
            }
            #expect(positions[0] < positions[1] && positions[1] < positions[2])
            #expect(focusOffsets.max()! - focusOffsets.min()! < 1)
        }
    }
}
