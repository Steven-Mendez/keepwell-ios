import XCTest

final class EmptyStateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Right after onboarding there are no movements: tabs explain it and offer to log one.
    @MainActor
    func testTabsWithoutDataSayItAndOfferToLogAMovement() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
        app.buttons["Start"].tap()
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.buttons["Go to home"].waitForExistence(timeout: 5))
        app.buttons["Go to home"].tap()

        XCTAssertTrue(app.staticTexts["No transactions yet"].waitForExistence(timeout: 5))
        attach("inicio")
        app.buttons["Transactions"].tap()
        XCTAssertTrue(app.staticTexts["No transactions yet"].waitForExistence(timeout: 5))
        attach("movimientos")
        app.buttons["Summary"].tap()
        XCTAssertTrue(app.staticTexts["Your summary starts with one transaction"].waitForExistence(timeout: 5))
        attach("resumen")

        app.buttons["Log transaction"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
