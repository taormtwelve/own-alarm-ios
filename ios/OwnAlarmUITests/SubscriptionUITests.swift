import XCTest

/// The Free/Premium plan: the limit on a Free account, the paywall it triggers, and
/// what Settings shows for each plan.
///
/// The four sample alarms already exceed the Free limit, so every other suite runs
/// as Premium (see `OwnAlarmApp.makeStore`) — only this suite passes `-freeTier` to
/// actually exercise the limit, starting from `-emptyStore` so it can add alarms up
/// to it from a known count.
final class SubscriptionUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-emptyStore", "-freeTier"]
        app.launch()
    }

    private var rows: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "alarmRow")
    }

    private func addAlarm(named name: String) {
        app.buttons["New alarm"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }

    // MARK: The limit

    func testAFreeAccountIsOfferedThePaywallAtTheLimit() {
        XCTAssertTrue(app.staticTexts["No alarms yet"].waitForExistence(timeout: 10))

        // The first alarm from the empty state, the rest from the toolbar button —
        // both routes reach the same limit.
        app.buttons["Add an alarm"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("One")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["One"].waitForExistence(timeout: 5))

        addAlarm(named: "Two")
        addAlarm(named: "Three")
        XCTAssertEqual(rows.count, 3, "At the free limit")

        // A fourth is turned away with the paywall instead of the editor.
        app.buttons["New alarm"].tap()
        XCTAssertTrue(app.staticTexts["You've reached the free limit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields.firstMatch.exists, "The editor should not have opened")

        app.buttons["Maybe later"].tap()
        XCTAssertFalse(app.staticTexts["You've reached the free limit"].exists)
        XCTAssertEqual(rows.count, 3, "Dismissing the paywall adds nothing")
    }

    func testAddingBelowTheLimitNeverShowsThePaywall() {
        XCTAssertTrue(app.staticTexts["No alarms yet"].waitForExistence(timeout: 10))
        app.buttons["Add an alarm"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("One")
        app.buttons["Save"].tap()

        addAlarm(named: "Two")

        XCTAssertEqual(rows.count, 2, "Below the limit — room for one more")
        XCTAssertFalse(app.staticTexts["You've reached the free limit"].exists)
    }

    // MARK: Sample data

    func testTheSampleDataRunsAsPremiumSoTheLimitNeverBlocksIt() {
        app.terminate()
        app.launchArguments = ["-uitesting"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Morning run"].waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 4, "The samples already exceed the Free limit")

        // A fifth alarm still opens the editor, not the paywall.
        app.buttons["New alarm"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["You've reached the free limit"].exists)
    }

    // MARK: Settings

    func testSettingsShowsTheFreePlanAndOffersToUpgrade() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Time format"].waitForExistence(timeout: 10))
        // The Subscription section sits last, below the fold on a short phone.
        app.swipeUp()

        XCTAssertTrue(app.staticTexts["Plan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Free"].exists)
        XCTAssertTrue(app.staticTexts["Upgrade to Premium"].exists)
        XCTAssertTrue(app.staticTexts["Restore purchases"].exists)
    }
}
