import XCTest

/// Forms keep their primary action reachable while typing: number pads have no return key, so a
/// button behind the keyboard left people stuck.
final class KeyboardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBankAccountFormCanBeSavedWithTheKeyboardUp() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
        app.buttons["Start"].tap()
        XCTAssertTrue(app.staticTexts["What should we call you?"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.staticTexts["Which currencies do you use?"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Add your accounts"].waitForExistence(timeout: 5))
        app.buttons["Bank"].tap()

        // The bank field takes focus with the sheet; return moves on to the account name.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("LAFISE\n")
        app.typeText("Savings")
        app.buttons["Next field"].tap()
        app.typeText("12345")
        XCTAssertEqual(app.textFields["Debit, last 4"].value as? String, "1234")
        app.buttons["Next field"].tap()
        // Typing into the focused field rather than tapping the pad's keys: once text has been typed
        // the simulator may tuck the pad away and leave only the keyboard toolbar, so its keys can be
        // off screen. The checks below hold either way, since they compare against the keyboard's frame.
        let balance = app.textFields.element(matching: NSPredicate(format: "hasKeyboardFocus == true"))
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        balance.typeText("10000")
        _ = XCTWaiter.wait(for: [expectation(description: "scroll settles")], timeout: 1)
        attach("bank-account-typing")

        let add = app.buttons["Add"]
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(add.isHittable, "Add must sit above the keyboard")
        XCTAssertLessThan(add.frame.maxY, app.keyboards.firstMatch.frame.minY)
        add.tap()

        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "10,000.00")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        attach("accounts-after-save")
    }

    private func attach(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
