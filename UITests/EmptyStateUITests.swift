import XCTest

final class EmptyStateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Right after onboarding there are no movements: tabs explain it and offer to log one.
    @MainActor
    func testTabsWithoutDataSayItAndOfferToLogAMovement() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.leaveWelcomeWithoutAccount()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Protect Keepwell"].waitForExistence(timeout: 5))
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.staticTexts["Your data stays yours"].waitForExistence(timeout: 5))
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.buttons["Go to home"].waitForExistence(timeout: 5))
        app.buttons["Go to home"].tap()

        XCTAssertTrue(app.staticTexts["No transactions yet"].waitForExistence(timeout: 5))
        attach("inicio")
        app.buttons["Transactions"].tap()
        XCTAssertTrue(app.staticTexts["No transactions yet"].waitForExistence(timeout: 5))
        attach("movimientos")
        app.buttons["Summary"].tap()
        XCTAssertTrue(app.staticTexts["Your summary starts with one transaction"].waitForExistence(timeout: 5))
        attach("resumen")

        app.buttons["Log transaction"].tap()
        XCTAssertTrue(app.staticTexts["What are you recording?"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Expense")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
