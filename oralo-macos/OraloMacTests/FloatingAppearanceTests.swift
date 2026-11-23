import AppKit
import Testing
import OraloCore
@testable import OraloMac

@MainActor struct FloatingAppearanceTests {
    @Test func appearancePersistsAndInvalidValuesFallBack() throws {
        let name = "OraloAppearanceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = MacPreferences(defaults: defaults)
        #expect(preferences.floatingLineSpacing == 5)
        #expect(preferences.lineSpacing == 12)
        preferences.lineSpacing = 20
        preferences.theme = .dark
        preferences.libraryLayout = .list
        preferences.showWelcome = false
        preferences.fontSize = 52
        preferences.floatingFontSize = 24
        preferences.transparency = 0.6
        preferences.mirror = true
        preferences.compatibility = true
        preferences.colorPanelMode = 1
        #expect(preferences.floatingHighlight == .indigo)
        preferences.floatingLineSpacing = 17
        preferences.floatingHighlight = .custom
        preferences.floatingCustomHighlight = try #require(HighlightColor(hex: "  #d45a87  "))
        let reopened = MacPreferences(defaults: defaults)
        #expect(reopened.floatingLineSpacing == 17)
        #expect(reopened.lineSpacing == 20)
        #expect(reopened.theme == .dark)
        #expect(reopened.libraryLayout == .list)
        #expect(!reopened.showWelcome)
        #expect(reopened.fontSize == 52)
        #expect(reopened.floatingFontSize == 24)
        #expect(reopened.transparency == 0.6)
        #expect(reopened.mirror)
        #expect(reopened.compatibility)
        #expect(reopened.colorPanelMode == 1)
        #expect(reopened.floatingHighlight == .custom)
        #expect(reopened.floatingCustomHighlight.hex == "#D45A87")
        #expect(HighlightColor(hex: "#11223300") == nil)
        #expect(HighlightColor(hex: "#GGHHII") == nil)
        #expect(HighlightColor(hex: "#12") == nil)
        defaults.set(-10, forKey: "mac.floatingLineSpacing")
        defaults.set("invalid", forKey: "mac.floatingHighlight")
        defaults.set("#00000000", forKey: "mac.floatingCustomHighlight")
        let recovered = MacPreferences(defaults: defaults)
        #expect(recovered.floatingLineSpacing == 0)
        #expect(recovered.floatingHighlight == .indigo)
        #expect(recovered.floatingCustomHighlight.hex == "#5056F5")
    }
    @Test func reflowAndRecolorKeepCursorAndPronunciationAnchors() throws {
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
        let scroll = ReadingScrollView(frame: CGRect(x: 0, y: 0, width: 520, height: 170))
        let view = ReadingTextView(); scroll.documentView = view
        view.update(session: session, fontSize: 28, floating: true, dark: false)
        view.fit(viewport: scroll.contentSize)
        let original = view.string, oldHeight = view.frame.height
        let ruby = try #require(view.layoutManager as? PronunciationLayoutManager)
        let readings = ruby.readings
        #expect(readings.count == 1)
        let color = HighlightColor(rgb: 0x16794F).nsColor
        view.update(session: session, fontSize: 28, floating: true, dark: false, lineSpacing: 18, highlightColor: color)
        view.fit(viewport: scroll.contentSize)
        #expect(view.frame.height > oldHeight)
        #expect(view.string == original)
        #expect(session.currentIndex == 2)
        #expect(session.readingPosition == position)
        #expect(session.recording)
        #expect(ruby.readings == readings)
        #expect(ruby.readings.allSatisfy { $0.isAnchored(in: view.string) })
        let storage = try #require(view.textStorage)
        #expect((storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing == 18)
        let cueStart = (view.string as NSString).range(of: session.snapshot.cues[2].text).location
        #expect(storage.attribute(.foregroundColor, at: cueStart, effectiveRange: nil) as? NSColor == color)
        let nextColor = HighlightColor(rgb: 0xC03970).nsColor
        let height = view.frame.height
        view.update(session: session, fontSize: 28, floating: true, dark: false, lineSpacing: 18, highlightColor: nextColor)
        view.fit(viewport: scroll.contentSize)
        #expect(storage.attribute(.foregroundColor, at: cueStart, effectiveRange: nil) as? NSColor == nextColor)
        #expect(view.frame.height == height)
        #expect(session.readingPosition == position)
        // Normal presentation keeps its independent spacing and palette.
        view.update(session: session, fontSize: 40, floating: false, dark: false)
        view.fit(viewport: scroll.contentSize)
        #expect((storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing == 12)
        #expect(session.readingPosition == position)
    }
    @Test func tallerSettingsStayOnScreenWithoutCoveringPrompt() {
        let screen = CGRect(x: 0, y: 40, width: 1440, height: 800)
        let prompt = FloatingGeometry.nearCamera(size: FloatingGeometry.standard, visible: screen)
        let settings = FloatingGeometry.settingsFrame(beside: prompt, visible: screen)
        #expect(screen.contains(settings))
        #expect(!settings.intersects(prompt))
        let smallScreen = CGRect(x: -1200, y: 0, width: 1024, height: 540)
        let smallPrompt = FloatingGeometry.nearCamera(size: FloatingGeometry.minimum, visible: smallScreen)
        let smallSettings = FloatingGeometry.settingsFrame(beside: smallPrompt, visible: smallScreen, contentSize: CGSize(width: 340, height: 600))
        #expect(smallScreen.contains(smallSettings))
        #expect(smallSettings.height == 524)
    }
    @Test func nativePaletteColorsAreOpaqueAndCornersRespectVisibleScreen() throws {
        let color = try #require(HighlightColor(nsColor: NSColor(srgbRed: 0.8, green: 0.2, blue: 0.4, alpha: 0.2)))
        #expect(color.hex == "#CC3366")
        #expect(color.nsColor.alphaComponent == 1)
        let visible = CGRect(x: -1400, y: 42, width: 1400, height: 850)
        for corner in FloatingCorner.allCases {
            let frame = FloatingGeometry.corner(corner, size: FloatingGeometry.standard, visible: visible)
            #expect(visible.contains(frame))
            #expect(corner.isLeft ? frame.minX == visible.minX + 8 : frame.maxX == visible.maxX - 8)
            #expect(corner.isTop ? frame.maxY == visible.maxY - 8 : frame.minY == visible.minY + 8)
            #expect(frame.size == FloatingGeometry.standard)
            let settings = FloatingGeometry.settingsFrame(beside: frame, visible: visible)
            #expect(visible.contains(settings))
            #expect(!settings.intersects(frame))
        }
    }

}
