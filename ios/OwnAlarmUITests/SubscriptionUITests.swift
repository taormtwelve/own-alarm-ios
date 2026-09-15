import XCTest

/// Membership: a free plan that keeps three alarms, and a subscription with no limit.
/// UI-test launches use a stand-in for the App Store: the app starts as a member unless
/// launched with `-free`, and "Become a member" subscribes at once.
final class SubscriptionUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String]) {
        app.launchArguments = ["-uitesting"] + arguments
        app.launch()
    }

    private var rows: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "alarmRow")
    }

    private func openSettings() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Time format"].waitForExistence(timeout: 10))
        // Membership is the first section, in view as Settings opens.
    }

    // MARK: The limit

    func testAFreeUserCanSetThreeAlarmsAndIsOfferedMembershipForAFourth() {
        launch(["-free", "-emptyStore"])

        for task in ["One", "Two", "Three"] {
            let add = app.buttons["New alarm"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            add.tap()
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(task)
            app.buttons["Save"].tap()
            XCTAssertTrue(app.staticTexts[task].waitForExistence(timeout: 5), "\(task) should be saved")
        }
        XCTAssertEqual(rows.count, 3)

        app.buttons["New alarm"].tap()
        let limit = app.alerts.firstMatch
        XCTAssertTrue(limit.waitForExistence(timeout: 5), "A fourth alarm needs membership")
        limit.buttons["Not now"].tap()

        XCTAssertFalse(app.buttons["Save"].waitForExistence(timeout: 2), "No editor without membership")
        XCTAssertEqual(rows.count, 3, "Nothing was added")
    }

    func testBecomingAMemberAtTheLimitOpensTheNewAlarm() {
        launch(["-free"])   // the four sample alarms: already over the free limit
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 4, "Alarms over the limit are all kept")

        app.buttons["New alarm"].tap()
        let limit = app.alerts.firstMatch
        XCTAssertTrue(limit.waitForExistence(timeout: 5))
        limit.buttons["Become a member"].tap()

        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5), "Once a member, the new alarm opens")
    }

    func testAMemberAddsAlarmsWithoutBeingAsked() {
        launch([])   // UI tests start as a member
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))

        app.buttons["New alarm"].tap()

        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    // MARK: Settings

    func testSettingsShowsTheFreePlanAndSubscribing() {
        launch(["-free"])
        openSettings()

        let plan = app.staticTexts["plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        XCTAssertEqual(plan.label, "Free")
        XCTAssertTrue(app.staticTexts["Up to 3 alarms"].exists)

        let subscribe = app.buttons["subscribe"]
        XCTAssertTrue(subscribe.exists, "Free users are offered membership")
        XCTAssertTrue(subscribe.label.contains("$6.00 a year"), "With its price: \(subscribe.label)")
        subscribe.tap()

        expectation(for: NSPredicate(format: "label == 'Member'"), evaluatedWith: plan)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["subscribe"].exists, "A member is not offered it again")
    }

    func testAMemberSeesTheirPlanAndCanManageIt() {
        launch([])
        openSettings()

        let plan = app.staticTexts["plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        XCTAssertEqual(plan.label, "Member")
        XCTAssertTrue(app.staticTexts["Unlimited alarms"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Manage subscription'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["subscribe"].exists)
    }
}
