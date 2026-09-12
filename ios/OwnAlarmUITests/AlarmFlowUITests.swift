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

    // MARK: Saving

    func testSavingAnEditedAlarmTurnsItOn() {
        // The sample night alarm starts switched off.
        let toggle = app.switches["Wind down & charge phone alarm"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "0")

        app.staticTexts["Wind down & charge phone"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()

        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1", "Saving an edit should switch the alarm on")
    }

    // MARK: Deleting

    func testSwipingLeftRevealsDeleteAndRemovesTheAlarm() {
        let rows = app.descendants(matching: .any).matching(identifier: "alarmRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        let before = rows.count
        XCTAssertEqual(before, 4, "One element per alarm — the four sample alarms")

        // Rows sort by time, so the first is the 06:45 Morning run.
        rows.firstMatch.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Swiping left should reveal Delete")
        delete.tap()

        expectation(for: NSPredicate(format: "count == %d", before - 1), evaluatedWith: rows)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["Morning run"].exists, "The swiped alarm should be gone")
    }

    // MARK: First launch

    func testFirstLaunchShowsTheEmptyStateNotSampleAlarms() {
        app.terminate()
        app.launchArguments = ["-uitesting", "-emptyStore"]
        app.launch()

        XCTAssertTrue(app.staticTexts["No alarms yet"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "alarmRow").count, 0)
        XCTAssertTrue(app.buttons["Add an alarm"].exists)
    }

    // MARK: Editing

    func testOpeningAnAlarmShowsItsVolume() {
        app.staticTexts["Morning run"].tap()
        XCTAssertTrue(app.staticTexts["Volume for this task"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["85%"].exists)
    }

    func testTheVolumeSliderIsReachableAndAdjustable() {
        app.staticTexts["Morning run"].tap()

        // Query the readout by identifier: the list behind the sheet still carries
        // its own "85%" label, so matching on text alone proves nothing.
        let readout = app.staticTexts["volumeReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        let before = readout.label

        let slider = app.sliders["Alarm volume"]
        XCTAssertTrue(slider.exists)
        slider.adjust(toNormalizedSliderPosition: 0.25)

        XCTAssertNotEqual(readout.label, before, "Moving the slider should change the readout")
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
