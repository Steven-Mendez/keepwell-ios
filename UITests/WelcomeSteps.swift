import XCTest

extension XCUIApplication {
    /// Leaves the welcome for setup without a Keepwell account. Builds with the API show the
    /// sign-in there and "Use without an account" under it; builds without one show "Start".
    func leaveWelcomeWithoutAccount(file: StaticString = #filePath, line: UInt = #line) {
        let withoutAccount = buttons["Use without an account"]
        let start = buttons["Start"]
        let deadline = Date.now.addingTimeInterval(10)
        while !withoutAccount.exists, !start.exists, Date.now < deadline {
            _ = withoutAccount.waitForExistence(timeout: 0.5)
        }
        if withoutAccount.exists {
            withoutAccount.tap()
        } else {
            XCTAssertTrue(start.exists, "The welcome offers no way to start", file: file, line: line)
            start.tap()
        }
    }
}
