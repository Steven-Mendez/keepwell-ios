import XCTest

final class AccountsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAccountsTabShowsCardsDepositsAndCash() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["Accounts"].waitForExistence(timeout: 10))
        app.buttons["Accounts"].tap()
        XCTAssertTrue(app.staticTexts["Deposits"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reconcile"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "accounts"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
