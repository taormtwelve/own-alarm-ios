import XCTest

/// Drives the real app in the Simulator. Launched with `-uitesting`, so the store is
/// throwaway and seeded with the starter alarms every run.
final class AlarmFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()
    }

    // MARK: Getting around

    func testTheThreeTabsExist() {
        XCTAssertTrue(app.tabBars.buttons["Alarms"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Sounds"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    func testTheAlarmListShowsTheSeededAlarms() {
        XCTAssertTrue(app.staticTexts["Morning run"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Take medication"].exists)
        XCTAssertGreaterThanOrEqual(
            app.descendants(matching: .any).matching(identifier: "alarmRow").count, 3
        )
    }

    /// The whole premise: two alarms, two different volumes, both visible at a glance.
    func testDifferentAlarmsShowDifferentVolumes() {
        XCTAssertTrue(app.staticTexts["85%"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["30%"].exists)
    }

    // MARK: The clock setting

    func testSwitchingToTwelveHourChangesEveryTimeOnTheList() {
        XCTAssertTrue(app.staticTexts["13:15"].waitForExistence(timeout: 10),
                      "24-hour is the default, so an afternoon alarm reads 13:15")

        app.tabBars.buttons["Settings"].tap()
        let amPm = app.buttons["AM / PM"]
        XCTAssertTrue(amPm.waitForExistence(timeout: 5))
        amPm.tap()

        app.tabBars.buttons["Alarms"].tap()

        let meridiem = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'PM' OR label CONTAINS[c] 'AM'")
        )
        XCTAssertGreaterThan(meridiem.count, 0, "Expected AM/PM times after switching")
        XCTAssertFalse(app.staticTexts["13:15"].exists, "13:15 should no longer appear")
    }

    // MARK: Creating an alarm

    func testCreatingAnAlarmAddsItToTheList() {
        app.buttons["New alarm"].tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Feed the cat")

        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Feed the cat"].waitForExistence(timeout: 5))
    }

    func testCancellingLeavesTheListAlone() {
        let before = app.descendants(matching: .any).matching(identifier: "alarmRow").count

        app.buttons["New alarm"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "alarmRow").count, before)
    }

    // MARK: Editing

    func testOpeningAnAlarmShowsItsVolume() {
        app.staticTexts["Morning run"].tap()
        XCTAssertTrue(app.staticTexts["Volume for this task"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["85%"].exists)
    }

    func testTheVolumeSliderIsReachableAndAdjustable() {
        app.staticTexts["Morning run"].tap()

        let slider = app.sliders["Alarm volume"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.5)

        // Any change is enough; the exact percentage depends on slider geometry.
        XCTAssertFalse(app.staticTexts["85%"].exists, "Volume should have moved off 85%")
    }

    // MARK: Sounds tab

    func testSoundsTabListsTheBundledTones() {
        app.tabBars.buttons["Sounds"].tap()

        XCTAssertTrue(app.staticTexts["Siren"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Marimba"].exists)
        XCTAssertTrue(app.staticTexts["Soft bell"].exists)
        XCTAssertTrue(app.staticTexts["Whisper"].exists)
    }

    // MARK: Settings

    func testSettingsExposesTheDefaultsAndTheThemeSwitch() {
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["Time format"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Show on Lock Screen"].exists)
        XCTAssertTrue(app.buttons["Dark"].exists)
        XCTAssertTrue(app.buttons["Light"].exists)
    }

    func testTurningOffLockScreenAlertsSticksAcrossTabs() {
        app.tabBars.buttons["Settings"].tap()

        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let before = toggle.value as? String
        toggle.tap()

        app.tabBars.buttons["Alarms"].tap()
        app.tabBars.buttons["Settings"].tap()

        XCTAssertNotEqual(app.switches.firstMatch.value as? String, before)
    }
}
