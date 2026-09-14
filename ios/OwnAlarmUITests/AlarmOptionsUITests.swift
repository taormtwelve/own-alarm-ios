import XCTest

/// The per-alarm options and the behaviour added after the first release: snooze
/// and fade-in switches, sound choice, remembered volume, the test ring, and what
/// iOS 26 hides.
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

    // MARK: Fade-in

    func testFadeInStartsOffOnANewAlarmAndOpensAtTenSeconds() {
        app.buttons["New alarm"].tap()
        app.swipeUp()

        let fade = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Fade in'")).firstMatch
        XCTAssertTrue(fade.waitForExistence(timeout: 5))
        XCTAssertEqual(fade.value as? String, "0", "Fade-in starts off")

        fade.tap()

        XCTAssertEqual(fade.value as? String, "1")
        XCTAssertTrue(beginning(with: "Fade over 10").waitForExistence(timeout: 2))
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

        let cancel = app.buttons["Cancel test"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3), "While the ring is on its way it can be cancelled")
        XCTAssertTrue(beginning(with: "Rings in").exists, "…and a countdown says when")
        cancel.tap()
        XCTAssertTrue(testRing.waitForExistence(timeout: 3), "Cancelled: back to the offer")
    }

    func testTheSoundsTabOffersToRingTheChosenToneForReal() {
        app.tabBars.buttons["Sounds"].tap()

        XCTAssertTrue(testRing.waitForExistence(timeout: 10))
        XCTAssertTrue(testRing.label.contains("50%"), "At the test level, 50% to start: \(testRing.label)")
        XCTAssertFalse(app.buttons["Play test tone"].exists, "No live preview any more")
    }

    // MARK: iOS 26

    func testOverrideSilentIsHiddenWhereAlarmsAlwaysRingThroughSilent() {
        openMorningRun()
        app.swipeUp()

        // Positive control first: the Fade in switch shares the card, so if it is
        // here, the override's absence means something rather than a wrong screen.
        let fade = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Fade in'")).firstMatch
        XCTAssertTrue(fade.waitForExistence(timeout: 5), "Should be looking at the volume card")

        let override = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Override Silent'")).firstMatch
        if onIOS26 {
            XCTAssertFalse(override.exists, "Every alarm rings through Silent on iOS 26")
        } else {
            XCTAssertTrue(override.waitForExistence(timeout: 5))
        }
    }

    func testSettingsNamesThePermissionThatMatters() {
        app.tabBars.buttons["Settings"].tap()

        let name = onIOS26 ? "Alarms permission" : "Critical Alerts permission"
        XCTAssertTrue(beginning(with: name).waitForExistence(timeout: 10))
        if onIOS26 {
            XCTAssertFalse(beginning(with: "Override Silent").exists)
        }
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
}
