import XCTest

final class EmptyStateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Right after onboarding there are no movements: tabs explain it and offer to log one.
    @MainActor
    func testTabsWithoutDataSayItAndOfferToLogAMovement() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.buttons["Empezar"].waitForExistence(timeout: 10))
        app.buttons["Empezar"].tap()
        app.buttons["Continuar"].tap()
        app.buttons["Continuar"].tap()
        app.buttons["Ahora no"].tap()
        XCTAssertTrue(app.buttons["Ir al inicio"].waitForExistence(timeout: 5))
        app.buttons["Ir al inicio"].tap()

        XCTAssertTrue(app.staticTexts["Aún no tienes movimientos"].waitForExistence(timeout: 5))
        attach("inicio")
        app.buttons["Movimientos"].tap()
        XCTAssertTrue(app.staticTexts["Aún no tienes movimientos"].waitForExistence(timeout: 5))
        attach("movimientos")
        app.buttons["Resumen"].tap()
        XCTAssertTrue(app.staticTexts["Tu resumen empieza con un movimiento"].waitForExistence(timeout: 5))
        attach("resumen")

        app.buttons["Anotar movimiento"].tap()
        XCTAssertTrue(app.buttons["Siguiente"].waitForExistence(timeout: 5))
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
