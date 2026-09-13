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
        player = AlarmPlayer()
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
}
