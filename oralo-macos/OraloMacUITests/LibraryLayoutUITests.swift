import XCTest
import AppKit
import Carbon

nonisolated final class LibraryLayoutUITests: XCTestCase {
    @MainActor func testLibraryCardsAndRowsAcrossLanguagesAndAppearances() throws {
        continueAfterFailure = false
        let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let sources = TISCreateInputSourceList([kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary, false).takeRetainedValue() as! [TISInputSource]
        XCTAssertEqual(TISSelectInputSource(try XCTUnwrap(sources.first)), noErr)
        defer { TISSelectInputSource(original) }
        for language in ["zh-Hans", "en"] {
            let chinese = language == "zh-Hans"
            guard let id = ProcessInfo.processInfo.environment[chinese ? "ORALO_LAYOUT_LIBRARY_ZH" : "ORALO_LAYOUT_LIBRARY_EN"] else {
                throw XCTSkip("Run scripts/check_library_layout.py to seed the isolated layout fixtures.")
            }
            let app = XCUIApplication()
            app.launchArguments = ["--ui-library=\(id)", "--ui-silent", "-AppleLanguages", "(\(language))"]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 8))
            app.buttons["welcome-continue"].click()
            let scripts = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library-script-"))
            XCTAssertTrue(scripts.firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(scripts.count, 4)
            let window = app.windows.firstMatch
            for appearance in ["light", "dark"] {
                app.typeKey(",", modifierFlags: .command)
                let theme = app.popUpButtons["theme-picker"]
                XCTAssertTrue(theme.waitForExistence(timeout: 3))
                theme.click()
                app.menuItems[chinese ? (appearance == "light" ? "浅色" : "深色") : (appearance == "light" ? "Light" : "Dark")].click()
                let settings = app.windows.containing(.popUpButton, identifier: "theme-picker").firstMatch
                settings.buttons.matching(NSPredicate(format: "identifier == %@ OR label CONTAINS[c] %@ OR label CONTAINS %@", "_XCUI:CloseWindow", "close", "关闭")).firstMatch.click()
                for width in [900.0, 1120.0] {
                    let before = window.frame
                    let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -14))
                    corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: width - before.width, dy: 760 - before.height)))
                    XCTAssertEqual(window.frame.width, width, accuracy: 8)
                    for grid in [true, false] {
                        let label = grid ? (chinese ? "平铺" : "Grid") : (chinese ? "列表" : "List")
                        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch.click()
                        for item in scripts.allElementsBoundByIndex {
                            XCTAssertGreaterThanOrEqual(item.frame.minX, window.frame.minX)
                            XCTAssertLessThanOrEqual(item.frame.maxX, window.frame.maxX)
                            XCTAssertGreaterThan(item.frame.height, grid ? 190 : 50)
                            XCTAssertTrue((item.value as? String)?.contains(chinese ? "分钟" : "min") == true || (item.value as? String)?.contains(chinese ? "待估算" : "Duration") == true)
                        }
                        let attachment = XCTAttachment(screenshot: window.screenshot())
                        attachment.name = "library-\(grid ? "grid" : "list")-\(language)-\(appearance)-\(Int(width))"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
            app.terminate()
        }
    }

}
