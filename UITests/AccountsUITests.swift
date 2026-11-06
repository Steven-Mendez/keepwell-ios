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
        // Each bank account is shown as its one debit card; there is no separate deposits list.
        XCTAssertTrue(app.staticTexts["Credit cards"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bank accounts"].exists)
        XCTAssertFalse(app.buttons["Link another card"].exists)
        XCTAssertTrue(app.staticTexts["Cash"].exists)
        XCTAssertTrue(app.buttons["Reconcile"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "accounts"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testABankAccountAndItsCardShareOneScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["Accounts"].waitForExistence(timeout: 10))
        app.buttons["Accounts"].tap()
        let savings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bank One Savings debit card")).firstMatch
        XCTAssertTrue(savings.waitForExistence(timeout: 5))
        savings.tap()

        XCTAssertTrue(app.staticTexts["Bank account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Manage account"].exists)
        XCTAssertFalse(app.buttons["Link another card"].exists)
        let delete = app.buttons["Delete account"]
        for _ in 0 ..< 4 where !delete.isHittable {
            app.swipeUp()
        }
        delete.tap()
        XCTAssertTrue(app.staticTexts["Delete Bank One Savings?"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "delete-account"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
