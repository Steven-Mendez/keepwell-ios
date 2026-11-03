import XCTest

final class CreateTransactionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLoggingAnExpenseInCórdobasPaidByDebit() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data", "-open-new-movement"]
        app.launch()

        XCTAssertTrue(app.buttons["Siguiente"].waitForExistence(timeout: 10))
        for key in ["8", "7", "9"] {
            app.buttons[key].tap()
        }
        attach("1-amount")
        app.buttons["Siguiente"].tap()

        XCTAssertTrue(app.staticTexts["¿En qué fue?"].waitForExistence(timeout: 5))
        attach("2-category")
        app.buttons["Restaurantes"].tap()

        XCTAssertTrue(app.staticTexts["¿Con qué pagaste?"].waitForExistence(timeout: 5))
        attach("3-method")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Débito •••• 1234")).firstMatch.tap()

        XCTAssertTrue(app.buttons["Guardar gasto"].waitForExistence(timeout: 5))
        let debit = app.textFields.element(boundBy: 1)
        debit.tap()
        debit.typeText("24.28")
        app.buttons["Listo"].tap()
        attach("4-review")
        app.buttons["Guardar gasto"].tap()

        XCTAssertTrue(app.staticTexts["Confirmado"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["36.20 NIO"].exists)
        attach("5-saved")
        app.buttons["Listo"].tap()
        XCTAssertTrue(app.buttons["Cuentas"].waitForExistence(timeout: 5))
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
