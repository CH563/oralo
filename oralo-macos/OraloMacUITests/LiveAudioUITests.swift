import XCTest
import AppKit

/// Opt-in hardware check. Never joins a meeting or records audio to disk.
nonisolated final class LiveAudioUITests: XCTestCase {
    @MainActor func testLiveMicrophoneWithTencentForeground() async throws {
        guard ProcessInfo.processInfo.environment["ORALO_VALIDATE_LIVE_AUDIO"] == "1" else {
            throw XCTSkip("Opt in with TEST_RUNNER_ORALO_VALIDATE_LIVE_AUDIO=1")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library=\(UUID())", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        app.activate()
        // macOS can restore this menu-bar app with its workspace closed.
        // Reopen it through the same native Window command available to users.
        if !app.buttons["welcome-continue"].waitForExistence(timeout: 3) {
            app.menuBars.menuBarItems["窗口"].click()
            app.menuBars.menuBarItems["窗口"].menus.menuItems["Oralo"].firstMatch.click()
        }
        XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 8))
        app.buttons["welcome-continue"].click()
        defer { app.terminate() }
        let monitor = addUIInterruptionMonitor(withDescription: "Oralo microphone permission") { alert in
            for title in ["允许", "Allow", "好", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].click(); return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }
        XCTAssertTrue(app.buttons["sample-script"].waitForExistence(timeout: 8))
        app.buttons["sample-script"].click()
        app.buttons["start-floating"].click()
        let panel = app.descendants(matching: .any).matching(identifier: "floating-window").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 6))
        panel.hover()
        panel.hover() // Move again after a permission alert has been dismissed.
        XCTAssertTrue(app.buttons["floating-settings"].waitForExistence(timeout: 6))
        app.buttons["floating-settings"].click() // Triggers interruption handling if TCC is visible.
        if app.buttons["close-floating-settings"].exists { app.buttons["close-floating-settings"].click() }
        let status = app.staticTexts["speech-status"]
        // The compact status distinguishes off-script holding while capture is active.
        let listening = NSPredicate { _, _ in
            MainActor.assumeIsolated { (status.value as? String)?.contains("正在聆听") == true || status.label.contains("正在聆听") || (status.value as? String)?.contains("自由发挥") == true || status.label.contains("自由发挥") }
        }
        let initial = await XCTWaiter.fulfillment(of: [XCTNSPredicateExpectation(predicate: listening, object: nil)], timeout: 12)
        if initial != .completed, app.buttons["floating-audio-issue"].exists {
            app.buttons["floating-audio-issue"].click()
            let download = app.buttons["下载模型并继续"]
            if download.exists { download.click() }
        }
        let ready = await XCTWaiter.fulfillment(of: [XCTNSPredicateExpectation(predicate: listening, object: nil)], timeout: 90)
        XCTAssertEqual(ready, .completed)
        guard (status.value as? String)?.contains("正在聆听") == true || status.label.contains("正在聆听") || (status.value as? String)?.contains("自由发挥") == true || status.label.contains("自由发挥") else {
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "live-audio-unavailable"; attachment.lifetime = .keepAlways; add(attachment)
            return
        }
        let paused = NSPredicate { _, _ in
            MainActor.assumeIsolated { (status.value as? String)?.contains("已暂停") == true || status.label.contains("已暂停") }
        }
        let meeting = XCUIApplication(bundleIdentifier: "com.tencent.meeting")
        meeting.activate()
        try await Task.sleep(for: .seconds(5))
        XCTAssertEqual(meeting.state, .runningForeground)
        XCTAssertTrue(panel.exists)
        let running = await XCTWaiter.fulfillment(of: [XCTNSPredicateExpectation(predicate: listening, object: nil)], timeout: 10)
        XCTAssertEqual(running, .completed)
        let anchor = meeting.menuBars.firstMatch
        let frame = panel.frame
        anchor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX - anchor.frame.minX, dy: frame.maxY - 22 - anchor.frame.minY)).hover()
        XCTAssertTrue(app.buttons["floating-toggle"].waitForExistence(timeout: 3))
        for expectedState in [paused, listening] {
            let control = app.buttons["floating-toggle"].frame
            anchor.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: control.midX - anchor.frame.minX, dy: control.midY - anchor.frame.minY)).click()
            let changed = await XCTWaiter.fulfillment(of: [XCTNSPredicateExpectation(predicate: expectedState, object: nil)], timeout: 15)
            XCTAssertEqual(changed, .completed)
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.tencent.meeting")
        }
        let attachment = XCTAttachment(string: "Oralo microphone capture is active with Tencent Meeting foreground. Remote meeting audio, live speech latency and speaker accuracy still require a real spoken trial.")
        attachment.name = "live-capture-state"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
