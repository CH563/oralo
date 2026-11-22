import XCTest
import UIKit
import Vision

final class FloatingPromptUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor private func launch(dark: Bool = false, extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "--ui-rehearsal-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-appearance=\(dark ? "dark" : "light")"] + extra
        app.launch()
        if extra.contains("--ui-welcome") { tap(app, "welcome-continue") }
        tap(app, "script-Quarterly report"); return app
    }
    @MainActor private func tap(_ app: XCUIApplication, _ id: String) {
        let button = app.buttons[id].firstMatch
        if ["data-settings", "clear-all-data"].contains(id) {
            for _ in 0..<10 {
                if button.exists && button.isHittable && app.frame.insetBy(dx: 0, dy: 24).contains(button.frame) { break }
                app.swipeUp()
            }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 15), id)
        if id.hasPrefix("floating-") && id != "floating-done" && !id.hasPrefix("floating-passage-") || id == "clear-all-data" {
            for _ in 0..<4 {
                if button.isHittable && app.frame.insetBy(dx: 0, dy: 12).contains(button.frame) { break }
                if button.exists && button.frame.maxY < app.frame.height * 0.2 { app.swipeDown() } else { app.swipeUp() }
            }
        }
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    @MainActor private func open(_ app: XCUIApplication) {
        tap(app, "script-options"); tap(app, "open-floating-prompt")
        XCTAssertTrue(app.otherElements["floating-preview"].waitForExistence(timeout: 8))
    }
    @MainActor private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testFixedPaceSurvivesAudioNotifications() {
        let app = launch(extra: ["--ui-floating-interruptions"]); open(app)
        let preview = app.otherElements["floating-preview"]
        let opening = preview.value as? String
        tap(app, "floating-preview-play")
        tap(app, "floating-test-interruption")
        XCTAssertTrue(app.buttons["floating-preview-play"].label.contains("Pause preview"), "Audio interruptions must not pause silent fixed-pace text")
        expectation(for: NSPredicate { _, _ in preview.value as? String != opening }, evaluatedWith: preview)
        waitForExpectations(timeout: 12)
        capture("fixed-pace-continues-after-audio-interruption")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["floating-preview-play"].label.contains("Preview scrolling"), "Preview without active PiP must still pause on background")
    }

    @MainActor func testVoiceReplayUsesExistingRecoveryAndHoldsWhenAudioStops() {
        let app = launch(extra: ["--ui-session-speech-replay"]); open(app)
        app.segmentedControls["floating-mode"].buttons["Voice follow"].tap()
        tap(app, "floating-preview-play")
        let preview = app.otherElements["floating-preview"]
        expectation(for: NSPredicate { _, _ in
            let text = preview.value as? String ?? ""
            // The shared cursor may preview the next cue after a completed
            // recognized sentence; both are original manuscript passages.
            return text.contains("roadmap") || text.contains("milestone")
        }, evaluatedWith: preview)
        waitForExpectations(timeout: 12)
        // This fixture delivers recognition/level events only; it never opens a
        // microphone. After its final event, the real missing-input guard fires.
        let status = app.staticTexts["floating-status"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "interrupted"), evaluatedWith: status)
        waitForExpectations(timeout: 8)
        let held = preview.value as? String
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "No audio must not scroll text")], timeout: 1)
        XCTAssertEqual(preview.value as? String, held)
        capture("floating-voice-recovery-then-input-interruption")
        tap(app, "floating-done")
        open(app)
        XCTAssertEqual(preview.value as? String, held)
        XCTAssertTrue(app.buttons["floating-preview-play"].label.contains("Try voice"))
    }

    @MainActor func testPreviewAnnotationsPauseBackgroundAndReopen() {
        let app = launch(); open(app)
        tap(app, "floating-choose-passage"); tap(app, "floating-passage-2")
        let preview = app.otherElements["floating-preview"]
        XCTAssertTrue((preview.value as? String ?? "").contains("roadmap"))
        capture("floating-preview-pinyin-IPA-light")
        tap(app, "floating-preview-play")
        XCTAssertTrue(app.buttons["floating-preview-play"].label.contains("Pause"))
        tap(app, "floating-preview-play")
        let passage = preview.value as? String
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(preview.value as? String, passage)
        XCTAssertTrue(app.buttons["floating-preview-play"].label.contains("Preview"))
        let speed = app.sliders["floating-speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 5)); speed.adjust(toNormalizedSliderPosition: 0.7)
        let savedSpeed = speed.value as? String
        tap(app, "floating-done"); app.terminate(); app.launch(); tap(app, "script-Quarterly report"); open(app)
        XCTAssertEqual(preview.value as? String, passage)
        XCTAssertEqual(speed.value as? String, savedSpeed)
        XCTAssertTrue(app.buttons["floating-preview-play"].label.contains("Preview"))
        // The full-screen reader remains a separate, explicit start.
        tap(app, "floating-done"); tap(app, "script-options"); tap(app, "start-manual"); tap(app, "readiness-start-manual")
        tap(app, "show-controls-waveform"); tap(app, "next-cue")
        XCTAssertTrue(app.staticTexts["presentation-position"].label.hasPrefix("2 /"))
    }

    @MainActor func testClearDataRemovesFloatingPositionAndPreferences() {
        let app = launch(extra: ["--ui-welcome"]); open(app)
        let defaultSpeed = app.sliders["floating-speed"].value as? String
        tap(app, "floating-choose-passage"); tap(app, "floating-passage-2")
        app.sliders["floating-speed"].adjust(toNormalizedSliderPosition: 1)
        tap(app, "floating-done")
        if app.buttons["back-to-library"].exists { tap(app, "back-to-library") }
        tap(app, "settings"); tap(app, "data-settings"); tap(app, "clear-all-data"); tap(app, "confirm-data-removal")
        XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); tap(app, "welcome-continue")
        XCTAssertFalse(app.buttons["script-Quarterly report"].exists)
        // An explicit new sample is allowed; deleted content is never reseeded automatically.
        tap(app, "sample-script")
        open(app)
        XCTAssertTrue(app.buttons["floating-preview-play"].label.contains("Preview"))
        XCTAssertEqual(app.sliders["floating-speed"].value as? String, defaultSpeed)
        capture("floating-after-clear-and-new-sample")
    }

    @MainActor func testNativeVoiceWindowStartsFromRecognitionAndKeepsHeldPassage() throws {
        let app = launch(dark: true, extra: ["--ui-session-speech-replay"]); open(app)
        guard app.buttons["floating-start"].exists else { throw XCTSkip("Native PiP unavailable on this simulator") }
        app.segmentedControls["floating-mode"].buttons["Voice follow"].tap()
        tap(app, "floating-start")
        let window = app.buttons["floating-start"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Close floating window"), evaluatedWith: window)
        waitForExpectations(timeout: 12)
        XCUIDevice.shared.press(.home)
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Native voice window on Home")], timeout: 7)
        capture("native-voice-pip-on-home-input-ended")
        app.activate()
        let preview = app.otherElements["floating-preview"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Try voice"), evaluatedWith: app.buttons["floating-preview-play"])
        waitForExpectations(timeout: 8)
        let position = preview.value as? String
        XCTAssertTrue(position?.contains("roadmap") == true || position?.contains("milestone") == true)
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Returned voice window stays paused")], timeout: 1)
        XCTAssertEqual(preview.value as? String, position)
        capture("native-voice-pip-return-paused")
    }

    @MainActor func testNativeCameraPreviewKeepsWindow() throws { try cameraPreviewCheck(voiceFollow: false) }
    @MainActor func testNativeCameraPreviewWithMicrophone() throws { try cameraPreviewCheck(voiceFollow: true) }
    @MainActor func testNativeVideoPreviewWithMicrophone() throws { try cameraPreviewCheck(voiceFollow: true, videoPreview: true) }
    @MainActor private func cameraPreviewCheck(voiceFollow: Bool, videoPreview: Bool = false) throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the physical system Camera; no recording is started by this test.")
        #else
        let app = launch(); open(app)
        if voiceFollow { app.segmentedControls["floating-mode"].buttons["Voice follow"].tap() }
        tap(app, "floating-start")
        let status = app.staticTexts["floating-status"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", voiceFollow ? "Listening" : "scrolling"), evaluatedWith: status)
        waitForExpectations(timeout: 15)
        XCUIDevice.shared.press(.home)
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "PiP settles on Home")], timeout: 2)
        capture("physical-pip-home-before-camera")
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let camera = XCUIApplication(bundleIdentifier: "com.apple.camera")
        camera.activate()
        XCTAssertTrue(camera.wait(for: .runningForeground, timeout: 10))
        if videoPreview {
            let strip = camera.otherElements["CameraMode"]
            XCTAssertTrue(strip.waitForExistence(timeout: 5))
            // The system exposes one adjustable mode strip, not individual
            // buttons. Swipe within that strip, away from the shutter, and
            // require the actual selected value before claiming video preview.
            if !["视频", "Video"].contains(strip.value as? String ?? "") { strip.swipeRight() }
            expectation(for: NSPredicate { _, _ in ["视频", "Video"].contains(strip.value as? String ?? "") }, evaluatedWith: strip)
            waitForExpectations(timeout: 5)
            capture("camera-video-mode-confirmed")
        }
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Camera preview coexistence")], timeout: 6)
        capture("physical-pip-camera-preview")
        let hierarchy = XCTAttachment(string: system.debugDescription)
        hierarchy.name = "camera-pip-system-controls"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        // iOS can stash playback PiP at the edge when Camera becomes active.
        // Restore the visible handle; do not touch the Camera shutter.
        let hidden = system.buttons.matching(NSPredicate(format: "label IN %@ AND value IN %@", ["视频", "Video"], ["已隐藏", "Hidden"])).firstMatch
        if hidden.exists {
            let y = hidden.frame.midY
            system.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: system.frame.width - 10, dy: y)).tap()
        }
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Restore stashed PiP")], timeout: 3)
        capture("physical-pip-camera-after-restoring-handle")
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.recognitionLevel = .accurate
        request.regionOfInterest = CGRect(x: 0.30, y: 0.74, width: 0.68, height: 0.22)
        let screen = XCUIScreen.main.screenshot().image
        try VNImageRequestHandler(cgImage: try XCTUnwrap(screen.cgImage)).perform([request])
        let visible = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined().lowercased() ?? ""
        XCTAssertTrue(["大家", "季度", "收入", "增长", "交付", "接下", "优先", "roadmap", "milestone", "客户", "计划", "第一", "三个", "现在", "团队", "谢谢", "最后"].contains(where: visible.contains), "PiP must contain manuscript text over Camera, not only native playback controls")
        // Never press Record or save a camera image. Audio-buffer diagnostics
        // confirm input delivery only, not spoken accuracy or recording coexistence.
        app.activate()
        app.swipeUp()
        let diagnostics = app.buttons["Window diagnostics"]
        if diagnostics.exists { diagnostics.tap() }
        let report = app.staticTexts["floating-diagnostics"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        let text = report.label
        let attachment = XCTAttachment(string: text)
        attachment.name = "physical-camera-pip-events"; attachment.lifetime = .keepAlways; add(attachment)
        guard let start = text.range(of: "pip.started", options: .backwards) else { return XCTFail("PiP did not start") }
        let events = String(text[start.upperBound...])
        if let stopped = events.range(of: "pip.stopped"), let returned = events.range(of: "app.foreground") {
            XCTAssertGreaterThan(stopped.lowerBound, returned.lowerBound, "The system ended PiP while Camera was foregrounded")
        }
        capture("physical-pip-camera-return-diagnostics")
        #endif
    }

    @MainActor func testNativeCountdownAdvancesAndReturnPauses() {
        let app = launch(dark: true); open(app)
        tap(app, "floating-choose-passage"); tap(app, "floating-passage-2")
        let preview = app.otherElements["floating-preview"]
        let passage = preview.value as? String
        if app.buttons["floating-start"].exists {
            tap(app, "floating-start")
            let status = app.staticTexts["floating-status"]
            expectation(for: NSPredicate { _, _ in status.label.contains("scrolling") || status.label.contains("did not open") }, evaluatedWith: status)
            waitForExpectations(timeout: 15)
            if status.label.contains("did not open") { XCTAssertTrue(app.staticTexts["floating-error"].exists) }
            else {
                // Let AVKit finish presenting the live-content surface.
                let settle = XCTWaiter.wait(for: [XCTestExpectation(description: "PiP frame settles")], timeout: 2)
                XCTAssertEqual(settle, .timedOut)
                capture("floating-native-window-open-dark")
                XCUIDevice.shared.press(.home)
                // Settle the Home transition before checking background progress.
                XCUIDevice.shared.orientation = .portrait
                _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Home transition settles")], timeout: 2)
                capture("floating-native-window-on-home")
                _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Advance beyond the starting passage")], timeout: 12)
                capture("floating-native-window-playing")
                app.activate()
                XCTAssertNotEqual(preview.value as? String, passage, "Countdown starts real manuscript progress")
                let previewPlay = app.buttons["floating-preview-play"]
                expectation(for: NSPredicate(format: "label CONTAINS %@", "Preview scrolling"), evaluatedWith: previewPlay)
                waitForExpectations(timeout: 5)
                capture("floating-return-paused")
                let resumed = preview.value as? String
                _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Returning remains paused")], timeout: 1)
                XCTAssertEqual(preview.value as? String, resumed)

            }
        } else {
            XCTAssertTrue(app.staticTexts["floating-status"].label.contains("unavailable"))
        }
        capture("floating-real-support-state-dark")
        tap(app, "floating-done")
    }
}
