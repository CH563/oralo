import XCTest

final class ReadingToolsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor private func launch(language: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"] + extra
        app.launch(); XCTAssertTrue(app.buttons["new-script-menu"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func tap(_ app: XCUIApplication, _ id: String) {
        let button = app.buttons[id].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8), id)
        if ["ignore-pronunciation-review", "keep-pronunciation-review", "undo-pronunciation-review", "pronunciation-review-rehearse"].contains(id) {
            for _ in 0..<5 {
                if button.isHittable && app.frame.contains(button.frame) { break }
                app.swipeUp()
            }
        }
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    @MainActor private func option(_ app: XCUIApplication, _ id: String) { tap(app, "script-options"); tap(app, id) }
    @MainActor private func capture(_ app: XCUIApplication, _ title: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = title; item.lifetime = .keepAlways; add(item)
    }
    @MainActor func testEnglishSampleMetricsEstimateAndReopen() {
        let app = launch(extra: ["--ui-appearance=light"])
        tap(app, "sample-script")
        XCTAssertTrue(app.textViews["saved-script-editor"].waitForExistence(timeout: 8))
        XCTAssertTrue((app.textViews["saved-script-editor"].value as? String ?? "").hasPrefix("Today I will"))
        XCTAssertTrue(app.buttons["edit-speaking-estimate"].label.contains("134 words"))
        capture(app, "01-English-script-count-and-estimate")
        tap(app, "edit-speaking-estimate")
        let slider = app.sliders["estimate-english-pace"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5)); slider.adjust(toNormalizedSliderPosition: 1)
        let selectedPace = slider.value as? String
        XCTAssertNotEqual(selectedPace, "140")
        capture(app, "02-estimate-settings")
        tap(app, "Done"); tap(app, "start-voice")
        XCTAssertTrue(app.staticTexts["readiness-status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["readiness-status"].label.contains("English"))
        tap(app, "close-readiness"); tap(app, "back-to-library")
        XCTAssertTrue(app.buttons["script-Quarterly report"].waitForExistence(timeout: 8))
        capture(app, "03-library-count-and-estimate")
        app.terminate(); app.launch(); tap(app, "script-Quarterly report")
        XCTAssertTrue(app.buttons["edit-speaking-estimate"].label.contains("134 words"))
        tap(app, "edit-speaking-estimate")
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertEqual(slider.value as? String, selectedPace)
    }
    @MainActor func testSimplifiedSampleUsesAppLanguage() { checkSample(language: "zh-Hans", title: "团队季度汇报", excerpt: "本季度收入增长", count: "210", screenshot: "04-Hans-sample") }
    @MainActor func testTraditionalSampleUsesAppLanguage() { checkSample(language: "zh-Hant", title: "團隊季度匯報", excerpt: "本季營收成長", count: "208", screenshot: "05-Hant-sample") }
    @MainActor private func checkSample(language: String, title: String, excerpt: String, count: String, screenshot: String) {
        let app = launch(language: language, extra: ["--ui-appearance=dark"])
        tap(app, "sample-script")
        let text = app.textViews["saved-script-editor"]
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        XCTAssertTrue((text.value as? String ?? "").contains(excerpt))
        XCTAssertEqual(app.textFields["script-title"].value as? String, title)
        XCTAssertTrue(app.buttons["edit-speaking-estimate"].label.contains(count))
        capture(app, screenshot)
    }
    @MainActor func testMirrorKeepsPausedPositionAcrossRotationAndRecovery() {
        let app = launch(extra: ["--ui-rehearsal-fixture", "--ui-appearance=dark"])
        tap(app, "script-Quarterly report"); option(app, "start-manual"); tap(app, "readiness-start-manual")
        tap(app, "show-controls-waveform"); tap(app, "next-cue"); tap(app, "next-cue"); tap(app, "start-stop")
        let position = app.staticTexts["presentation-position"]
        XCTAssertEqual(position.label, "3 / 12")
        tap(app, "presentation-options")
        let toggle = app.switches["mirror-text"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        capture(app, "06-mirror-options")
        tap(app, "close-presentation-options")
        XCTAssertEqual(position.label, "3 / 12"); XCTAssertTrue(app.staticTexts["Paused · Manual"].exists)
        capture(app, "07-mirrored-pinyin-IPA")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.buttons["presentation-options"].waitForExistence(timeout: 5))
        XCTAssertEqual(position.label, "3 / 12")
        capture(app, "08-landscape-mirror")
        tap(app, "recovery"); tap(app, "recover-1")
        XCTAssertEqual(position.label, "2 / 12"); XCTAssertTrue(app.staticTexts["Paused · Manual"].exists)
        tap(app, "presentation-options"); toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); tap(app, "close-presentation-options")
        XCTAssertEqual(position.label, "2 / 12")
    }
    @MainActor func testCustomLayoutRemainsEditableAndSurvivesRelaunch() {
        let app = launch()
        tap(app, "sample-script"); option(app, "toggle-sentences")
        tap(app, "pause-mark-0"); tap(app, "merge-0")
        let count = app.staticTexts["sentence-count"].label
        option(app, "toggle-sentences")
        let text = app.textViews["saved-script-editor"]
        text.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 100, dy: 27)).tap()
        text.typeText("Updated ")
        option(app, "save-script"); option(app, "toggle-sentences")
        XCTAssertEqual(app.staticTexts["sentence-count"].label, count)
        capture(app, "09-manual-layout-after-text-edit")
        tap(app, "back-to-library"); app.terminate(); app.launch(); tap(app, "script-Quarterly report")
        XCTAssertTrue((text.value as? String ?? "").contains("Updated"))
        option(app, "toggle-sentences"); XCTAssertEqual(app.staticTexts["sentence-count"].label, count)
    }
    @MainActor func testPronunciationReviewSaveIgnoreUndoReopenAndRehearse() {
        let app = launch(extra: ["--ui-rehearsal-fixture"])
        tap(app, "script-Quarterly report"); option(app, "rehearse-script"); tap(app, "readiness-start-manual")
        tap(app, "show-controls-waveform"); tap(app, "next-cue"); tap(app, "next-cue")
        tap(app, "exit-presentation"); tap(app, "finish-session")
        tap(app, "review-pronunciation-passages")
        let passage = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'check-passage-' AND label CONTAINS 'roadmap' ")).firstMatch
        XCTAssertTrue(passage.waitForExistence(timeout: 5)); passage.tap()
        let search = app.textFields["review-word-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("roadmap")
        tap(app, "review-word-match-0")
        XCTAssertTrue(app.buttons["pronunciation-save"].waitForExistence(timeout: 5))
        capture(app, "10-review-existing-IPA")
        // Save the existing hint: the review must not duplicate it or consume an unrelated undo.
        tap(app, "pronunciation-save")
        XCTAssertTrue(app.staticTexts["pronunciation-review-status"].waitForExistence(timeout: 8))
        capture(app, "11-reading-hint-saved-from-review")
        tap(app, "ignore-pronunciation-review")
        XCTAssertEqual(app.staticTexts["pronunciation-review-status"].label, "Ignored for this record")
        tap(app, "undo-pronunciation-review")
        XCTAssertTrue(app.staticTexts["pronunciation-review-status"].label.contains("saved"))
        tap(app, "close-pronunciation-review")
        XCTAssertTrue(app.buttons["pronunciation-count"].label.contains("3"))
        app.terminate(); app.launch(); tap(app, "script-Quarterly report"); option(app, "rehearsal-history")
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rehearsal-record-' ")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 8)); record.tap(); tap(app, "review-pronunciation-passages"); passage.tap()
        XCTAssertTrue(app.staticTexts["pronunciation-review-status"].waitForExistence(timeout: 8))
        tap(app, "pronunciation-review-rehearse")
        XCTAssertTrue(app.buttons["readiness-start-manual"].waitForExistence(timeout: 8))
    }
    @MainActor func testReviewAddsNewReadingWithoutAutomaticFindings() {
        let app = launch(extra: ["--ui-pronunciation-fixture", "--ui-appearance=light"])
        tap(app, "script-Reading rehearsal"); option(app, "rehearse-script"); tap(app, "readiness-start-manual")
        tap(app, "show-controls-waveform"); tap(app, "exit-presentation"); tap(app, "finish-session")
        tap(app, "review-pronunciation-passages")
        let passage = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'check-passage-' AND label == 'roadmap'")).firstMatch
        XCTAssertTrue(passage.waitForExistence(timeout: 5)); passage.tap()
        let search = app.textFields["review-word-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("roadmap")
        tap(app, "review-word-match-0"); tap(app, "pronunciation-save")
        XCTAssertTrue(app.staticTexts["pronunciation-review-status"].waitForExistence(timeout: 8))
        capture(app, "12-new-reading-from-manual-review")
        tap(app, "close-pronunciation-review")
        XCTAssertTrue(app.buttons["pronunciation-count"].label.contains("1"))
        app.terminate(); app.launch(); tap(app, "script-Reading rehearsal")
        XCTAssertTrue(app.buttons["pronunciation-count"].label.contains("1"))
        option(app, "start-manual"); tap(app, "readiness-start-manual")
        tap(app, "show-controls-waveform")
        XCTAssertTrue((app.buttons["cue-0"].value as? String ?? "").contains("oʊ"))
    }

}
