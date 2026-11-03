import XCTest

final class AccountsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAccountsTabShowsCreditCardsDebitCardsAndCash() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["Accounts"].waitForExistence(timeout: 10))
        app.buttons["Accounts"].tap()
        // Bank accounts are shown through their debit cards; there is no separate deposits list.
        XCTAssertTrue(app.staticTexts["Credit cards"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Debit cards"].exists)
        XCTAssertTrue(app.staticTexts["Cash"].exists)
        XCTAssertTrue(app.buttons["Reconcile"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "accounts"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
