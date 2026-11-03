import XCTest

final class CreateTransactionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLoggingAnExpenseInCórdobasPaidByDebit() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data", "-open-new-movement", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
        for key in ["8", "7", "9"] {
            app.buttons[key].tap()
        }
        attach("expense-1-amount")
        app.buttons["Next"].tap()

        XCTAssertTrue(app.staticTexts["What was it for?"].waitForExistence(timeout: 5))
        attach("expense-2-category")
        app.buttons["Restaurants"].tap()

        XCTAssertTrue(app.staticTexts["How did you pay?"].waitForExistence(timeout: 5))
        attach("expense-3-method")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Debit •••• 1234")).firstMatch.tap()

        let confirm = app.buttons["Save expense"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        let debit = app.textFields.element(boundBy: 1)
        debit.tap()
        debit.typeText("24.28")
        app.scrollViews.firstMatch.swipeDown()
        attach("expense-4-review")
        slide(confirm)

        XCTAssertTrue(app.staticTexts["Confirmed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["36.20 NIO"].exists)
        XCTAssertTrue(app.buttons["Share"].exists)
        XCTAssertTrue(app.buttons["Save image"].exists)
        attach("expense-5-receipt")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Accounts"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMovingMoneyBetweenOwnAccountsFromTheMenu() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["Transactions"].waitForExistence(timeout: 10))
        app.buttons["Transactions"].tap()
        app.buttons["New transaction"].tap()
        XCTAssertTrue(app.staticTexts["What are you recording?"].waitForExistence(timeout: 5))
        attach("transfer-0-menu")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Between my accounts")).firstMatch.tap()

        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wallet")).firstMatch.tap()
        XCTAssertTrue(next.isEnabled)
        attach("transfer-1-accounts")
        next.tap()

        XCTAssertTrue(app.staticTexts["How much are you moving?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Review"].isEnabled)
        for key in ["1", "0", "0"] {
            app.buttons[key].tap()
        }
        app.buttons["Add a note"].tap()
        // Return submits the note, as the sheet's Done button does.
        app.textFields.firstMatch.typeText("Weekend market\n")
        attach("transfer-2-amount")
        app.buttons["Review"].tap()

        let confirm = app.buttons["Save transfer"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        attach("transfer-3-review")
        slide(confirm)

        XCTAssertTrue(app.staticTexts["You moved"].waitForExistence(timeout: 5))
        attach("transfer-4-receipt")
        app.buttons["Done"].tap()
    }

    /// Drags the slide-to-confirm thumb from its resting place to the far end.
    private func slide(_ control: XCUIElement) {
        let start = control.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        let end = control.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
