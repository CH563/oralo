import XCTest

final class SettingsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "--ui-rehearsal-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        if extra.contains("--ui-welcome") { tap(app, "welcome-continue") }
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.buttons[id].firstMatch
        for _ in 0..<16 {
            if element.exists && element.isHittable && app.frame.insetBy(dx: 0, dy: 24).contains(element.frame) { break }
            if element.exists && element.frame.maxY < app.frame.height * 0.2 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    @MainActor private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.allElementsBoundByIndex.first { $0.isHittable && $0.identifier != "settings" }
        XCTAssertNotNil(button)
        button?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    @MainActor private func number(_ app: XCUIApplication, _ id: String) -> Int? {
        // LabeledContent exposes its title and value as one VoiceOver element.
        let value = app.staticTexts[id].firstMatch
        for _ in 0..<12 { if value.exists { break }; app.swipeDown() }
        return value.label.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).last
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func manualSession(_ app: XCUIApplication, rehearsal: Bool) {
        tap(app, "script-options"); tap(app, rehearsal ? "rehearse-script" : "start-manual")
        XCTAssertTrue(app.buttons["readiness-start-manual"].waitForExistence(timeout: 5)); tap(app, "readiness-start-manual")
        XCTAssertTrue(app.buttons["show-controls-waveform"].waitForExistence(timeout: 8)); tap(app, "show-controls-waveform")
        tap(app, "next-cue"); tap(app, "exit-presentation"); tap(app, "finish-session")
        XCTAssertTrue(app.buttons["review-back-script"].waitForExistence(timeout: 8)); tap(app, "review-back-script")
    }
    @MainActor func testPreferencesPersistAndManualDefaultKeepsAnnotations() {
        let app = launch(extra: ["--ui-appearance=light"])
        tap(app, "settings")
        let slider = app.sliders["reading-size"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5)); slider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(number(app, "reading-size-value"), 48)
        tap(app, "reading-appearance"); tap(app, "Dark")
        let toggle = app.switches["default-follow"]
        for _ in 0..<5 { if toggle.isHittable { break }; app.swipeUp() }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let disabled = NSPredicate(format: "value == %@", "0")
        expectation(for: disabled, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        tap(app, "default-language"); tap(app, "English (US)")
        capture(app, "01-settings-preferences")
        tap(app, "close-settings")
        app.terminate(); app.launch()
        tap(app, "settings")
        XCTAssertEqual(number(app, "reading-size-value"), 48)
        for _ in 0..<5 { if toggle.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(toggle.value as? String, "0")
        capture(app, "02-preferences-after-relaunch")
        tap(app, "close-settings"); tap(app, "script-Quarterly report")
        XCTAssertTrue(app.buttons["pronunciation-count"].label.contains("3"))
        tap(app, "start-voice")
        XCTAssertTrue(app.buttons["readiness-start-manual"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["readiness-check-start"].exists, "Manual default must not request microphone permission.")
        tap(app, "readiness-start-manual"); tap(app, "show-controls-waveform")
        XCTAssertEqual(app.staticTexts["presentation-position"].label, "1 / 12")
        tap(app, "next-cue"); tap(app, "next-cue")
        capture(app, "03-reading-with-saved-size-and-dark-appearance")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    @MainActor func testClearRehearsalsPreservesPresentationAndScriptAfterRelaunch() {
        let app = launch()
        tap(app, "script-Quarterly report")
        manualSession(app, rehearsal: true); manualSession(app, rehearsal: false)
        tap(app, "back-to-library"); tap(app, "settings"); tap(app, "data-settings")
        XCTAssertEqual(number(app, "data-rehearsal-count"), 1)
        XCTAssertEqual(number(app, "data-presentation-count"), 1)
        tap(app, "clear-rehearsals"); capture(app, "04-clear-rehearsals-confirmation")
        tap(app, "cancel-data-removal")
        XCTAssertEqual(number(app, "data-rehearsal-count"), 1)
        tap(app, "clear-rehearsals"); tap(app, "confirm-data-removal")
        XCTAssertTrue(app.staticTexts["data-cleared"].waitForExistence(timeout: 8))
        app.terminate(); app.launch(); tap(app, "settings"); tap(app, "data-settings")
        XCTAssertEqual(number(app, "data-rehearsal-count"), 0)
        XCTAssertEqual(number(app, "data-presentation-count"), 1)
        XCTAssertEqual(number(app, "data-script-count"), 1)
        XCTAssertEqual(number(app, "data-pronunciation-count"), 3)
        capture(app, "05-records-after-clear-and-relaunch")
    }
    @MainActor func testClearAllCancelThenDeleteResetsPreferencesWithoutReseeding() {
        let app = launch(extra: ["--ui-welcome"])
        tap(app, "settings"); app.sliders["reading-size"].adjust(toNormalizedSliderPosition: 1)
        tap(app, "data-settings"); tap(app, "clear-all-data"); tap(app, "cancel-data-removal")
        XCTAssertEqual(number(app, "data-script-count"), 1)
        tap(app, "clear-all-data"); capture(app, "06-clear-all-confirmation"); tap(app, "confirm-data-removal")
        XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); tap(app, "welcome-continue"); tap(app, "settings")
        XCTAssertEqual(number(app, "reading-size-value"), 32)
        tap(app, "data-settings")
        for id in ["data-script-count", "data-pronunciation-count", "data-rehearsal-count", "data-presentation-count"] {
            XCTAssertEqual(number(app, id), 0, id)
        }
        capture(app, "07-empty-data-after-relaunch")
    }
    @MainActor func testLanguageDefaultOnlyAppliesToNewScripts() {
        let app = launch()
        tap(app, "settings"); tap(app, "default-language"); tap(app, "English (US)"); tap(app, "close-settings")
        tap(app, "script-Quarterly report"); tap(app, "start-voice")
        XCTAssertTrue(app.staticTexts["readiness-status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["readiness-status"].label.contains("Mandarin"))
        tap(app, "close-readiness"); tap(app, "back-to-library")
        tap(app, "new-script-menu"); tap(app, "new-script")
        let editor = app.textViews["saved-script-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8)); editor.tap(); editor.typeText("Go at your own pace.")
        tap(app, "script-options"); tap(app, "save-script"); tap(app, "start-voice")
        XCTAssertTrue(app.staticTexts["readiness-status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["readiness-status"].label.contains("English"))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    @MainActor func testChineseLargeTypePrivacyLicensesAndAccessibleSettings() throws {
        let app = launch(extra: ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "--ui-appearance=dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tap(app, "settings")
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        capture(app, "08-chinese-dark-large-type-settings")
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .trait, .textClipped])
        tap(app, "privacy-settings")
        XCTAssertTrue(app.navigationBars["隐私与开源说明"].waitForExistence(timeout: 5))
        capture(app, "09-privacy-dark-large-type")
        for _ in 0..<16 {
            if app.buttons["mit-license"].exists && app.buttons["mit-license"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.descendants(matching: .any)["open-source-link"].firstMatch.exists)
        capture(app, "11-public-source-and-bundled-licenses")
        tap(app, "mit-license")
        XCTAssertTrue(app.navigationBars["MIT 许可证"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Permission is hereby granted")).firstMatch.exists)
        capture(app, "10-bundled-mit-license")
        back(app); back(app)
        tap(app, "data-settings"); tap(app, "clear-all-data")
        XCTAssertTrue(app.buttons["cancel-data-removal"].firstMatch.waitForExistence(timeout: 5)); tap(app, "cancel-data-removal")
        XCTAssertEqual(number(app, "data-script-count"), 1)
    }
}
