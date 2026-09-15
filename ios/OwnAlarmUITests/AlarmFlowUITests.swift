import XCTest

/// Drives the real app in the Simulator. Launched with `-uitesting`, so the store is
/// throwaway and seeded with the four sample alarms every run.
///
/// Rule for this suite: never find something by text that also appears elsewhere on
/// screen — a sheet does not hide the list behind it from the query, so a check like
/// "85% exists" passes whether or not the sheet shows it. Use identifiers or labels
/// that exist in exactly one place.
final class AlarmFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()
    }

    private var rows: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "alarmRow")
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
        XCTAssertEqual(rows.count, 4, "One row per sample alarm")
    }

    /// The whole premise: two alarms, two different volumes, both visible at a glance.
    func testDifferentAlarmsShowDifferentVolumes() {
        XCTAssertTrue(app.staticTexts["85%"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["30%"].exists)
    }

    // MARK: The clock setting

    func testSwitchingToTwelveHourChangesEveryTimeOnTheList() {
        // The default follows the test phone's region, so pin 24-hour first.
        app.tabBars.buttons["Settings"].tap()
        let twentyFour = app.buttons["24-hour"]
        XCTAssertTrue(twentyFour.waitForExistence(timeout: 10))
        twentyFour.tap()
        app.tabBars.buttons["Alarms"].tap()
        XCTAssertTrue(app.staticTexts["13:15"].waitForExistence(timeout: 5),
                      "In 24-hour an afternoon alarm reads 13:15")

        app.tabBars.buttons["Settings"].tap()
        let amPm = app.buttons["AM / PM"]
        XCTAssertTrue(amPm.waitForExistence(timeout: 5))
        amPm.tap()

        app.tabBars.buttons["Alarms"].tap()

        // 13:15 becomes 1:15 PM. iOS puts a narrow no-break space before "PM", so the
        // parts are matched rather than the exact string.
        let afternoon = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH '1:15' AND label CONTAINS[c] 'PM'"))
        XCTAssertTrue(afternoon.firstMatch.waitForExistence(timeout: 5),
                      "The 13:15 alarm should now read 1:15 PM")
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
        XCTAssertEqual(rows.count, 5, "The new alarm joins the four samples")
    }

    func testCancellingLeavesTheListAlone() {
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        let before = rows.count

        app.buttons["New alarm"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        XCTAssertEqual(rows.count, before)
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
        XCTAssertEqual(rows.count, 0)
        XCTAssertTrue(app.buttons["Add an alarm"].exists)
    }

    // MARK: Editing

    func testOpeningAnAlarmShowsItsVolume() {
        app.staticTexts["Morning run"].tap()

        // The readout, not any "85%": the list behind the sheet shows 85% too.
        let readout = app.staticTexts["volumeReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5), "The editor should open")
        XCTAssertEqual(readout.label, "85%")
    }

    func testTheVolumeSliderIsReachableAndAdjustable() {
        app.staticTexts["Morning run"].tap()

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

        // Exact names: the alarm list only ever shows them inside longer summaries.
        XCTAssertTrue(app.staticTexts["Siren"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Marimba"].exists)
        XCTAssertTrue(app.staticTexts["Soft bell"].exists)
        XCTAssertTrue(app.staticTexts["Whisper"].exists)
        for name in ["Sunrise", "Music box", "Birdsong", "Chimes", "Sonar", "Beeps"] {
            XCTAssertTrue(app.staticTexts[name].exists, "\(name) should be listed")
        }
    }

    // MARK: Settings

    func testSettingsShowsClockLockScreenAndThemeControls() {
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["Time format"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["Show on Lock Screen"].exists)
        XCTAssertTrue(app.buttons["Dark"].exists)
        XCTAssertTrue(app.buttons["Light"].exists)
        // New-alarm defaults are learned from saved alarms, not set here.
        XCTAssertFalse(app.staticTexts["NEW ALARM DEFAULTS"].exists)
    }

    func testChoosingThaiTranslatesTheAppAndEnglishBringsItBack() {
        relaunch(languages: "(en, th)")   // a phone that lists Thai, English first
        app.tabBars.buttons["Settings"].tap()
        // The Language section is last; on a short phone it sits below the fold.
        app.swipeUp()
        let thai = app.buttons["ไทย"]
        XCTAssertTrue(thai.waitForExistence(timeout: 10), "Settings offers Thai")
        thai.tap()

        XCTAssertTrue(app.tabBars.buttons["การตั้งค่า"].waitForExistence(timeout: 5), "The tabs read Thai")
        XCTAssertTrue(app.staticTexts["รูปแบบเวลา"].exists, "So does Settings")

        app.tabBars.buttons["นาฬิกาปลุก"].tap()
        XCTAssertTrue(app.staticTexts["ทุกวัน"].waitForExistence(timeout: 5),
                      "The every-day sample alarm's repeat line, in Thai")

        app.tabBars.buttons["การตั้งค่า"].tap()
        app.swipeUp()
        let english = app.buttons["English"]
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        english.tap()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5), "Back in English")
    }

    func testWithoutThaiOnThePhoneThereIsNoLanguageChoice() {
        relaunch(languages: "(en)")
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Time format"].waitForExistence(timeout: 10))
        app.swipeUp()

        XCTAssertFalse(app.buttons["ไทย"].exists, "No Thai on the phone: nothing to choose")
        XCTAssertFalse(app.buttons["English"].exists)
    }

    /// Restarts the app as if the phone's language list were `languages`, e.g. "(en, th)".
    private func relaunch(languages: String) {
        app.terminate()
        app.launchArguments = ["-uitesting", "-AppleLanguages", languages]
        app.launch()
    }

    func testTurningOffLockScreenAlertsSticksAcrossTabs() {
        app.tabBars.buttons["Settings"].tap()

        // By name: "the first switch" could be an alarm's switch on the list tab.
        let toggle = app.switches["Show on Lock Screen"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "1", "On by default")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")

        app.tabBars.buttons["Alarms"].tap()
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0", "The choice should stick")
    }
}
