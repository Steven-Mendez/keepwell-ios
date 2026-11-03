import XCTest

final class AddCardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddingACreditCardShowsItOnAccounts() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data"]
        app.launch()

        XCTAssertTrue(app.buttons["Cuentas"].waitForExistence(timeout: 10))
        app.buttons["Cuentas"].tap()
        app.buttons["Agregar cuenta o tarjeta"].tap()
        XCTAssertTrue(app.staticTexts["¿Qué quieres agregar?"].waitForExistence(timeout: 5))
        attach("1-type")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tarjeta de crédito")).firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Tu tarjeta de crédito"].waitForExistence(timeout: 5))
        let bank = app.textFields["Nombre del banco"]
        bank.tap()
        bank.typeText("Banco Tres")
        let digits = app.textFields["0000"]
        digits.tap()
        digits.typeText("2468")
        app.buttons["Listo"].tap()
        app.buttons["Violeta"].tap()
        attach("2-plastic")
        app.buttons["Continuar"].tap()

        XCTAssertTrue(app.staticTexts["Cómo funciona la deuda"].waitForExistence(timeout: 5))
        attach("3-debt")
        app.buttons["Agregar tarjeta"].tap()

        XCTAssertTrue(app.staticTexts["Tarjeta agregada"].waitForExistence(timeout: 5))
        attach("4-added")
        app.buttons["Ver tarjeta"].tap()

        XCTAssertTrue(app.staticTexts["Banco Tres"].waitForExistence(timeout: 5))
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
