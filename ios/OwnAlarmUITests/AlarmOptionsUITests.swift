import XCTest

/// The per-alarm options and the behaviour added after the first release: snooze
/// and fade-in switches, sound choice, remembered volume, previews stopping when the
/// app leaves the screen, and what iOS 26 hides.
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
        XCTAssertTrue(soundRow.waitForExistence(timeout: 5))
        XCTAssertTrue(soundRow.label.contains("Siren"))

        soundRow.tap()
        let whisper = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Whisper'")).firstMatch
        XCTAssertTrue(whisper.waitForExistence(timeout: 5))
        whisper.tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(soundRow.waitForExistence(timeout: 5))
        XCTAssertTrue(soundRow.label.contains("Whisper"), "got \(soundRow.label)")
    }

    // MARK: Leaving the app

    func testLeavingTheAppStopsAPreviewAtOnce() throws {
        app.tabBars.buttons["Sounds"].tap()
        let play = app.buttons["Play test tone"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))

        play.tap()
        guard app.buttons["Stop test tone"].waitForExistence(timeout: 3) else {
            throw XCTSkip("No audio output available on this machine")
        }

        let left = Date()
        XCUIDevice.shared.press(.home)
        app.activate()
        // A preview ends on its own after 6 s; a slower round trip proves nothing.
        try XCTSkipIf(Date().timeIntervalSince(left) > 5, "Round trip too slow to prove anything")

        XCTAssertTrue(app.buttons["Play test tone"].waitForExistence(timeout: 5),
                      "The preview should have stopped when the app left the screen")
    }

    // MARK: iOS 26

    func testOverrideSilentIsHiddenWhereAlarmsAlwaysRingThroughSilent() {
        openMorningRun()
        app.swipeUp()

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
}
