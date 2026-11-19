import XCTest

final class WelcomeUITests: XCTestCase {
    @MainActor private func app(language: String = "en", largeType: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-welcome", "--ui-library=\(UUID().uuidString)",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if largeType {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 12))
        return app
    }

    @MainActor func testSystemLanguageAndCompletionSurviveRelaunch() {
        let english = app()
        XCTAssertEqual(english.buttons["welcome-continue"].label, "Let’s get ready")
        XCTAssertFalse(english.buttons["welcome-language"].exists)
        capture(english, name: "Welcome English")
        english.terminate()
        let app = app(language: "zh-Hans")
        XCTAssertFalse(app.alerts.firstMatch.exists, "The introduction must not request microphone permission.")
        XCTAssertEqual(app.buttons["welcome-continue"].label, "准备我的演讲")
        XCTAssertFalse(app.buttons["welcome-language"].exists)
        let start = app.buttons["welcome-continue"]
        capture(app, name: "Welcome Chinese")
        start.tap()
        XCTAssertTrue(app.buttons["new-script-menu"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["new-script-menu"].waitForExistence(timeout: 10))
        XCTAssertFalse(start.exists, "Returning users should go straight to their scripts.")
    }

    @MainActor func testLargeTypeCanEnterLibrary() {
        let app = app(largeType: true)
        let start = app.buttons["welcome-continue"]
        XCTAssertTrue(start.isHittable)
        XCTAssertLessThanOrEqual(start.frame.maxY, app.frame.maxY)
        XCTAssertGreaterThanOrEqual(start.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(start.frame.maxX, app.frame.maxX)
        capture(app, name: "Welcome accessibility text")
        start.tap()
        XCTAssertTrue(app.buttons["new-script-menu"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
