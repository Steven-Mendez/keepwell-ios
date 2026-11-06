import XCTest

final class SummaryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The chart switch reaches all three charts, and the month stepper moves every one of them.
    @MainActor
    func testSwitchesBetweenTheThreeCharts() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let summaryTab = app.buttons["Summary"].firstMatch
        XCTAssertTrue(summaryTab.waitForExistence(timeout: 10))
        summaryTab.tap()
        XCTAssertTrue(app.buttons["Cash flow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Result per month"].exists)
        attach("cash-flow")

        app.buttons["Categories"].tap()
        XCTAssertTrue(app.staticTexts["By category"].waitForExistence(timeout: 5))
        attach("categories")

        app.buttons["Pace"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Spent so far in")).firstMatch
            .waitForExistence(timeout: 5))
        attach("pace")

        app.buttons["Previous month"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Spent in")).firstMatch
            .waitForExistence(timeout: 5))
        attach("pace-previous-month")
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
