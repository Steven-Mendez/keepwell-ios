import XCTest

final class AddCardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddingACreditCardShowsItOnAccounts() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["Accounts"].waitForExistence(timeout: 10))
        app.buttons["Accounts"].tap()
        app.buttons["Add account or card"].tap()
        XCTAssertTrue(app.staticTexts["What do you want to add?"].waitForExistence(timeout: 5))
        attach("1-type")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Credit card")).firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Your credit card"].waitForExistence(timeout: 5))
        let bank = app.textFields["Bank"]
        bank.tap()
        bank.typeText("Bank Three")
        let digits = app.textFields["Last 4 digits"]
        digits.tap()
        digits.typeText("2468")
        app.buttons["Violet"].tap()
        attach("2-plastic")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["How the debt works"].waitForExistence(timeout: 5))
        attach("3-debt")
        app.buttons["Add card"].tap()

        XCTAssertTrue(app.staticTexts["Card added"].waitForExistence(timeout: 5))
        attach("4-added")
        app.buttons["View card"].tap()

        XCTAssertTrue(app.staticTexts["Bank Three"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddingADebitCardCreatesItsBankAccount() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["Accounts"].waitForExistence(timeout: 10))
        app.buttons["Accounts"].tap()
        app.buttons["Add account or card"].tap()
        XCTAssertTrue(app.staticTexts["What do you want to add?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Bank account"].exists)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Debit card")).firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Your debit card"].waitForExistence(timeout: 5))
        let bank = app.textFields["Bank"]
        bank.tap()
        bank.typeText("Bank Four")
        let account = app.textFields["Account"]
        account.tap()
        account.typeText("Travel")
        let digits = app.textFields["Last 4 digits"]
        digits.tap()
        digits.typeText("1357")
        attach("debit-plastic")
        app.buttons["Add card"].tap()

        XCTAssertTrue(app.staticTexts["Card added"].waitForExistence(timeout: 5))
        attach("debit-added")
        app.buttons["View card"].tap()

        XCTAssertTrue(app.staticTexts["Bank account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Travel"].exists)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
