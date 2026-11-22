import XCTest
import UIKit

final class AdaptiveUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor private func launch(extra: [String] = [], landscape: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "--ui-rehearsal-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        let script = app.buttons["script-Quarterly report"]
        XCTAssertTrue(script.waitForExistence(timeout: 15)); tap(script)
        XCTAssertTrue(app.buttons["pronunciation-count"].waitForExistence(timeout: 8))
        return app
    }
    @MainActor private func tap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    @MainActor private func option(_ app: XCUIApplication, _ id: String) {
        tap(app.buttons["script-options"])
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5)); tap(app.buttons[id])
    }
    @MainActor private func manual(_ app: XCUIApplication) {
        option(app, "rehearse-script")
        XCTAssertTrue(app.buttons["readiness-start-manual"].waitForExistence(timeout: 5)); tap(app.buttons["readiness-start-manual"])
        let waveform = app.buttons["show-controls-waveform"]
        XCTAssertTrue(waveform.waitForExistence(timeout: 8))
        if UIDevice.current.userInterfaceIdiom == .pad { XCTAssertGreaterThanOrEqual(waveform.frame.minY, 28) }
        tap(waveform)
        XCTAssertTrue(app.buttons["next-cue"].waitForExistence(timeout: 5))
    }
    @MainActor private func rotate(_ orientation: UIDeviceOrientation, app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation.isLandscape
        expectation(for: NSPredicate { _, _ in (app.frame.width > app.frame.height) == landscape }, evaluatedWith: app)
        waitForExpectations(timeout: 8)
    }
    @MainActor private func anchor(_ app: XCUIApplication) {
        let line = app.staticTexts["reading-line"], viewport = app.descendants(matching: .any)["script-scroll"].firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        expectation(for: NSPredicate { _, _ in
            let fraction = (line.frame.midY - viewport.frame.minY) / viewport.frame.height
            return (0.28...0.56).contains(fraction)
        }, evaluatedWith: line)
        waitForExpectations(timeout: 5)
    }
    @MainActor private func finish(_ app: XCUIApplication) {
        tap(app.buttons["exit-presentation"])
        XCTAssertTrue(app.buttons["finish-session"].waitForExistence(timeout: 5)); tap(app.buttons["finish-session"])
        XCTAssertTrue(app.buttons["review-back-script"].waitForExistence(timeout: 8))
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testRotationKeepsAnnotatedCuePauseAndRecovery() {
        let app = launch(extra: ["--ui-appearance=dark"])
        manual(app)
        tap(app.buttons["next-cue"]); tap(app.buttons["next-cue"])
        tap(app.buttons["start-stop"])
        let duration = app.staticTexts["session-duration"].label
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            rotate(orientation, app: app)
            XCTAssertEqual(app.staticTexts["presentation-position"].label, "3 / 12")
            XCTAssertEqual(app.staticTexts["session-duration"].label, duration)
            XCTAssertTrue(app.staticTexts["Paused · Manual"].exists)
            XCTAssertTrue((app.buttons["cue-2"].value as? String ?? "").contains("hāng"))
            anchor(app)
            for id in ["previous-cue", "start-stop", "next-cue", "recovery", "exit-presentation"] {
                XCTAssertTrue(app.frame.contains(app.buttons[id].frame), "\(id) stays inside the viewport")
            }
            capture(app, "build12-rotation-\(orientation.rawValue)")
        }
        rotate(.landscapeLeft, app: app)
        tap(app.buttons["start-stop"])
        tap(app.buttons["recovery"])
        XCTAssertTrue(app.buttons["recover-0"].waitForExistence(timeout: 5)); tap(app.buttons["recover-0"])
        XCTAssertTrue(app.staticTexts["Paused · Manual"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["presentation-position"].label, "1 / 12")
        tap(app.buttons["hide-controls"])
        XCTAssertFalse(app.buttons["next-cue"].exists)
        XCTAssertLessThan(app.buttons["show-controls-waveform"].frame.width, 180)
        anchor(app)
        capture(app, "build12-immersive-landscape")
        app.terminate(); XCUIDevice.shared.orientation = .portrait
    }

    @MainActor func testReviewObservationsOriginalAndVoiceRotation() {
        let app = launch(extra: ["--ui-appearance=light", "--ui-session-speech-replay", "--ui-review-observations"])
        option(app, "rehearse-script")
        XCTAssertTrue(app.buttons["readiness-check-start"].waitForExistence(timeout: 5)); tap(app.buttons["readiness-check-start"])
        XCTAssertTrue(app.buttons["show-controls-waveform"].waitForExistence(timeout: 8))
        rotate(.landscapeLeft, app: app)
        tap(app.buttons["show-controls-waveform"])
        expectation(for: NSPredicate(format: "label == %@", "3 / 12"), evaluatedWith: app.staticTexts["presentation-position"])
        waitForExpectations(timeout: 15)
        anchor(app)
        XCTAssertTrue(app.buttons["start-stop"].label.contains("Pause"))
        finish(app)
        rotate(.portrait, app: app)
        let quiet = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'review-event-' AND label CONTAINS 'Quiet for about'")).firstMatch
        XCTAssertTrue(quiet.waitForExistence(timeout: 8))
        let repeatEvent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'review-event-' AND label CONTAINS 'Repeated this passage'")).firstMatch
        XCTAssertTrue(repeatEvent.exists)
        capture(app, "build12-review-observations")
        tap(quiet)
        let compare = app.buttons["compare-original"]
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        if !compare.isHittable { app.swipeUp() }
        capture(app, "build12-review-context")
        tap(compare)
        let original = app.textViews["original-draft-text"]
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["original-unmapped"].exists)
        tap(original); XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture(app, "build12-original-draft")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["script-Quarterly report"].waitForExistence(timeout: 10)); tap(app.buttons["script-Quarterly report"])
        option(app, "rehearsal-history")
        let history = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rehearsal-record-'")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5)); tap(history)
        XCTAssertTrue(quiet.waitForExistence(timeout: 5)); XCTAssertTrue(repeatEvent.exists)
    }

    @MainActor func testIPadWorkspaceSwitchSaveAndSplitReview() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad workspace test") }
        let app = launch(extra: ["--ui-appearance=light", "--ui-import-fixture"], landscape: true)
        XCTAssertTrue(app.buttons["new-script-menu"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "new-script-menu").count, 1)
        capture(app, "build12-ipad-workspace")
        let title = app.textFields["script-title"]; tap(title); title.typeText(" updated")
        tap(app.buttons["new-script-menu"])
        XCTAssertTrue(app.buttons["import-script"].waitForExistence(timeout: 5)); tap(app.buttons["import-script"])
        XCTAssertTrue(app.buttons["script-Quarterly report updated"].waitForExistence(timeout: 8))
        tap(app.buttons["script-Quarterly report updated"])
        XCTAssertTrue(app.buttons["pronunciation-count"].waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Quarterly report updated")
        manual(app)
        XCTAssertFalse(app.buttons["new-script-menu"].isHittable, "The sidebar is covered while speaking")
        XCTAssertGreaterThan(app.descendants(matching: .any)["script-scroll"].firstMatch.frame.width, app.frame.width * 0.7)
        tap(app.buttons["next-cue"]); tap(app.buttons["next-cue"])
        anchor(app); capture(app, "build12-ipad-speaking")
        finish(app)
        XCTAssertTrue(app.buttons["edit-reviewed-passage"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.buttons["edit-reviewed-passage"].frame.minX, app.buttons["review-back-script"].frame.maxX)
        capture(app, "build12-ipad-review")
        tap(app.buttons["edit-reviewed-passage"])
        XCTAssertTrue(app.staticTexts["review-edit-location"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-script-menu"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.terminate(); XCUIDevice.shared.orientation = .portrait
    }

    @MainActor func testIPadDarkRotationPreservesDraftAndReviewSelection() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad rotation test") }
        let app = launch(extra: ["--ui-appearance=dark"], landscape: true)
        let title = app.textFields["script-title"]
        tap(title); title.typeText(" rotated")
        rotate(.portrait, app: app)
        XCTAssertEqual(title.value as? String, "Quarterly report rotated")
        XCTAssertTrue(app.buttons["pronunciation-count"].exists)
        capture(app, "build12-ipad-dark-portrait-editor")
        rotate(.landscapeLeft, app: app)
        XCTAssertEqual(title.value as? String, "Quarterly report rotated")
        manual(app)
        tap(app.buttons["next-cue"]); tap(app.buttons["next-cue"])
        capture(app, "build12-ipad-dark-speaking")
        finish(app)
        XCTAssertTrue(app.buttons["edit-reviewed-passage"].waitForExistence(timeout: 5))
        capture(app, "build12-ipad-dark-split-review")
        rotate(.portrait, app: app)
        XCTAssertFalse(app.buttons["edit-reviewed-passage"].exists)
        let event = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'review-event-'")).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5)); tap(event)
        XCTAssertTrue(app.buttons["compare-original"].waitForExistence(timeout: 5))
        capture(app, "build12-ipad-dark-portrait-passage")
        app.terminate(); XCUIDevice.shared.orientation = .portrait
    }
}
