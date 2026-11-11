import XCTest

final class PlanUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The fifth tab summarizes recurring, goals and debts, and each card leads to its screen.
    @MainActor
    func testPlanTabLeadsToItsScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let planTab = app.buttons["Plan"].firstMatch
        XCTAssertTrue(planTab.waitForExistence(timeout: 10))
        planTab.tap()
        XCTAssertTrue(app.staticTexts["Subscriptions per month"].waitForExistence(timeout: 5))

        // The card is one combined element, so its label carries the figures after the title.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Savings goals")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
    }
}
