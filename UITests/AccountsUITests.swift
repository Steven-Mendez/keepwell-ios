import XCTest

final class AccountsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAccountsTabShowsCardsDepositsAndCash() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data"]
        app.launch()

        XCTAssertTrue(app.buttons["Cuentas"].waitForExistence(timeout: 10))
        app.buttons["Cuentas"].tap()
        XCTAssertTrue(app.staticTexts["Depósitos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cuadrar"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "accounts"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
