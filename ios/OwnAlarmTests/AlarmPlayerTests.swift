import XCTest
@testable import OwnAlarm

/// In-app playback: previews, live slider feedback, and what happens when the app
/// leaves the screen.
@MainActor
final class AlarmPlayerTests: XCTestCase {

    private var player: AlarmPlayer!
    private let siren = AlarmTone.tone(id: "siren", in: AlarmTone.bundled)

    override func setUp() {
        super.setUp()
        // A pretend phone volume: tests must never move the machine's real one.
        player = AlarmPlayer(system: .fake(FakeVolume(0.5), defaults: UserDefaults(suiteName: UUID().uuidString)!))
    }

    override func tearDown() {
        player.stop()
        super.tearDown()
    }

    /// CI machines can lack an audio device; then nothing can be proved about
    /// playback, and the test says so rather than failing.
    private func requirePlayback() throws {
        try XCTSkipIf(player.playingToneID == nil, "No audio output available on this machine")
    }

    func testPreviewReportsWhatIsPlayingAndStopClearsIt() throws {
        player.preview(siren, at: 0.3)
        try requirePlayback()
        XCTAssertEqual(player.playingToneID, "siren")

        player.stop()
        XCTAssertNil(player.playingToneID)
    }

    func testLeavingTheAppStopsAPreviewImmediately() throws {
        player.preview(siren, at: 0.3)
        try requirePlayback()

        player.appDidLeaveForeground()

        XCTAssertNil(player.playingToneID)
    }

    func testLeavingTheAppStopsSliderFeedbackImmediately() throws {
        player.beginScrub(siren, at: 0.5)
        try requirePlayback()

        player.appDidLeaveForeground()

        XCTAssertNil(player.playingToneID)
    }

    func testLeavingTheAppDoesNotSilenceARingingAlarm() throws {
        let alarm = Alarm(task: "Wake", hour: 7, minute: 0, repeatDays: [],
                          volume: 0.4, fadeInSeconds: 0, overridesSilent: true, toneID: "siren")
        player.startRinging(alarm, tone: siren)
        try requirePlayback()

        player.appDidLeaveForeground()

        XCTAssertEqual(player.playingToneID, "siren", "Leaving the app must not silence an alarm")
    }

    func testSliderFeedbackStopsShortlyAfterTheFingerLifts() throws {
        player.beginScrub(siren, at: 0.5)
        try requirePlayback()
        player.scrub(to: 0.8)
        XCTAssertEqual(player.playingToneID, "siren", "Still playing while dragging")

        player.endScrub()

        let stopped = NSPredicate { _, _ in self.player.playingToneID == nil }
        expectation(for: stopped, evaluatedWith: nil)
        waitForExpectations(timeout: 3)
    }

    func testMovingASliderWithoutTouchingItPlaysNothing() {
        player.scrub(to: 0.9)
        XCTAssertNil(player.playingToneID)
    }

    // MARK: The phone's volume

    func testDraggingMovesThePhoneVolumeAndLettingGoPutsItBack() throws {
        let phone = FakeVolume(0.3)
        let player = AlarmPlayer(system: .fake(phone, defaults: UserDefaults(suiteName: UUID().uuidString)!))
        defer { player.stop() }

        player.beginScrub(siren, at: 0.8)
        try XCTSkipIf(player.playingToneID == nil, "No audio output available on this machine")
        XCTAssertEqual(phone.level, 0.8, accuracy: 0.001, "The phone follows the slider")

        player.scrub(to: 0.5)
        XCTAssertEqual(phone.level, 0.5, accuracy: 0.001)

        player.endScrub()
        let restored = NSPredicate { _, _ in abs(phone.level - 0.3) < 0.001 }
        expectation(for: restored, evaluatedWith: nil)
        waitForExpectations(timeout: 3)
    }

    func testLeavingTheAppPutsThePhoneVolumeBack() throws {
        let phone = FakeVolume(0.3)
        let player = AlarmPlayer(system: .fake(phone, defaults: UserDefaults(suiteName: UUID().uuidString)!))
        defer { player.stop() }

        player.preview(siren, at: 0.9)
        try XCTSkipIf(player.playingToneID == nil, "No audio output available on this machine")

        player.appDidLeaveForeground()

        XCTAssertEqual(phone.level, 0.3, accuracy: 0.001)
    }

    func testARingingAlarmHoldsItsVolumeUntilStopped() throws {
        let phone = FakeVolume(0.3)
        let player = AlarmPlayer(system: .fake(phone, defaults: UserDefaults(suiteName: UUID().uuidString)!))
        defer { player.stop() }
        let alarm = Alarm(task: "Wake", hour: 7, minute: 0, repeatDays: [],
                          volume: 0.9, fadeInSeconds: 0, overridesSilent: true, toneID: "siren")

        player.startRinging(alarm, tone: siren)
        try XCTSkipIf(player.playingToneID == nil, "No audio output available on this machine")
        XCTAssertEqual(phone.level, 0.9, accuracy: 0.001)

        player.appDidLeaveForeground()
        XCTAssertEqual(phone.level, 0.9, accuracy: 0.001, "Still ringing, still at its level")

        player.stop()
        XCTAssertEqual(phone.level, 0.3, accuracy: 0.001, "Stopped: the user's volume is back")
    }

    // MARK: Stopping previews

    func testStopPreviewsEndsAPreview() throws {
        player.preview(siren, at: 0.4)
        try requirePlayback()

        player.stopPreviews()

        XCTAssertNil(player.playingToneID)
    }

    func testStopPreviewsEndsSliderFeedback() throws {
        player.beginScrub(siren, at: 0.4)
        try requirePlayback()

        player.stopPreviews()   // e.g. the fade switch was touched

        XCTAssertNil(player.playingToneID)
        player.scrub(to: 0.9)
        XCTAssertNil(player.playingToneID, "A stopped drag must not restart on a stray value change")
    }

    func testStopPreviewsLeavesARingingAlarmAlone() throws {
        let alarm = Alarm(task: "Wake", hour: 7, minute: 0, repeatDays: [],
                          volume: 0.4, fadeInSeconds: 0, overridesSilent: true, toneID: "siren")
        player.startRinging(alarm, tone: siren)
        try requirePlayback()

        player.stopPreviews()

        XCTAssertEqual(player.playingToneID, "siren")
    }

    // MARK: A drag iOS cancelled

    func testASliderLeftAloneFallsSilentOnItsOwn() throws {
        // iOS can cancel a drag (a scroll takes it over) without the slider ever
        // reporting the finger lifting. The tone must not loop forever.
        let phone = FakeVolume(0.3)
        let player = AlarmPlayer(system: .fake(phone, defaults: UserDefaults(suiteName: UUID().uuidString)!))
        defer { player.stop() }

        player.beginScrub(siren, at: 0.8)
        try XCTSkipIf(player.playingToneID == nil, "No audio output available on this machine")

        let silent = NSPredicate { _, _ in player.playingToneID == nil }
        expectation(for: silent, evaluatedWith: nil)
        waitForExpectations(timeout: AlarmPlayer.scrubIdleTimeout + 2)
        XCTAssertEqual(phone.level, 0.3, accuracy: 0.001, "The user's volume comes back")
    }

    func testMovingTheSliderAgainAfterASilenceBringsTheSoundBack() throws {
        player.beginScrub(siren, at: 0.5)
        try requirePlayback()
        let silent = NSPredicate { _, _ in self.player.playingToneID == nil }
        expectation(for: silent, evaluatedWith: nil)
        waitForExpectations(timeout: AlarmPlayer.scrubIdleTimeout + 2)

        player.scrub(to: 0.6)

        XCTAssertEqual(player.playingToneID, "siren", "Still dragging: the sound resumes")
    }
}
