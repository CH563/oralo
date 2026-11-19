import XCTest

final class PrototypeUITests: XCTestCase {
    @MainActor
    func testPresentationHidesControlsAndFirstTapOnlyReveals() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-prototype"]
        app.launch()
        XCTAssertTrue(app.buttons["enter-presentation"].waitForExistence(timeout: 10))
        app.buttons["enter-presentation"].tap()
        XCTAssertFalse(app.buttons["start-stop"].exists)
        XCTAssertFalse(app.buttons["setup"].exists)
        XCTAssertTrue(app.buttons["show-controls-waveform"].exists)
        XCTAssertEqual(app.buttons["show-controls-waveform"].value as? String, "Microphone paused")
        // Tap on a sentence while controls are hidden: it must not select that sentence.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)).tap()
        XCTAssertTrue(app.buttons["hide-controls"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["presentation-position"].label, "1 / 12")
        XCTAssertTrue(app.buttons["start-stop"].exists)
        app.buttons["cue-1"].tap()
        XCTAssertEqual(app.staticTexts["presentation-position"].label, "2 / 12")
        app.buttons["hide-controls"].tap()
        XCTAssertFalse(app.buttons["start-stop"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["cue-1"].frame.minY,
                                    app.buttons["show-controls-waveform"].frame.maxY)
        XCTAssertLessThan(app.descendants(matching: .any)["script-scroll"].firstMatch.frame.minY,
                          app.buttons["show-controls-waveform"].frame.maxY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Immersive presentation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // The blank edge is also a reveal target.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.015, dy: 0.4)).tap()
        XCTAssertTrue(app.buttons["exit-presentation"].waitForExistence(timeout: 5))
        app.buttons["exit-presentation"].tap()
        XCTAssertTrue(app.buttons["setup"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cue-position"].label, "2 / 12")
    }

    @MainActor
    func testReadingLineStaysInUpperThirdAcrossWrapsAndJumpToLastCue() throws {
        try verifyReadingAnchor(largeType: false)
    }

    @MainActor
    func testReadingAnchorWithAccessibilityTextSize() throws {
        try verifyReadingAnchor(largeType: true)
    }

    @MainActor
    func testAnnotatedReplayPreservesCharacterProgressWrapAndRejoin() throws {
        try verifyReadingAnchor(largeType: false, annotated: true)
    }

    @MainActor
    private func verifyReadingAnchor(largeType: Bool, annotated: Bool = false) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reading-replay"]
        if annotated { app.launchArguments.append("--ui-pronunciation-replay") }
        if largeType {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["enter-presentation"].waitForExistence(timeout: 10))
        app.buttons["enter-presentation"].tap()
        let line = app.staticTexts["reading-line"]
        let viewport = app.descendants(matching: .any)["script-scroll"].firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        if annotated {
            XCTAssertTrue((app.buttons["cue-0"].value as? String ?? "").contains("tuán duì"), "Replay must include real annotations on the active cue IDs.")
        }
        func assertAnchor(_ value: String) {
            let predicate = NSPredicate(format: "value == %@", value)
            expectation(for: predicate, evaluatedWith: line)
            waitForExpectations(timeout: 12)
            // Allow the 120 ms line transition to complete before measuring its settled position.
            let settled = NSPredicate { _, _ in
                abs(line.frame.midY - (viewport.frame.minY + viewport.frame.height * 0.34)) < 6
            }
            expectation(for: settled, evaluatedWith: line)
            waitForExpectations(timeout: 3)
        }
        assertAnchor("cue:0 characters:0")
        assertAnchor("cue:0 characters:6")
        assertAnchor("cue:0 characters:36")
        if largeType { XCTAssertGreaterThan(line.frame.height, 70, "The test must actually use enlarged text.") }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Actual wrapped reading line at upper third"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // Skip the remaining first-cue update, then check the last cue and a backward rejoin.
        assertAnchor("cue:2 characters:14")
        assertAnchor("cue:0 characters:12")
        XCTAssertFalse(app.buttons["start-stop"].exists)
    }

    @MainActor
    func testManualRecoveryAndRedactedReportWithoutMicrophone() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-prototype"]
        app.launch()
        XCTAssertTrue(app.buttons["start-stop"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["cue-position"].label, "1 / 12")
        app.buttons["cue-1"].tap()
        XCTAssertEqual(app.staticTexts["cue-position"].label, "2 / 12")
        app.buttons["recovery"].tap()
        XCTAssertTrue(app.buttons["recover-0"].waitForExistence(timeout: 5))
        app.buttons["recover-0"].tap()
        XCTAssertEqual(app.staticTexts["cue-position"].label, "1 / 12")
        XCTAssertTrue(app.buttons["start-stop"].label.contains("Start / Resume"))
        app.buttons["diagnostics"].tap()
        let report = app.staticTexts["diagnostic-report"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertTrue(report.label.contains("Manual selections: 2"))
        XCTAssertTrue(report.label.contains("Recognition requests: 0"))
        XCTAssertFalse(report.label.contains("大家好"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Manual recovery diagnostic report"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testScriptSetupAppliesSampleAndResetsPosition() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-prototype"]
        app.launch()
        XCTAssertTrue(app.buttons["cue-1"].waitForExistence(timeout: 10))
        app.buttons["cue-1"].tap()
        app.buttons["setup"].tap()
        XCTAssertTrue(app.textViews["script-editor"].waitForExistence(timeout: 5))
        app.buttons["Load sample for selected language"].tap()
        app.buttons["Apply"].tap()
        XCTAssertTrue(app.buttons["start-stop"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cue-position"].label, "1 / 12")
    }
}
