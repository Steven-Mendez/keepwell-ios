import XCTest

final class RecurringUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// From Plan to a rule's detail and its next payment, then "Link a payment": the movement found
    /// by searching becomes one of its payments.
    @MainActor
    func testLinkingAMovementMakesItAPaymentOfTheRule() {
        let app = XCUIApplication()
        app.launchArguments = ["-sample-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let planTab = app.buttons["Plan"].firstMatch
        XCTAssertTrue(planTab.waitForExistence(timeout: 10))
        planTab.tap()
        let recurringCard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Recurring")).firstMatch
        XCTAssertTrue(recurringCard.waitForExistence(timeout: 5))
        recurringCard.tap()

        let streaming = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Streaming")).firstMatch
        XCTAssertTrue(streaming.waitForExistence(timeout: 5))
        streaming.tap()

        // Each line is one combined element, so its label starts with the caption.
        let nextPayment = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Next payment")).firstMatch
        XCTAssertTrue(nextPayment.waitForExistence(timeout: 5))
        // From the 23rd on, the rule's own charge of the month is already confirmed and counted, so
        // what linking adds is read against what was there before.
        let paidThisYear = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Paid this year")).firstMatch
        let paidBefore = paidThisYear.exists ? paidThisYear.label : nil

        // The sample's streaming charge was paid in córdobas, so it isn't suggested: it's searched.
        app.buttons["Link a payment"].firstMatch.tap()
        let search = app.textFields["Search movements"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Streaming")
        let movement = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Streaming", "197.02"))
            .firstMatch
        XCTAssertTrue(movement.waitForExistence(timeout: 5))
        movement.tap()

        XCTAssertTrue(paidThisYear.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Streaming", "197.02"))
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertNotEqual(paidThisYear.label, paidBefore)
        XCTAssertFalse(app.staticTexts["No payments yet"].exists)
    }
}
