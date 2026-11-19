import XCTest

final class PronunciationUITests: XCTestCase {
    @MainActor private func launch(seeded: Bool = false, dark: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID().uuidString)", "--ui-pronunciation-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", dark ? "--ui-appearance=dark" : "--ui-appearance=light"]
        if seeded { app.launchArguments.append("--ui-pronunciation-seeded") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let card = app.buttons["script-Reading rehearsal"]
        XCTAssertTrue(card.waitForExistence(timeout: 15)); card.tap()
        XCTAssertTrue(app.textViews["saved-script-editor"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor func testSelectWordListenSaveReopenAndSpeak() {
        let app = launch()
        let text = app.textViews["saved-script-editor"]
        // Real text selection and UIKit edit menu, rather than a test-only sheet shortcut.
        text.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 65, dy: 27)).doubleTap()
        let action = app.menuItems["Pronunciation"]
        XCTAssertTrue(action.waitForExistence(timeout: 5), app.debugDescription)
        action.tap()
        let input = app.textFields["pronunciation-input"]
        let multiline = app.textViews["pronunciation-input"]
        XCTAssertTrue(app.buttons["pronunciation-save"].waitForExistence(timeout: 5))
        let field = input.exists ? input : multiline
        expectation(for: NSPredicate { _, _ in (field.value as? String ?? "").contains("roʊd") || (field.value as? String ?? "").contains("ɹoʊd") }, evaluatedWith: field)
        waitForExpectations(timeout: 6)
        XCTAssertTrue(app.buttons["pronunciation-listen"].isEnabled)
        capture(app, "01-english-pronunciation")
        app.buttons["pronunciation-listen"].tap()
        app.buttons["pronunciation-save"].tap()
        XCTAssertTrue(app.buttons["pronunciation-count"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.buttons["script-Reading rehearsal"].tap()
        XCTAssertTrue(app.buttons["pronunciation-count"].waitForExistence(timeout: 5))
        capture(app, "02-saved-preparation")
        options(app, "start-manual")
        XCTAssertTrue(app.buttons["readiness-start-manual"].waitForExistence(timeout: 5)); app.buttons["readiness-start-manual"].tap()
        XCTAssertTrue(app.buttons["show-controls-waveform"].waitForExistence(timeout: 5))
        assertAnchor(app)
        capture(app, "03-annotated-presentation")
        XCTAssertFalse(app.buttons["pronunciation-listen"].exists)
        app.buttons["show-controls-waveform"].tap()
        app.buttons["next-cue"].tap()
        assertAnchor(app)
        app.buttons["exit-presentation"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["finish-session"].waitForExistence(timeout: 5)); app.buttons["finish-session"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["review-back-script"].waitForExistence(timeout: 8)); app.buttons["review-back-script"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
    }

    @MainActor func testEditChineseCustomIPAHideDeleteAndUndo() {
        let app = launch(seeded: true, dark: true)
        openReading(app, "夯实")
        capture(app, "04-chinese-dark")
        app.buttons["pronunciation-cancel"].tap()
        openReading(app, "roadmap")
        let field = app.textFields["pronunciation-input"].exists ? app.textFields["pronunciation-input"] : app.textViews["pronunciation-input"]
        field.tap(); field.typeText("x")
        XCTAssertFalse(app.buttons["pronunciation-listen"].isEnabled)
        capture(app, "05-custom-ipa-dark")
        app.buttons["pronunciation-restore"].tap()
        XCTAssertTrue(app.buttons["pronunciation-listen"].isEnabled)
        app.switches["pronunciation-show"].tap()
        app.buttons["pronunciation-save"].tap()
        openReading(app, "roadmap")
        XCTAssertEqual(app.switches["pronunciation-show"].value as? String, "0")
        app.buttons["pronunciation-remove"].tap()
        let undo = app.buttons["undo-pronunciation-removal"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.buttons["pronunciation-count"].label.contains("3"))
        options(app, "start-manual")
        XCTAssertTrue(app.buttons["readiness-start-manual"].waitForExistence(timeout: 5)); app.buttons["readiness-start-manual"].tap()
        XCTAssertTrue(app.buttons["show-controls-waveform"].waitForExistence(timeout: 5))
        app.buttons["show-controls-waveform"].tap(); app.buttons["next-cue"].tap()
        assertAnchor(app)
        app.buttons["hide-controls"].tap()
        capture(app, "06-pinyin-speaking-dark")
    }

    @MainActor func testAnnotatedReadingAtAccessibilitySize() {
        let app = launch(seeded: true, large: true)
        options(app, "start-manual")
        XCTAssertTrue(app.buttons["readiness-start-manual"].waitForExistence(timeout: 5)); app.buttons["readiness-start-manual"].tap()
        XCTAssertTrue(app.buttons["show-controls-waveform"].waitForExistence(timeout: 5))
        assertAnchor(app)
        capture(app, "07-accessibility-reading")
        app.buttons["show-controls-waveform"].tap(); app.buttons["next-cue"].tap()
        assertAnchor(app)
    }

    @MainActor func testAddChinesePinyinFromSelectedText() {
        let app = launch()
        let text = app.textViews["saved-script-editor"]
        text.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 42, dy: 84)).doubleTap()
        XCTAssertTrue(app.menuItems["Pronunciation"].waitForExistence(timeout: 5))
        app.menuItems["Pronunciation"].tap()
        XCTAssertTrue(app.buttons["pronunciation-save"].waitForExistence(timeout: 5))
        let field = app.textFields["pronunciation-input"].exists ? app.textFields["pronunciation-input"] : app.textViews["pronunciation-input"]
        expectation(for: NSPredicate { _, _ in (field.value as? String ?? "").contains("hāng") }, evaluatedWith: field)
        waitForExpectations(timeout: 5)
        capture(app, "08-add-pinyin-light")
        app.buttons["pronunciation-save"].tap()
        XCTAssertTrue(app.buttons["pronunciation-count"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.buttons["script-Reading rehearsal"].tap()
        XCTAssertTrue(app.buttons["pronunciation-count"].waitForExistence(timeout: 5))
    }

    @MainActor func testEditingAnnotatedWordRequiresReviewAndUndoRestoresIt() {
        let app = launch(seeded: true)
        let text = app.textViews["saved-script-editor"]
        // Enter text editing beside the first word; tapping its annotation opens the sheet.
        text.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 250, dy: 45)).tap()
        text.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 65, dy: 45)).doubleTap()
        XCTAssertTrue(app.menuItems["Cut"].waitForExistence(timeout: 5))
        app.menuItems["Cut"].tap()
        XCTAssertTrue(app.staticTexts["reading-needs-review"].waitForExistence(timeout: 5))
        options(app, "undo-edit")
        XCTAssertTrue(app.staticTexts["reading-needs-review"].waitForNonExistence(timeout: 5))
        XCTAssertTrue((text.value as? String ?? "").hasPrefix("roadmap"))
        XCTAssertTrue(app.buttons["pronunciation-count"].label.contains("3"))
    }

    @MainActor private func openReading(_ app: XCUIApplication, _ term: String) {
        XCTAssertTrue(app.buttons["pronunciation-count"].waitForExistence(timeout: 5))
        app.buttons["pronunciation-count"].tap()
        XCTAssertTrue(app.buttons["reading-item-\(term)"].waitForExistence(timeout: 5))
        app.buttons["reading-item-\(term)"].tap()
        XCTAssertTrue(app.buttons["pronunciation-save"].waitForExistence(timeout: 5))
    }
    @MainActor private func options(_ app: XCUIApplication, _ action: String) {
        app.buttons["script-options"].tap()
        XCTAssertTrue(app.buttons[action].waitForExistence(timeout: 5)); app.buttons[action].tap()
    }
    @MainActor private func assertAnchor(_ app: XCUIApplication) {
        let line = app.staticTexts["reading-line"], viewport = app.descendants(matching: .any)["script-scroll"].firstMatch
        expectation(for: NSPredicate { _, _ in
            abs(line.frame.midY - (viewport.frame.minY + viewport.frame.height * 0.34)) < 6
        }, evaluatedWith: line)
        waitForExpectations(timeout: 4)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
