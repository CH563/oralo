import XCTest

final class LibraryUITests: XCTestCase {
    @MainActor private func app(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID().uuidString)", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["new-script-menu"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    func testCreateAutosaveRelaunchAndManualPresentation() {
        let app = app()
        openNewScriptMenu(app)
        app.buttons["new-script"].tap()
        let editor = app.textViews["saved-script-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        editor.tap()
        editor.typeText("First we share the quarterly results.\nNext we improve delivery quality.\nThank you for listening.")
        XCTAssertTrue(app.staticTexts["Saved on this device"].waitForExistence(timeout: 8))
        // Kill from the editor after autosave, without Save or navigating back.
        app.terminate(); app.launch()
        let card = app.buttons["script-Untitled script"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        capture(app, name: "Library with saved draft")
        card.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains("delivery quality"))
        capture(app, name: "Editor with saved draft")
        editorAction(app, "start-manual")
        XCTAssertTrue(app.buttons["readiness-start-manual"].waitForExistence(timeout: 5)); app.buttons["readiness-start-manual"].tap()
        XCTAssertTrue(app.buttons["show-controls-waveform"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["next-cue"].exists)
        app.buttons["show-controls-waveform"].tap()
        XCTAssertEqual(app.staticTexts["presentation-position"].label, "1 / 3")
        XCTAssertTrue(app.staticTexts["Manual"].exists)
        app.buttons["next-cue"].tap()
        XCTAssertEqual(app.staticTexts["presentation-position"].label, "2 / 3")
        app.buttons["start-stop"].tap()
        XCTAssertTrue(app.staticTexts["Paused · Manual"].exists)
        app.buttons["start-stop"].tap()
        app.buttons["recovery"].tap()
        XCTAssertTrue(app.buttons["recover-0"].waitForExistence(timeout: 5))
        app.buttons["recover-0"].tap()
        XCTAssertEqual(app.staticTexts["presentation-position"].label, "1 / 3")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Saved script in manual presentation"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["exit-presentation"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["finish-session"].waitForExistence(timeout: 5)); app.buttons["finish-session"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["review-back-script"].waitForExistence(timeout: 8)); app.buttons["review-back-script"].tap()
        XCTAssertTrue(app.buttons["script-options"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists, "Manual flow must not request microphone permissions.")
    }

    @MainActor
    func testPasteRenameAndDeletePersist() {
        let app = app()
        openNewScriptMenu(app)
        app.buttons["paste-script"].tap()
        let title = app.textFields["paste-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Team report")
        let text = app.textViews["paste-text"]; text.tap(); text.typeText("Our team is ready.\nWe will start today.")
        app.buttons["add-pasted-script"].tap()
        XCTAssertTrue(app.textFields["script-title"].waitForExistence(timeout: 8))
        let savedTitle = app.textFields["script-title"]
        savedTitle.tap()
        savedTitle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Team report".count) + "Board report")
        editorAction(app, "save-script")
        app.buttons["back-to-library"].tap()
        let card = app.buttons["script-Board report"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        app.terminate(); app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.press(forDuration: 1)
        app.buttons["Delete"].tap()
        app.buttons["Delete “Board report”"].tap()
        XCTAssertTrue(app.buttons["sample-script"].waitForExistence(timeout: 8))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["sample-script"].waitForExistence(timeout: 10))
        XCTAssertFalse(card.exists)
    }

    @MainActor
    func testImportedMarkdownSentenceLayoutUndoAndReopen() {
        let app = app(extra: ["--ui-import-fixture"])
        openNewScriptMenu(app)
        app.buttons["import-script"].tap()
        let editor = app.textViews["saved-script-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertTrue((editor.value as? String ?? "").hasPrefix("# Quarterly report"))
        editorAction(app, "toggle-sentences")
        XCTAssertEqual(app.staticTexts["sentence-count"].label, "3 sentences")
        app.buttons["split-0"].tap()
        XCTAssertTrue(app.buttons["confirm-split"].waitForExistence(timeout: 5))
        app.buttons["confirm-split"].tap()
        XCTAssertEqual(app.staticTexts["sentence-count"].label, "4 sentences")
        editorAction(app, "undo-edit")
        XCTAssertEqual(app.staticTexts["sentence-count"].label, "3 sentences")
        app.buttons["merge-0"].tap()
        XCTAssertEqual(app.staticTexts["sentence-count"].label, "2 sentences")
        app.buttons["pause-mark-0"].tap()
        capture(app, name: "Sentence layout with pause mark")
        editorAction(app, "save-script")
        app.buttons["back-to-library"].tap()
        app.terminate(); app.launch()
        let card = app.buttons["script-Imported report"]
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        editorAction(app, "toggle-sentences")
        XCTAssertEqual(app.staticTexts["sentence-count"].label, "2 sentences")
        XCTAssertEqual(app.buttons["pause-mark-0"].label, "Unmark")
        editorAction(app, "start-manual")
        XCTAssertTrue(app.buttons["readiness-start-manual"].waitForExistence(timeout: 5)); app.buttons["readiness-start-manual"].tap()
        XCTAssertTrue(app.buttons["show-controls-waveform"].waitForExistence(timeout: 8))
        capture(app, name: "Immersive saved manuscript")
        app.buttons["show-controls-waveform"].tap()
        XCTAssertEqual(app.staticTexts["presentation-position"].label, "1 / 2")
        app.buttons["next-cue"].tap()
        XCTAssertEqual(app.staticTexts["presentation-position"].label, "2 / 2")
        let line = app.staticTexts["reading-line"]
        let viewport = app.descendants(matching: .any)["script-scroll"].firstMatch
        expectation(for: NSPredicate { _, _ in
            abs(line.frame.midY - (viewport.frame.minY + viewport.frame.height * 0.34)) < 6
        }, evaluatedWith: line)
        waitForExpectations(timeout: 4)
    }

    @MainActor
    func testEmptyDraftDoesNotOpenPresentationAndFilePickerCanCancel() {
        let app = app()
        openNewScriptMenu(app)
        app.buttons["import-script"].tap()
        // The system Files extension can take longer to cold-launch on a simulator.
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 25))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForNonExistence(timeout: 5))
        openNewScriptMenu(app)
        app.buttons["new-script"].tap()
        XCTAssertTrue(app.buttons["start-voice"].waitForExistence(timeout: 8))
        editorAction(app, "start-manual")
        XCTAssertTrue(app.alerts["Check your script"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["script-options"].exists)
        XCTAssertEqual(app.staticTexts["save-status"].label, "Saved on this device")
    }

    @MainActor private func editorAction(_ app: XCUIApplication, _ action: String) {
        app.buttons["script-options"].tap()
        XCTAssertTrue(app.buttons[action].waitForExistence(timeout: 5))
        app.buttons[action].tap()
    }

    @MainActor private func openNewScriptMenu(_ app: XCUIApplication) {
        let menu = app.buttons["new-script-menu"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: menu)
        waitForExpectations(timeout: 5)
        // On iOS 18, Menu's accessibility wrapper can report a false hit point.
        // Tap the visible control's center, as a user would, then verify its actions.
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["new-script"].waitForExistence(timeout: 5))
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
