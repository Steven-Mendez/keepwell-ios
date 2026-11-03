import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Walks every step with the defaults and lands on the main tabs. Each step's screenshot is
    /// attached to the result for comparison with the design.
    @MainActor
    func testOnboardingReachesTheMainTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.buttons["Empezar"].waitForExistence(timeout: 10))
        attachScreenshot("1-welcome")
        app.buttons["Empezar"].tap()

        XCTAssertTrue(app.staticTexts["¿Con qué monedas trabajas?"].waitForExistence(timeout: 5))
        let rate = app.textFields["Tasa de cambio"]
        rate.tap()
        attachScreenshot("2-currencies-editing")
        XCTAssertFalse(app.buttons["Listo"].exists, "The design has no keyboard toolbar button")
        app.staticTexts["Segunda moneda"].tap()
        XCTAssertEqual(app.keyboards.count, 0)
        app.buttons["Ejemplo Nicaragua: 1 USD = 36.6243 NIO"].tap()
        attachScreenshot("2-currencies")
        app.buttons["Continuar"].tap()

        XCTAssertTrue(app.staticTexts["Agrega tus cuentas"].waitForExistence(timeout: 5))
        attachScreenshot("3-accounts")
        app.buttons["Continuar"].tap()

        XCTAssertTrue(app.staticTexts["Protege tus datos"].waitForExistence(timeout: 5))
        attachScreenshot("4-privacy")
        app.buttons["Ahora no"].tap()

        XCTAssertTrue(app.staticTexts["Todo listo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 USD = 36.6243 NIO"].exists)
        attachScreenshot("5-done")
        app.buttons["Ir al inicio"].tap()

        XCTAssertTrue(app.buttons["Inicio"].waitForExistence(timeout: 5))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
