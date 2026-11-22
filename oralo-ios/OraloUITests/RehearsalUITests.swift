import XCTest

final class RehearsalUITests: XCTestCase {
    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "--ui-rehearsal-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        let card = app.buttons["script-Quarterly report"]
        XCTAssertTrue(card.waitForExistence(timeout: 15)); card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["pronunciation-count"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func option(_ app: XCUIApplication, _ id: String) {
        app.buttons["script-options"].tap()
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5)); app.buttons[id].tap()
    }
    @MainActor private func startManual(_ app: XCUIApplication) {
        option(app, "rehearse-script")
        XCTAssertTrue(app.buttons["readiness-start-manual"].waitForExistence(timeout: 5))
        capture(app, "01-readiness")
        app.buttons["readiness-start-manual"].tap()
        XCTAssertTrue(app.buttons["show-controls-waveform"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.alerts.firstMatch.exists, "Manual start never requests microphone or speech access.")
        app.buttons["show-controls-waveform"].tap()
    }
    @MainActor private func finish(_ app: XCUIApplication) {
        let exit = app.buttons["exit-presentation"]
        XCTAssertTrue(exit.exists)
        XCTAssertTrue(app.frame.contains(exit.frame), "The control remains fully visible.")
        // A scrolled UITextView exposes cue frames beneath the floating glass.
        // XCTest's automatic hit point can choose the transparent capsule corner;
        // use the visible control center, matching the verified physical touch.
        exit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["finish-session"].waitForExistence(timeout: 5)); app.buttons["finish-session"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["review-back-script"].waitForExistence(timeout: 8))
    }
    @MainActor private func firstReviewEvent(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'review-event-'")).firstMatch
    }
    @MainActor private func firstHistory(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rehearsal-record-'")).firstMatch
    }
    @MainActor func testRehearsalReviewEditReopenAndChangedRevision() {
        let app = launch(extra: ["--ui-appearance=light"])
        startManual(app)
        app.buttons["next-cue"].tap(); app.buttons["next-cue"].tap()
        XCTAssertEqual(app.staticTexts["presentation-position"].label, "3 / 12")
        capture(app, "02-rehearsal-with-pronunciations")
        app.buttons["start-stop"].tap()
        let paused = app.staticTexts["session-duration"].label
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        XCTAssertEqual(app.staticTexts["session-duration"].label, paused)
        app.buttons["start-stop"].tap()
        finish(app)
        XCTAssertEqual(app.staticTexts["review-manual-count"].label, "2")
        XCTAssertTrue(app.staticTexts["review-unfinished"].exists)
        capture(app, "03-real-review")
        XCTAssertTrue(firstReviewEvent(app).waitForExistence(timeout: 5)); firstReviewEvent(app).tap()
        XCTAssertTrue(app.buttons["edit-reviewed-passage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["review-script-changed"].exists)
        let historical = app.textViews["historical-passage-text"]
        XCTAssertTrue(historical.exists)
        historical.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Historical snapshots remain read-only after layout.")
        capture(app, "04-historical-passage")
        app.buttons["edit-reviewed-passage"].tap()
        let text = app.textViews["saved-script-editor"]
        XCTAssertTrue(app.staticTexts["review-edit-location"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        text.typeText("Updated quarterly figures.")
        option(app, "save-script")
        XCTAssertTrue(app.staticTexts["Saved on this device"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["pronunciation-count"].label.contains("3"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["script-Quarterly report"].waitForExistence(timeout: 10)); app.buttons["script-Quarterly report"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue((text.value as? String ?? "").contains("Updated quarterly figures."))
        XCTAssertTrue((text.value as? String ?? "").contains("roadmap"))
        option(app, "rehearsal-history")
        XCTAssertTrue(firstHistory(app).waitForExistence(timeout: 8)); firstHistory(app).tap()
        XCTAssertEqual(app.staticTexts["review-manual-count"].label, "2")
        firstReviewEvent(app).tap()
        XCTAssertTrue(app.staticTexts["review-script-changed"].waitForExistence(timeout: 5))
        capture(app, "05-history-keeps-original-revision")
        app.buttons["edit-reviewed-passage"].tap()
        XCTAssertTrue(app.staticTexts["review-edit-location"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["review-edit-location"].label.contains("changed"))
        XCTAssertTrue((text.value as? String ?? "").contains("Updated quarterly figures."))
    }
    @MainActor func testDeniedReadinessStillStartsManualAndEmptyReviewCanRehearseAgain() {
        let app = launch(extra: ["--ui-preflight=denied", "--ui-appearance=dark"])
        startManual(app)
        finish(app)
        XCTAssertEqual(app.staticTexts["review-manual-count"].label, "0")
        XCTAssertFalse(firstReviewEvent(app).exists)
        capture(app, "06-empty-manual-review-dark")
        app.buttons["rehearse-again"].tap()
        XCTAssertTrue(app.buttons["readiness-start-manual"].waitForExistence(timeout: 8))
        app.buttons["close-readiness"].tap()
        XCTAssertTrue(app.buttons["script-options"].waitForExistence(timeout: 5))
    }
    @MainActor func testBackgroundAndRelaunchKeepAnUnfinishedRecord() {
        let app = launch(extra: ["--ui-appearance=dark"])
        startManual(app); app.buttons["next-cue"].tap()
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Paused · Manual"].waitForExistence(timeout: 5))
        let paused = app.staticTexts["session-duration"].label
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        XCTAssertEqual(app.staticTexts["session-duration"].label, paused)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["script-Quarterly report"].waitForExistence(timeout: 10)); app.buttons["script-Quarterly report"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        option(app, "rehearsal-history")
        XCTAssertTrue(firstHistory(app).waitForExistence(timeout: 8)); firstHistory(app).tap()
        XCTAssertTrue(app.staticTexts["review-unfinished"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["review-manual-count"].label, "1")
    }
    @MainActor func testRecoveryCompletesAnnotatedScriptAtLargeType() {
        let app = launch(extra: ["--ui-appearance=dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        startManual(app)
        app.buttons["recovery"].tap()
        let last = app.buttons["recover-11"]
        for _ in 0..<10 { if last.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(last.exists); last.tap()
        XCTAssertEqual(app.staticTexts["presentation-position"].label, "12 / 12")
        finish(app)
        XCTAssertEqual(app.staticTexts["review-manual-count"].label, "1")
        XCTAssertFalse(app.staticTexts["review-unfinished"].exists)
        capture(app, "07-completed-review-accessibility")
    }
    @MainActor func testVoiceReplayRecordsOneHoldWithoutChangingRecovery() {
        let app = launch(extra: ["--ui-session-speech-replay"])
        option(app, "rehearse-script")
        XCTAssertTrue(app.buttons["readiness-check-start"].waitForExistence(timeout: 5)); app.buttons["readiness-check-start"].tap()
        XCTAssertTrue(app.buttons["show-controls-waveform"].waitForExistence(timeout: 8)); app.buttons["show-controls-waveform"].tap()
        let position = app.staticTexts["presentation-position"]
        expectation(for: NSPredicate(format: "label == %@", "3 / 12"), evaluatedWith: position)
        waitForExpectations(timeout: 15)
        finish(app)
        XCTAssertEqual(app.staticTexts["review-manual-count"].label, "0")
        XCTAssertEqual(app.staticTexts["review-hold-count"].label, "1")
        XCTAssertTrue(firstReviewEvent(app).exists)
        capture(app, "08-real-matcher-replayed-hold")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
