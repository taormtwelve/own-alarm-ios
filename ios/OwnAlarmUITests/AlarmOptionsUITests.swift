import XCTest

/// The per-alarm options and the behaviour added after the first release: the snooze
/// and vibrate switches, sound choice, remembered volume, the test ring, and the
/// Silent override.
final class AlarmOptionsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()
    }

    private var onIOS26: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    }

    private func beginning(with prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }

    private func openMorningRun() {
        let row = app.staticTexts["Morning run"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
    }

    // MARK: Repeat days

    func testTheWholeWeekSitsOnOneLine() {
        openMorningRun()

        // Day pills are labelled with the short day names; nothing else in the
        // editor or the list behind it uses those exact labels.
        let days = app.buttons.matching(NSPredicate(format: "label IN %@", Calendar.current.shortWeekdaySymbols))
        XCTAssertEqual(days.count, 7, "One pill per day")
        let lines = Set((0..<days.count).map { Int(days.element(boundBy: $0).frame.midY.rounded()) })
        XCTAssertEqual(lines.count, 1, "Sun–Sat should share one line, not wrap")
    }

    // MARK: Snooze

    func testSnoozeSwitchShowsAndHidesTheLength() {
        openMorningRun()
        // The snooze card sits below a tall volume card; two swipes reach it on
        // every simulator size, and a swipe past the end does no harm.
        app.swipeUp()
        app.swipeUp()

        let snooze = app.switches["Snooze"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 5))
        XCTAssertEqual(snooze.value as? String, "1", "The sample alarm snoozes")
        XCTAssertTrue(app.staticTexts["Snooze length"].exists)

        snooze.tap()
        XCTAssertEqual(snooze.value as? String, "0")
        XCTAssertFalse(app.staticTexts["Snooze length"].exists)

        snooze.tap()
        XCTAssertTrue(app.staticTexts["Snooze length"].waitForExistence(timeout: 2))
    }

    // MARK: Remembering choices

    func testANewAlarmStartsFromTheLastSavedVolume() {
        app.buttons["New alarm"].tap()
        let readout = app.staticTexts["volumeReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        XCTAssertEqual(readout.label, "50%", "Factory default")

        app.sliders["Alarm volume"].adjust(toNormalizedSliderPosition: 0.2)
        let chosen = readout.label
        XCTAssertNotEqual(chosen, "50%")
        app.buttons["Save"].tap()

        app.buttons["New alarm"].tap()
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        XCTAssertEqual(readout.label, chosen, "The next alarm starts where the last one was saved")
    }

    // MARK: Sound

    func testChoosingASoundUpdatesTheAlarm() {
        openMorningRun()
        let soundRow = app.buttons["soundRow"]
        XCTAssertTrue(soundRow.waitForExistence(timeout: 5), "The editor should have a Sound row")
        XCTAssertTrue(soundRow.label.contains("Siren"), "Sound row reads: \(soundRow.label)")

        // Taps the row's centre — the empty gap between title and value — which is
        // exactly where a row without a full-width hit area would ignore the tap.
        soundRow.tap()
        XCTAssertTrue(app.navigationBars["Sound & loudness"].waitForExistence(timeout: 5),
                      "Tapping anywhere on the Sound row should open the sound picker")

        let whisper = app.buttons["tone.whisper"]
        XCTAssertTrue(whisper.waitForExistence(timeout: 5), "The picker should list Whisper")
        whisper.tap()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The picker should have a Done button")
        done.tap()

        XCTAssertTrue(soundRow.waitForExistence(timeout: 5), "Should be back in the editor")
        XCTAssertTrue(soundRow.label.contains("Whisper"), "Sound row reads: \(soundRow.label)")
    }

    // MARK: Hearing the level for real

    private var testRing: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Test real alarm'")).firstMatch
    }

    func testTheEditorOffersToRingTheRealAlarmAtItsLevel() {
        openMorningRun()

        XCTAssertTrue(testRing.waitForExistence(timeout: 5), "The editor should offer a test ring")
        XCTAssertTrue(testRing.label.contains("85%"), "At this alarm's level: \(testRing.label)")

        testRing.tap()

        // Launched without -ringAllowed, the app's stand-in scheduler says nothing may
        // ring, whatever the simulator allows: the screen must say so rather than
        // count down to silence.
        XCTAssertTrue(beginning(with: "Nothing can ring yet").waitForExistence(timeout: 10),
                      "Without permission the screen says nothing can ring")
        XCTAssertTrue(testRing.exists, "Blocked: the offer stays")
        XCTAssertFalse(app.buttons["Cancel test"].exists, "No countdown to a ring that cannot come")
    }

    func testWithPermissionTheTestRingCountsDownAndCanBeCalledOff() {
        app.terminate()
        app.launchArguments = ["-uitesting", "-ringAllowed"]
        app.launch()
        openMorningRun()
        XCTAssertTrue(testRing.waitForExistence(timeout: 5))

        testRing.tap()

        let cancel = app.buttons["Cancel test"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "The ring is on its way and can be called off")
        XCTAssertTrue(beginning(with: "Rings in").exists, "…with a countdown to when it rings")
        cancel.tap()

        // Back to the offer: at once when cancelled, or when a countdown ends if the
        // tap came late and started another. Either way nothing is left counting down.
        XCTAssertTrue(testRing.waitForExistence(timeout: 10), "Called off: back to the offer")
        XCTAssertFalse(beginning(with: "Nothing can ring yet").exists, "Allowed, so never blocked")
    }

    func testTheSoundsTabOffersToRingTheChosenToneForReal() {
        app.tabBars.buttons["Sounds"].tap()

        XCTAssertTrue(testRing.waitForExistence(timeout: 10))
        XCTAssertTrue(testRing.label.contains("50%"), "At the test level, 50% to start: \(testRing.label)")
        XCTAssertFalse(app.buttons["Play test tone"].exists, "No live preview any more")
    }

    func testTappingAToneInTheSoundsTabPicksIt() {
        app.tabBars.buttons["Sounds"].tap()
        let marimba = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Marimba'")).firstMatch
        XCTAssertTrue(marimba.waitForExistence(timeout: 10))

        marimba.tap()

        XCTAssertTrue(marimba.isSelected, "The tone tapped is the one the test ring will use")
    }

    // MARK: Ringing through Silent

    func testOverrideSilentIsOfferedWhileAlarmsGoThroughNotifications() {
        openMorningRun()
        app.swipeUp()

        // Positive control first: the test button shares the card, so the switch's
        // presence is about the switch, not a wrong screen.
        XCTAssertTrue(testRing.waitForExistence(timeout: 5), "Should be looking at the volume card")

        // UI tests never grant the Alarms permission, so even on iOS 26 alarms go
        // through notifications here — where Silent matters — and the switch shows.
        let override = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Override Silent'")).firstMatch
        XCTAssertTrue(override.waitForExistence(timeout: 5))
    }

    func testSettingsNamesThePermissionThatMatters() {
        app.tabBars.buttons["Settings"].tap()

        let name = onIOS26 ? "Alarms permission" : "Critical Alerts permission"
        XCTAssertTrue(beginning(with: name).waitForExistence(timeout: 10))
        XCTAssertFalse(beginning(with: "Louder after each snooze").exists, "Removed on every iOS")
    }

    // MARK: Vibration

    func testVibrateIsOnForANewAlarmAndCanBeSwitchedOff() {
        app.buttons["New alarm"].tap()
        app.swipeUp()

        let vibrate = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Vibrate'")).firstMatch
        XCTAssertTrue(vibrate.waitForExistence(timeout: 5), "The editor should offer Vibrate")
        XCTAssertEqual(vibrate.value as? String, "1", "New alarms vibrate unless told otherwise")

        vibrate.tap()

        XCTAssertEqual(vibrate.value as? String, "0")
    }

    // MARK: Theme

    func testThemeChoiceSticksAcrossTabs() {
        app.tabBars.buttons["Settings"].tap()
        let dark = app.buttons["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 10))

        dark.tap()
        app.tabBars.buttons["Alarms"].tap()
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Dark"].isSelected)
    }
}
