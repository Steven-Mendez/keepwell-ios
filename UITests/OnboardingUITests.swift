import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Walks every step, giving a name and creating a passcode, and lands on the main tabs greeted
    /// by name. Each step's screenshot is attached to the result for comparison with the design.
    @MainActor
    func testOnboardingReachesTheMainTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
        attachScreenshot("1-welcome")
        app.buttons["Start"].tap()

        XCTAssertTrue(app.staticTexts["What should we call you?"].waitForExistence(timeout: 5))
        let name = app.textFields["Your name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Steven")
        attachScreenshot("2-name")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Which currencies do you use?"].waitForExistence(timeout: 5))
        let rate = app.textFields["Exchange rate"]
        rate.tap()
        attachScreenshot("3-currencies-editing")
        XCTAssertFalse(app.buttons["Done"].exists, "The design has no keyboard toolbar button")
        app.staticTexts["Second currency"].tap()
        XCTAssertEqual(app.keyboards.count, 0)
        app.buttons["Nicaragua example: 1 USD = 36.6243 NIO"].tap()
        attachScreenshot("3-currencies")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Add your accounts"].waitForExistence(timeout: 5))
        attachScreenshot("4-accounts")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Protect Keepwell"].waitForExistence(timeout: 5))
        attachScreenshot("5-protect")
        app.buttons["Create passcode"].tap()
        XCTAssertTrue(app.staticTexts["Create a passcode"].waitForExistence(timeout: 5))
        typePasscode("135790", in: app)
        XCTAssertTrue(app.staticTexts["Confirm your passcode"].waitForExistence(timeout: 5))
        typePasscode("135790", in: app)
        XCTAssertTrue(app.staticTexts["On · tap to choose another"].waitForExistence(timeout: 10))
        attachScreenshot("5-protect-done")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Your data stays yours"].waitForExistence(timeout: 5))
        attachScreenshot("6-privacy")
        app.buttons["Not now"].tap()

        XCTAssertTrue(app.staticTexts["All set, Steven"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 USD = 36.6243 NIO"].exists)
        attachScreenshot("7-done")
        app.buttons["Go to home"].tap()

        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        let greeting = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Steven")).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 5))
    }

    private func typePasscode(_ digits: String, in app: XCUIApplication) {
        for digit in digits {
            app.buttons[String(digit)].tap()
        }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
