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
        attach("1-amount")
        app.buttons["Next"].tap()

        XCTAssertTrue(app.staticTexts["What was it for?"].waitForExistence(timeout: 5))
        attach("2-category")
        app.buttons["Restaurants"].tap()

        XCTAssertTrue(app.staticTexts["How did you pay?"].waitForExistence(timeout: 5))
        attach("3-method")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Debit •••• 1234")).firstMatch.tap()

        XCTAssertTrue(app.buttons["Save expense"].waitForExistence(timeout: 5))
        let debit = app.textFields.element(boundBy: 1)
        debit.tap()
        debit.typeText("24.28")
        attach("4-review")
        app.buttons["Save expense"].tap()

        XCTAssertTrue(app.staticTexts["Confirmed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["36.20 NIO"].exists)
        attach("5-saved")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Accounts"].waitForExistence(timeout: 5))
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
