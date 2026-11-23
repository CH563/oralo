import XCTest
import AppKit
import Carbon

nonisolated final class MacUITests: XCTestCase {
    @MainActor func testAlignmentAtNarrowWidthsAndAfterRelaunch() throws {
        let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let sources = TISCreateInputSourceList([kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary, false).takeRetainedValue() as! [TISInputSource]
        XCTAssertEqual(TISSelectInputSource(try XCTUnwrap(sources.first)), noErr)
        defer { TISSelectInputSource(original) }
        for language in ["zh-Hans", "en"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-library=\(UUID())", "--ui-silent", "-AppleLanguages", "(\(language))"]
            app.launch()
            defer { app.terminate() }
            continueWelcome(app)
            XCTAssertTrue(app.buttons["sample-script"].waitForExistence(timeout: 5))
            app.buttons["sample-script"].click()
            let window = app.windows.firstMatch
            let before = window.frame
            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -14))
            corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: 900 - before.width, dy: 690 - before.height)))
            XCTAssertEqual(window.frame.width, 900, accuracy: 8)
            let locale = app.popUpButtons["speech-language"]
            XCTAssertTrue(locale.exists)
            XCTAssertFalse(app.staticTexts[language == "en" ? "Speech language" : "演讲语言"].exists)
            XCTAssertEqual(locale.frame.minX, app.textFields["script-title"].frame.minX, accuracy: 5)
            let text = app.textViews["script-editor"].value as? String
            for alignment in ["left", "right", "center"] {
                let segment = app.descendants(matching: .any).matching(identifier: "alignment-\(alignment)").firstMatch
                XCTAssertTrue(segment.isHittable)
                XCTAssertEqual(segment.frame.midY, app.buttons["save-script"].frame.midY, accuracy: 5)
                segment.click()
                XCTAssertEqual(app.textViews["script-editor"].value as? String, text)
                capture("21-editor-\(alignment)-\(language)", app)
            }
            let center = app.descendants(matching: .any).matching(identifier: "alignment-center").firstMatch
            let selectedValue = String(describing: center.value)
            XCTAssertNotNil(center.value)
            app.buttons["save-script"].click()
            app.terminate(); app.launch(); continueWelcome(app)
            let script = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library-script-")).firstMatch
            XCTAssertTrue(script.waitForExistence(timeout: 5)); script.click()
            XCTAssertEqual(String(describing: center.value), selectedValue)
            XCTAssertEqual(app.textViews["script-editor"].value as? String, text)
            // Keep the workspace key before invoking the native Settings shortcut.
            app.textFields["script-title"].click()
            app.typeKey(",", modifierFlags: .command)
            XCTAssertTrue(app.popUpButtons["theme-picker"].waitForExistence(timeout: 4))
            app.popUpButtons["theme-picker"].click()
            app.menuItems[language == "en" ? "Dark" : "深色"].click()
            closeSettings(app)
            capture("24-editor-centered-dark-\(language)", app)
            app.terminate()
        }
    }

    @MainActor func testCompactNativePalette() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "--ui-silent", "-AppleLanguages", "(en)"]
        app.launch(); continueWelcome(app)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["sample-script"].waitForExistence(timeout: 6))
        app.buttons["sample-script"].click()
        app.buttons["start-floating"].click()
        XCTAssertTrue(app.buttons["floating-settings"].waitForExistence(timeout: 5))
        app.buttons["floating-settings"].click()
        let settings = app.descendants(matching: .any).matching(identifier: "floating-settings-window").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertEqual(settings.scrollBars.count, 0)
        capture("15-floating-settings-compact-en", app)
        let well = app.colorWells["highlight-custom"]
        XCTAssertTrue(well.exists)
        let before = String(describing: well.value)
        chooseNativeHighlight(app)
        XCTAssertNotEqual(String(describing: well.value), before)
        capture("16-floating-settings-native-color", app)
        XCTAssertFalse(app.textFields["custom-highlight-hex"].exists)
        XCTAssertLessThan(settings.frame.height, 480)
        let selected = String(describing: well.value)
        app.buttons["close-floating-settings"].click()
        app.buttons["floating-settings"].click()
        XCTAssertEqual(String(describing: well.value), selected)
        app.buttons["close-floating-settings"].click()
        app.buttons["return-reader"].click()
        app.buttons["reader-settings"].click()
        app.colorWells["highlight-custom"].click()
        let fullPalette = app.descendants(matching: .any).matching(identifier: "highlight-color-panel").firstMatch
        XCTAssertTrue(fullPalette.waitForExistence(timeout: 3), "The native palette must stay available from reading settings")
        let attachment = XCTAttachment(screenshot: fullPalette.screenshot())
        attachment.name = "16-system-color-panel"; attachment.lifetime = .keepAlways; add(attachment)
        closeColorPalette(fullPalette)
        XCTAssertTrue(app.buttons["close-reading-settings"].exists)
    }
    @MainActor func testAllSettingsSurviveRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "--ui-silent", "-AppleLanguages", "(en)"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.checkBoxes["welcome-at-launch"].waitForExistence(timeout: 5))
        app.checkBoxes["welcome-at-launch"].click()
        app.buttons["welcome-continue"].click()
        app.buttons["sample-script"].click()
        app.buttons["start-speaking"].click()
        app.buttons["reader-settings"].click()
        let readerFont = app.sliders["reader-font-size"], readerGap = app.sliders["reader-line-spacing"]
        readerFont.adjust(toNormalizedSliderPosition: 0.6)
        readerGap.adjust(toNormalizedSliderPosition: 0.7)
        let savedReaderFont = String(describing: readerFont.value), savedReaderGap = String(describing: readerGap.value)
        app.checkBoxes["mirror-text"].click()
        app.checkBoxes["compatibility-recognition"].click()
        let savedMirror = String(describing: app.checkBoxes["mirror-text"].value)
        let savedCompatibility = String(describing: app.checkBoxes["compatibility-recognition"].value)
        app.popUpButtons["theme-picker"].click(); app.menuItems["Dark"].click()
        app.buttons["close-reading-settings"].click()
        app.buttons["show-floating"].click()
        app.buttons["floating-settings"].click()
        let font = app.sliders["floating-font-size"], gap = app.sliders["floating-line-spacing"], transparency = app.sliders["background-transparency"]
        font.adjust(toNormalizedSliderPosition: 0.3)
        gap.adjust(toNormalizedSliderPosition: 0.5)
        transparency.adjust(toNormalizedSliderPosition: 0.5)
        let savedFont = String(describing: font.value), savedGap = String(describing: gap.value), savedTransparency = String(describing: transparency.value)
        chooseNativeHighlight(app)
        let savedColor = String(describing: app.colorWells["highlight-custom"].value)
        app.descendants(matching: .any).matching(identifier: "size-wide").firstMatch.click()
        app.buttons["position-bottom-right"].click()
        let floating = app.descendants(matching: .any).matching(identifier: "floating-window").firstMatch
        let savedFrame = floating.frame
        app.buttons["close-floating-settings"].click()
        app.buttons["floating-end"].click()
        app.buttons["back-to-library"].click()
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "List")).firstMatch.click()
        app.terminate(); app.launch()
        let script = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library-script-")).firstMatch
        XCTAssertTrue(script.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["welcome-continue"].exists)
        XCTAssertLessThan(script.frame.height, 110)
        script.click()
        app.buttons["start-speaking"].click()
        app.buttons["reader-settings"].click()
        XCTAssertEqual(String(describing: readerFont.value), savedReaderFont)
        XCTAssertEqual(String(describing: readerGap.value), savedReaderGap)
        XCTAssertEqual(String(describing: app.checkBoxes["mirror-text"].value), savedMirror)
        XCTAssertEqual(String(describing: app.checkBoxes["compatibility-recognition"].value), savedCompatibility)
        XCTAssertEqual(app.popUpButtons["theme-picker"].value as? String, "Dark")
        XCTAssertEqual(String(describing: app.colorWells["highlight-custom"].value), savedColor)
        app.buttons["close-reading-settings"].click()
        app.buttons["show-floating"].click()
        XCTAssertEqual(floating.frame.minX, savedFrame.minX, accuracy: 2)
        XCTAssertEqual(floating.frame.minY, savedFrame.minY, accuracy: 2)
        XCTAssertEqual(floating.frame.width, savedFrame.width, accuracy: 2)
        XCTAssertEqual(floating.frame.height, savedFrame.height, accuracy: 2)
        app.buttons["floating-settings"].click()
        XCTAssertEqual(String(describing: font.value), savedFont)
        XCTAssertEqual(String(describing: gap.value), savedGap)
        XCTAssertEqual(String(describing: transparency.value), savedTransparency)
        XCTAssertEqual(String(describing: app.colorWells["highlight-custom"].value), savedColor)
        XCTAssertEqual(String(describing: app.checkBoxes["mirror-text"].value), savedMirror)
        capture("19-floating-settings-restored", app)
    }
    @MainActor func testWelcomeLibraryLayoutsSearchAndSave() throws {
        let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let sources = TISCreateInputSourceList([kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary, false).takeRetainedValue() as! [TISInputSource]
        XCTAssertEqual(TISSelectInputSource(try XCTUnwrap(sources.first)), noErr)
        defer { TISSelectInputSource(original) }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "--ui-silent", "-AppleLanguages", "(en)"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textViews["script-editor"].exists)
        capture("11-welcome-light", app)
        app.checkBoxes["welcome-at-launch"].click()
        app.buttons["welcome-continue"].click()
        XCTAssertTrue(app.buttons["sample-script"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["script-editor"].exists)
        app.buttons["sample-script"].click()
        XCTAssertTrue(app.textViews["script-editor"].waitForExistence(timeout: 5))
        let title = app.textFields["script-title"]
        title.click(); app.typeKey("a", modifierFlags: .command)
        title.typeText("Camera notes")
        app.buttons["back-to-library"].click()
        let scripts = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library-script-"))
        XCTAssertTrue(scripts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(scripts.firstMatch.label, "Camera notes")
        XCTAssertFalse(app.textViews["script-editor"].exists)
        for (name, text) in [
            ("A short introduction", "Hello, everyone. I am glad to be here. Today I want to share a simple idea: make room for your own voice."),
            ("Weekly team update", "This week we shipped the first milestone. Next, we will listen to feedback and make the small details feel better.")
        ] {
            app.buttons["new-script"].click()
            XCTAssertTrue(title.waitForExistence(timeout: 4))
            title.click(); app.typeKey("a", modifierFlags: .command); title.typeText(name)
            app.textViews["script-editor"].click(); app.textViews["script-editor"].typeText(text)
            app.buttons["back-to-library"].click()
        }
        XCTAssertEqual(scripts.count, 3)
        capture("12-library-grid", app)
        let search = app.searchFields["script-search"]
        app.typeKey("f", modifierFlags: .command); search.typeText("Camera")
        XCTAssertEqual(scripts.count, 1)
        search.click(); app.typeKey("a", modifierFlags: .command); app.typeKey(.delete, modifierFlags: [])
        search.typeText("roadmap")
        XCTAssertEqual(scripts.count, 1)
        XCTAssertEqual(scripts.firstMatch.label, "Camera notes")
        search.click(); app.typeKey("a", modifierFlags: .command); app.typeKey(.delete, modifierFlags: [])
        search.typeText("no-match-here")
        XCTAssertTrue(app.staticTexts["No scripts found"].waitForExistence(timeout: 3))
        XCTAssertEqual(scripts.count, 0)
        search.click(); app.typeKey("a", modifierFlags: .command); app.typeKey(.delete, modifierFlags: [])
        let list = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "List")).firstMatch
        XCTAssertTrue(list.exists)
        list.click()
        capture("13-library-list", app)
        app.terminate(); app.launch()
        XCTAssertTrue(scripts.firstMatch.waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["welcome-continue"].exists)
        // Check the restored layout itself; AppKit radio controls expose selection
        // differently across OS versions (value vs. selected accessibility trait).
        XCTAssertLessThan(scripts.firstMatch.frame.height, 110)
        scripts.matching(NSPredicate(format: "label == %@", "Camera notes")).firstMatch.click()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Camera notes")
        app.buttons["back-to-library"].click()
        app.typeKey(",", modifierFlags: .command)
        let theme = app.popUpButtons["theme-picker"]
        XCTAssertTrue(theme.waitForExistence(timeout: 4))
        theme.click(); app.menuItems["Dark"].click()
        closeSettings(app)
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Grid")).firstMatch.click()
        capture("14-library-dark", app)
    }
    @MainActor func testChineseAndEnglishAtNarrowWindowSize() throws {
        let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let sources = TISCreateInputSourceList([kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary, false).takeRetainedValue() as! [TISInputSource]
        XCTAssertEqual(TISSelectInputSource(try XCTUnwrap(sources.first)), noErr)
        defer { TISSelectInputSource(original) }
        for language in ["zh-Hans", "en"] {
            let chinese = language == "zh-Hans"
            let app = XCUIApplication()
            app.launchArguments = ["--ui-library=\(UUID())", "--ui-silent", "-AppleLanguages", "(\(language))"]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 8))
            let window = app.windows.firstMatch
            let before = window.frame
            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -14))
            corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: 900 - before.width, dy: 690 - before.height)))
            XCTAssertEqual(window.frame.width, 900, accuracy: 8)
            capture("15-\(language)-welcome-narrow", app)
            app.buttons["welcome-continue"].click()
            XCTAssertTrue(app.buttons["sample-script"].waitForExistence(timeout: 5))
            app.buttons["sample-script"].click()
            let title = app.textFields["script-title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            title.click(); app.typeKey("a", modifierFlags: .command)
            title.typeText("Quarterly team review and presentation notes for the next product milestone")
            for id in ["new-script", "import-script", "start-speaking", "start-floating", "back-to-library", "open-pronunciation", "save-script"] {
                let control = app.buttons[id]
                XCTAssertTrue(control.exists, id)
                let toolbarItem = !["open-pronunciation", "save-script"].contains(id)
                XCTAssertLessThanOrEqual(control.frame.height, toolbarItem ? 56 : 40, "Unexpected wrapping: \(id) / \(language)")
                XCTAssertGreaterThanOrEqual(control.frame.minX, window.frame.minX, id)
                XCTAssertLessThanOrEqual(control.frame.maxX, window.frame.maxX, id)
            }
            capture("16-\(language)-editor-narrow", app)
            app.buttons["back-to-library"].click()
            XCTAssertTrue(app.searchFields["script-search"].exists)
            XCTAssertGreaterThan(app.searchFields["script-search"].frame.width, 180)
            capture("17-\(language)-grid-narrow", app)
            app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", chinese ? "列表" : "List")).firstMatch.click()
            capture("18-\(language)-list-narrow", app)
            app.typeKey(",", modifierFlags: .command)
            let theme = app.popUpButtons["theme-picker"]
            XCTAssertTrue(theme.waitForExistence(timeout: 4))
            theme.click(); app.menuItems[chinese ? "深色" : "Dark"].click()
            closeSettings(app)
            capture("19-\(language)-list-dark-narrow", app)
            app.menuBars.menuBarItems[chinese ? "稿库" : "Library"].click()
            app.menuItems[chinese ? "显示欢迎页" : "Show welcome"].click()
            XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 4))
            capture("20-\(language)-welcome-dark-narrow", app)
            app.terminate()
        }
    }
    @MainActor func testFloatingControlsKeepTencentForeground() async throws {
        guard FileManager.default.fileExists(atPath: "/Applications/TencentMeeting.app") else { throw XCTSkip("Tencent Meeting is not installed") }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "--ui-silent", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        continueWelcome(app)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["sample-script"].waitForExistence(timeout: 8))
        app.buttons["sample-script"].click()
        app.buttons["start-floating"].click()
        XCTAssertTrue(app.buttons["floating-settings"].waitForExistence(timeout: 6))
        let meeting = XCUIApplication(bundleIdentifier: "com.tencent.meeting")
        meeting.activate()
        let anchor = meeting.menuBars.firstMatch
        XCTAssertTrue(anchor.waitForExistence(timeout: 3))
        // A normal XCUIElement.click() may activate the target app. Send actual mouse
        // clicks from the already-foreground meeting's coordinate space instead.
        for identifier in ["floating-pick-up", "floating-settings", "size-wide", "position-top-left", "position-top-right", "position-bottom-left", "position-bottom-right", "near-camera", "highlight-green"] {
            let button = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            let frame = button.frame
            let origin = anchor.frame.origin
            guard origin.x.isFinite, origin.y.isFinite, frame.midX.isFinite, frame.midY.isFinite else {
                XCTFail("Native window coordinates are unavailable")
                return
            }
            anchor.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX - origin.x, dy: frame.midY - origin.y)).click()
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.tencent.meeting", "Control activated Oralo: \(identifier)")
        }
        let well = app.colorWells["highlight-custom"]
        let oldColor = String(describing: well.value)
        let wellFrame = well.frame, anchorFrame = anchor.frame
        anchor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: wellFrame.midX - anchorFrame.minX, dy: wellFrame.midY - anchorFrame.minY)).click()
        let palette = app.descendants(matching: .any).matching(identifier: "highlight-color-panel").firstMatch
        XCTAssertTrue(palette.waitForExistence(timeout: 3))
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.tencent.meeting")
        let paletteFrame = palette.frame
        anchor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: paletteFrame.minX + paletteFrame.width * 0.3 - anchorFrame.minX, dy: paletteFrame.minY + paletteFrame.height * 0.38 - anchorFrame.minY)).click()
        XCTAssertNotEqual(String(describing: well.value), oldColor)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.tencent.meeting")
        let closePalette = colorPaletteCloseButton(palette).frame
        anchor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: closePalette.midX - anchorFrame.minX, dy: closePalette.midY - anchorFrame.minY)).click()
        XCTAssertFalse(palette.exists)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.tencent.meeting")
        let panel = app.descendants(matching: .any).matching(identifier: "floating-window").firstMatch
        XCTAssertEqual(panel.frame.width, 680, accuracy: 3)
        let slider = app.sliders["background-transparency"]
        let previousValue = String(describing: slider.value)
        let sliderFrame = slider.frame
        anchor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: sliderFrame.minX + sliderFrame.width * 0.75 - anchor.frame.minX,
                                 dy: sliderFrame.midY - anchor.frame.minY)).click()
        XCTAssertNotEqual(String(describing: slider.value), previousValue)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.tencent.meeting")
        let close = app.buttons["close-floating-settings"].frame
        anchor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: close.midX - anchor.frame.minX, dy: close.midY - anchor.frame.minY)).click()
        XCTAssertFalse(app.buttons["close-floating-settings"].exists)
        XCTAssertTrue(panel.exists)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.tencent.meeting")
    }
    @MainActor func testRemainingSettingsAndPaletteModeKeepTencentForeground() throws {
        guard FileManager.default.fileExists(atPath: "/Applications/TencentMeeting.app") else { throw XCTSkip("Tencent Meeting is not installed") }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "--ui-silent", "-AppleLanguages", "(en)"]
        app.launch(); continueWelcome(app)
        defer { app.terminate() }
        app.buttons["sample-script"].click()
        app.buttons["start-floating"].click()
        app.buttons["floating-settings"].click()
        let meeting = XCUIApplication(bundleIdentifier: "com.tencent.meeting")
        meeting.activate()
        let anchor = meeting.menuBars.firstMatch
        XCTAssertTrue(anchor.waitForExistence(timeout: 3))
        func click(_ element: XCUIElement, x: CGFloat = 0.5, y: CGFloat = 0.5) {
            let frame = element.frame, origin = anchor.frame.origin
            XCTAssertTrue(frame.minX.isFinite && frame.minY.isFinite && frame.width > 0)
            anchor.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.minX + frame.width * x - origin.x, dy: frame.minY + frame.height * y - origin.y)).click()
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.tencent.meeting")
        }
        for id in ["floating-font-size", "floating-line-spacing"] {
            let slider = app.sliders[id]
            let old = String(describing: slider.value)
            click(slider, x: 0.65)
            XCTAssertNotEqual(String(describing: slider.value), old)
        }
        let mirror = app.checkBoxes["mirror-text"]
        let oldMirror = String(describing: mirror.value)
        click(mirror)
        XCTAssertNotEqual(String(describing: mirror.value), oldMirror)
        click(app.popUpButtons["theme-picker"])
        let dark = app.menuItems["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 3))
        click(dark)
        XCTAssertEqual(app.popUpButtons["theme-picker"].value as? String, "Dark")
        let well = app.colorWells["highlight-custom"]
        click(well)
        let palette = app.descendants(matching: .any).matching(identifier: "highlight-color-panel").firstMatch
        XCTAssertTrue(palette.waitForExistence(timeout: 3))
        // The second toolbar item is the native color-sliders tab.
        click(palette, x: 95 / palette.frame.width, y: 38 / palette.frame.height)
        let mode = palette.popUpButtons.firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 3))
        let selectedMode = String(describing: mode.value)
        click(colorPaletteCloseButton(palette))
        XCTAssertFalse(palette.exists)
        click(well)
        XCTAssertTrue(palette.waitForExistence(timeout: 3))
        XCTAssertTrue(mode.exists)
        XCTAssertEqual(String(describing: mode.value), selectedMode)
        click(colorPaletteCloseButton(palette))
        click(app.buttons["close-floating-settings"])
        XCTAssertFalse(app.buttons["close-floating-settings"].exists)
    }
    @MainActor func testPronunciationSelectionPlaybackAndReopen() throws {
        // XCTest synthesizes physical keys through the Mac's active input method.
        // Isolate the English fixture from a user's Chinese IME; restore it on exit.
        let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
        let english = try XCTUnwrap(sources.first)
        XCTAssertEqual(TISSelectInputSource(english), noErr)
        defer { TISSelectInputSource(original) }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "--ui-silent", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        continueWelcome(app)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["new-script"].waitForExistence(timeout: 6))
        app.buttons["new-script"].click()
        let body = app.textViews["script-editor"]
        XCTAssertTrue(body.waitForExistence(timeout: 4))
        body.click()
        for character in "roadmap" { app.typeKey(String(character), modifierFlags: []) }
        guard body.value as? String == "roadmap" else {
            XCTFail("English fixture was not entered into the editor")
            return
        }
        app.typeKey("a", modifierFlags: [.command])
        XCTAssertTrue(app.buttons["open-pronunciation"].isEnabled)
        app.buttons["open-pronunciation"].click()
        let field = app.textFields["pronunciation-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        XCTAssertTrue(NSPredicate(format: "value CONTAINS %@", "mæp").evaluate(with: field)
            || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "mæp"), object: field)], timeout: 5) == .completed)
        let reading = field.value as? String ?? ""
        XCTAssertTrue(reading.contains("mæp"))
        app.buttons["pronunciation-listen"].click()
        app.buttons["pronunciation-save"].click()
        XCTAssertTrue(app.buttons["start-speaking"].waitForExistence(timeout: 4))
        app.buttons["save-script"].click()
        app.terminate()
        app.launch()
        continueWelcome(app)
        let savedScript = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library-script-")).firstMatch
        XCTAssertTrue(savedScript.waitForExistence(timeout: 6))
        savedScript.click()
        XCTAssertTrue(body.waitForExistence(timeout: 6))
        body.click()
        app.typeKey("a", modifierFlags: [.command])
        app.buttons["open-pronunciation"].click()
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        XCTAssertEqual(field.value as? String, reading)
        app.buttons["pronunciation-save"].click()
        capture("09-workspace-pronunciation", app)
        app.buttons["start-speaking"].click()
        XCTAssertTrue(app.buttons["reader-next"].waitForExistence(timeout: 4))
        capture("10-reader-pronunciation", app)
    }
    @MainActor func testPreparePresentFloatAndReturn() throws {
        for language in ["zh-Hans", "en"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-library=\(UUID())", "--ui-silent", "-AppleLanguages", "(\(language))"]
            app.launch()
            continueWelcome(app)
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["sample-script"].waitForExistence(timeout: 8))
            app.buttons["sample-script"].click()
            XCTAssertTrue(app.buttons["start-speaking"].waitForExistence(timeout: 5))
            app.buttons["start-speaking"].click()
            XCTAssertTrue(app.buttons["reader-next"].waitForExistence(timeout: 5))
            app.buttons["reader-next"].click()
            app.buttons["reader-next"].click()
            let reader = app.windows.matching(identifier: "presentation-window").firstMatch
            let sentence = reader.textViews.firstMatch.value as? String
            XCTAssertNotNil(sentence)
            app.buttons["reader-settings"].click()
            let readerGap = app.sliders["reader-line-spacing"]
            XCTAssertTrue(readerGap.waitForExistence(timeout: 3))
            readerGap.adjust(toNormalizedSliderPosition: 0.25)
            app.buttons["highlight-blue"].click()
            XCTAssertTrue(app.colorWells["highlight-custom"].exists)
            let readingControls = app.popovers.firstMatch
            XCTAssertEqual(readingControls.scrollBars.count, 0)
            let settingsShot = XCTAttachment(screenshot: readingControls.screenshot())
            settingsShot.name = "17-reading-settings-\(language)"; settingsShot.lifetime = .keepAlways; add(settingsShot)
            app.buttons["close-reading-settings"].click()
            XCTAssertEqual(reader.textViews.firstMatch.value as? String, sentence)
            capture("02-presentation-\(language)", app)
            let corner = reader.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -14))
            corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: 620 - reader.frame.width, dy: 520 - reader.frame.height)))
            for id in ["reader-back", "reader-next", "reader-pick-up", "reader-settings", "show-floating"] {
                let control = app.buttons[id]
                XCTAssertTrue(control.isHittable, id)
                XCTAssertLessThanOrEqual(control.frame.maxX, reader.frame.maxX, id)
            }
            capture("02-presentation-narrow-\(language)", app)
            app.buttons["show-floating"].click()
            XCTAssertTrue(app.buttons["floating-settings"].waitForExistence(timeout: 5))
            let floating = app.descendants(matching: .any).matching(identifier: "floating-window").firstMatch
            app.buttons["floating-near-camera"].click()
            capture("03-floating-\(language)", app)
            app.buttons["floating-settings"].click()
            let wide = app.descendants(matching: .any).matching(identifier: "size-wide").firstMatch
            XCTAssertTrue(wide.waitForExistence(timeout: 3))
            for (preset, width) in [("compact", 360.0), ("standard", 520.0), ("wide", 680.0)] {
                app.descendants(matching: .any).matching(identifier: "size-" + preset).firstMatch.click()
                XCTAssertEqual(floating.frame.width, width, accuracy: 3)
                XCTAssertEqual(floating.textViews.firstMatch.value as? String, sentence)
                capture("03-floating-\(preset)-\(language)", app)
            }
            app.buttons["near-camera"].click()
            let slider = app.sliders["background-transparency"]
            XCTAssertTrue(slider.exists)
            slider.adjust(toNormalizedSliderPosition: 0.75)
            let gap = app.sliders["floating-line-spacing"]
            XCTAssertTrue(gap.exists)
            gap.adjust(toNormalizedSliderPosition: 0.5)
            let spacing = String(describing: gap.value)
            app.buttons["highlight-green"].click()
            XCTAssertTrue(app.buttons["highlight-green"].isSelected)
            XCTAssertEqual(floating.textViews.firstMatch.value as? String, sentence)
            capture("04-floating-settings-\(language)", app)
            let settings = app.descendants(matching: .any).matching(identifier: "floating-settings-window").firstMatch
            XCTAssertEqual(settings.scrollBars.count, 0)
            XCTAssertLessThan(settings.frame.height, 480)
            let dimensions = app.staticTexts["floating-dimensions"]
            let compact = app.descendants(matching: .any).matching(identifier: "size-compact").firstMatch
            XCTAssertEqual(dimensions.frame.midY, compact.frame.midY, accuracy: 3)
            let nearCamera = floating.frame
            for corner in ["top-left", "top-right", "bottom-left", "bottom-right"] {
                app.buttons["position-" + corner].click()
                XCTAssertEqual(floating.textViews.firstMatch.value as? String, sentence)
                if corner.hasSuffix("left") { XCTAssertLessThan(floating.frame.minX, nearCamera.minX) }
                else { XCTAssertGreaterThan(floating.frame.minX, nearCamera.minX) }
                if corner.hasPrefix("bottom") { XCTAssertGreaterThan(floating.frame.minY, nearCamera.minY) }
            }
            app.buttons["near-camera"].click()
            chooseNativeHighlight(app)
            let well = app.colorWells["highlight-custom"]
            let selectedColor = String(describing: well.value)
            capture("04-floating-settings-custom-\(language)", app)
            app.buttons["close-floating-settings"].click()
            app.buttons["floating-settings"].click()
            XCTAssertTrue(well.waitForExistence(timeout: 3))
            XCTAssertEqual(String(describing: well.value), selectedColor)
            XCTAssertEqual(String(describing: gap.value), spacing)
            XCTAssertEqual(floating.textViews.firstMatch.value as? String, sentence)
            app.buttons["close-floating-settings"].click()
            let resize = floating.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -12, dy: -12))
            let previousSize = floating.frame.size
            resize.press(forDuration: 0.2, thenDragTo: resize.withOffset(CGVector(dx: 60, dy: 30)))
            XCTAssertGreaterThan(floating.frame.width, previousSize.width + 30)
            XCTAssertEqual(floating.textViews.firstMatch.value as? String, sentence)
            app.buttons["return-reader"].click()
            XCTAssertTrue(app.buttons["reader-next"].waitForExistence(timeout: 3))
            XCTAssertEqual(reader.textViews.firstMatch.value as? String, sentence)
            app.buttons["reader-settings"].click()
            XCTAssertEqual(String(describing: app.colorWells["highlight-custom"].value), selectedColor)
            app.buttons["close-reading-settings"].click()
            capture("05-returned-reader-\(language)", app)
            app.terminate()
        }
    }
    @MainActor func testTencentForegroundCoexistenceAndDarkAppearance() throws {
        guard FileManager.default.fileExists(atPath: "/Applications/TencentMeeting.app") else { throw XCTSkip("Tencent Meeting is not installed") }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "--ui-silent", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        continueWelcome(app)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["sample-script"].waitForExistence(timeout: 6))
        app.buttons["sample-script"].click()
        app.buttons["start-floating"].click()
        XCTAssertTrue(app.buttons["floating-settings"].waitForExistence(timeout: 5))
        app.buttons["floating-settings"].click()
        let picker = app.popUpButtons["theme-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.click()
        app.menuItems["深色"].click()
        app.buttons["highlight-amber"].click()
        XCTAssertTrue(app.buttons["highlight-amber"].isSelected)
        capture("04-floating-settings-dark", app)
        app.colorWells["highlight-custom"].click()
        let darkPalette = app.descendants(matching: .any).matching(identifier: "highlight-color-panel").firstMatch
        XCTAssertTrue(darkPalette.waitForExistence(timeout: 3))
        let paletteShot = XCTAttachment(screenshot: darkPalette.screenshot())
        paletteShot.name = "18-system-palette-dark"; paletteShot.lifetime = .keepAlways; add(paletteShot)
        closeColorPalette(darkPalette)
        app.descendants(matching: .any).matching(identifier: "size-standard").firstMatch.click()
        if app.buttons["close-floating-settings"].exists { app.buttons["close-floating-settings"].click() }
        capture("06-floating-dark", app)
        let meeting = XCUIApplication(bundleIdentifier: "com.tencent.meeting")
        meeting.activate() // Never creates, joins, records or ends a meeting.
        XCTAssertEqual(meeting.state, .runningForeground)
        let panel = app.descendants(matching: .any).matching(identifier: "floating-window").firstMatch
        XCTAssertTrue(panel.exists)
        XCTAssertTrue(app.buttons["floating-settings"].exists)
        XCTAssertEqual(meeting.state, .runningForeground)
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        XCTAssertEqual(front, "com.tencent.meeting")
        let frame = panel.frame
        XCTAssertEqual(frame.width, 520, accuracy: 3)
        capture("07-floating-over-tencent", app)
        app.activate()
        app.buttons["return-reader"].click()
        capture("08-reader-dark", app)
        app.terminate()
    }
    @MainActor private func chooseNativeHighlight(_ app: XCUIApplication) {
        let well = app.colorWells["highlight-custom"]
        let before = String(describing: well.value)
        well.click()
        // Select a point inside the native color wheel with an actual pointer click.
        let palette = app.descendants(matching: .any).matching(identifier: "highlight-color-panel").firstMatch
        XCTAssertTrue(palette.waitForExistence(timeout: 3))
        palette.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.38)).click()
        XCTAssertNotEqual(String(describing: well.value), before)
        closeColorPalette(palette)
    }
    @MainActor private func colorPaletteCloseButton(_ palette: XCUIElement) -> XCUIElement {
        palette.buttons.matching(NSPredicate(format: "identifier == %@ OR label CONTAINS[c] %@ OR label CONTAINS %@", "_XCUI:CloseWindow", "close", "关闭")).firstMatch
    }
    @MainActor private func closeColorPalette(_ palette: XCUIElement) {
        let close = colorPaletteCloseButton(palette)
        XCTAssertTrue(close.exists)
        close.click()
        XCTAssertTrue(palette.waitForNonExistence(timeout: 3))
    }
    @MainActor private func closeSettings(_ app: XCUIApplication) {
        let window = app.windows.containing(.popUpButton, identifier: "theme-picker").firstMatch
        XCTAssertTrue(window.exists)
        let close = window.buttons.matching(NSPredicate(format: "identifier == %@ OR label CONTAINS[c] %@ OR label CONTAINS %@", "_XCUI:CloseWindow", "close", "关闭")).firstMatch
        if close.exists { close.click() }
        else { window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 16, dy: 16)).click() }
        XCTAssertTrue(window.waitForNonExistence(timeout: 4))
    }
    @MainActor private func continueWelcome(_ app: XCUIApplication) {
        let button = app.buttons["welcome-continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.click()
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let identifier = name.contains("floating-settings") ? "floating-settings-window" : name.contains("floating") ? "floating-window" : name.contains("reader") || name.contains("presentation") ? "presentation-window" : "workspace"
        let window = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let attachment = XCTAttachment(screenshot: window.exists ? window.screenshot() : app.windows.firstMatch.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
