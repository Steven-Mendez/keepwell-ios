import XCTest

final class KeepwellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesOnTransactionsDashboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.staticTexts["transactions.month.title"].waitForExistence(timeout: 10))
    }
}
