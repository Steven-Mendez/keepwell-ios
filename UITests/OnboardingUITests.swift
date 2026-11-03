import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Walks every step with the defaults and lands on the main tabs. Each step's screenshot is
    /// attached to the result for comparison with the design.
    @MainActor
    func testOnboardingReachesTheMainTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
        attachScreenshot("1-welcome")
        app.buttons["Start"].tap()

        XCTAssertTrue(app.staticTexts["Which currencies do you use?"].waitForExistence(timeout: 5))
        let rate = app.textFields["Exchange rate"]
        rate.tap()
        attachScreenshot("2-currencies-editing")
        XCTAssertFalse(app.buttons["Done"].exists, "The design has no keyboard toolbar button")
        app.staticTexts["Second currency"].tap()
        XCTAssertEqual(app.keyboards.count, 0)
        app.buttons["Nicaragua example: 1 USD = 36.6243 NIO"].tap()
        attachScreenshot("2-currencies")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Add your accounts"].waitForExistence(timeout: 5))
        attachScreenshot("3-accounts")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Protect your data"].waitForExistence(timeout: 5))
        attachScreenshot("4-privacy")
        app.buttons["Not now"].tap()

        XCTAssertTrue(app.staticTexts["All set"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 USD = 36.6243 NIO"].exists)
        attachScreenshot("5-done")
        app.buttons["Go to home"].tap()

        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
