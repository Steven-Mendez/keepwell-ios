import XCTest

extension XCUIApplication {
    /// The language step shows once per install; runs that kept the app's data skip it.
    func chooseEnglishIfAsked() {
        guard buttons["English"].waitForExistence(timeout: 5) else { return }
        buttons["English"].tap()
        buttons["Continue"].tap()
    }
}
