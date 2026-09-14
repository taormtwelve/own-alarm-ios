import XCTest
@testable import OwnAlarm

/// In-app playback: previews and live slider feedback — the real alarm's own sound
/// at the Ringer & Alerts volume — the alarm ringing in the app, and what happens
/// when the app leaves the screen.
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
    /// playback, and the test says so rather than failing. A preview shows it by
    /// its first chunk ending the instant it starts, so give that a moment.
    private func requirePlayback() throws {
        try XCTSkipIf(player.playingToneID == nil, "No audio output available on this machine")
        let moment = expectation(description: "first chunk under way")
        moment.isInverted = true
        wait(for: [moment], timeout: 0.25)
        try XCTSkipIf(player.previewMuted || player.playingToneID == nil,
                      "No audio output available on this machine")
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

    // MARK: Following the slider

    func testSliderFeedbackMovesToWhereTheFingerSettles() throws {
        player.beginScrub(siren, at: 0.8)
        try requirePlayback()
        XCTAssertEqual(player.previewPercent, 80)

        player.scrub(to: 0.5)   // the next chunk picks it up
        XCTAssertEqual(player.previewTargetPercent, 50)

        let moved = NSPredicate { _, _ in self.player.previewPercent == 50 }
        expectation(for: moved, evaluatedWith: nil)
        waitForExpectations(timeout: ScaledSound.previewChunkSeconds * 3 + 1)
    }

    func testLettingGoPlaysTheLevelItLetGoAt() throws {
        player.beginScrub(siren, at: 0.8)
        try requirePlayback()
        player.scrub(to: 0.4)

        player.endScrub()

        XCTAssertEqual(player.previewTargetPercent, 40, "The last level is the one chosen")
        XCTAssertEqual(player.playingToneID, "siren", "It rings on for a moment rather than being cut off")
        let heard = NSPredicate { _, _ in self.player.previewPercent == 40 }
        expectation(for: heard, evaluatedWith: nil)
        waitForExpectations(timeout: ScaledSound.previewChunkSeconds + 0.9)
    }

    func testSwitchingToneMidDragPlaysTheNewToneFromItsStart() throws {
        let bell = AlarmTone.tone(id: "soft-bell", in: AlarmTone.bundled)
        player.beginScrub(siren, at: 0.5)
        try requirePlayback()

        player.stopPreviews()
        player.beginScrub(bell, at: 0.5)

        XCTAssertEqual(player.playingToneID, "soft-bell", "The tone last chosen is the one previewed")
    }

    // MARK: The phone's volume

    func testDraggingNeverTouchesThePhonesMediaVolume() throws {
        let phone = FakeVolume(0.3)
        let player = AlarmPlayer(system: .fake(phone, defaults: UserDefaults(suiteName: UUID().uuidString)!))
        defer { player.stop() }

        player.beginScrub(siren, at: 0.8)
        try XCTSkipIf(player.playingToneID == nil, "No audio output available on this machine")
        player.scrub(to: 0.5)
        player.endScrub()

        XCTAssertEqual(phone.level, 0.3, accuracy: 0.001,
                       "Previews play at the Ringer & Alerts volume, as the real alarm does")
    }

    func testAPreviewLeavesThePhonesMediaVolumeAlone() throws {
        let phone = FakeVolume(0.3)
        let player = AlarmPlayer(system: .fake(phone, defaults: UserDefaults(suiteName: UUID().uuidString)!))
        defer { player.stop() }

        player.preview(siren, at: 0.9)
        try XCTSkipIf(player.playingToneID == nil, "No audio output available on this machine")

        XCTAssertEqual(phone.level, 0.3, accuracy: 0.001)
    }

    func testNothingIsReportedMutedBeforeAnythingHasPlayed() {
        XCTAssertFalse(player.previewMuted)
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
        XCTAssertEqual(phone.level, 0.3, accuracy: 0.001, "Media volume never moved")
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
