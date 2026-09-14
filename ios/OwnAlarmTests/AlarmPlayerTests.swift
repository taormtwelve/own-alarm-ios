import XCTest
@testable import OwnAlarm

/// The alarm ringing in the app: it takes the phone's volume for its level and
/// hands it back when stopped.
@MainActor
final class AlarmPlayerTests: XCTestCase {

    private let siren = AlarmTone.tone(id: "siren", in: AlarmTone.bundled)

    private func alarm(volume: Double) -> Alarm {
        Alarm(task: "Wake", hour: 7, minute: 0, repeatDays: [],
              volume: volume, overridesSilent: true, toneID: "siren")
    }

    func testRingingReportsTheToneAndStopClearsIt() throws {
        let player = AlarmPlayer(system: .fake(FakeVolume(0.5), defaults: UserDefaults(suiteName: UUID().uuidString)!))
        defer { player.stop() }

        player.startRinging(alarm(volume: 0.4), tone: siren)
        // CI machines can lack an audio device; then nothing can be proved.
        try XCTSkipIf(player.playingToneID == nil, "No audio output available on this machine")
        XCTAssertEqual(player.playingToneID, "siren")

        player.stop()
        XCTAssertNil(player.playingToneID)
    }

    func testARingingAlarmHoldsItsVolumeUntilStopped() throws {
        let phone = FakeVolume(0.3)
        let player = AlarmPlayer(system: .fake(phone, defaults: UserDefaults(suiteName: UUID().uuidString)!))
        defer { player.stop() }

        player.startRinging(alarm(volume: 0.9), tone: siren)
        try XCTSkipIf(player.playingToneID == nil, "No audio output available on this machine")
        XCTAssertEqual(phone.level, 0.9, accuracy: 0.001, "The phone is set to the alarm's level")

        player.stop()
        XCTAssertEqual(phone.level, 0.3, accuracy: 0.001, "Stopped: the user's volume is back")
    }

    // MARK: Picking a tone

    private let bell = AlarmTone.tone(id: "soft-bell", in: AlarmTone.bundled)

    func testPickingAToneOnlyPreviewsItAsMedia() throws {
        let phone = FakeVolume(0.3)
        let player = AlarmPlayer(system: .fake(phone, defaults: UserDefaults(suiteName: UUID().uuidString)!))
        defer { player.stop() }

        player.preview(siren)
        try XCTSkipIf(player.previewingToneID == nil, "No audio output available on this machine")

        XCTAssertEqual(player.previewingToneID, "siren")
        XCTAssertNil(player.playingToneID, "A preview is not an alarm")
        XCTAssertEqual(phone.level, 0.3, accuracy: 0.001, "The media volume as it is, never changed")

        player.stopPreview()
        XCTAssertNil(player.previewingToneID)
    }

    func testPickingAnotherToneReplacesThePreview() throws {
        let player = AlarmPlayer(system: .fake(FakeVolume(0.5), defaults: UserDefaults(suiteName: UUID().uuidString)!))
        defer { player.stop() }

        player.preview(siren)
        try XCTSkipIf(player.previewingToneID == nil, "No audio output available on this machine")
        player.preview(bell)

        XCTAssertEqual(player.previewingToneID, "soft-bell", "Only the tone picked last plays")
    }

    func testAPreviewStopsByItself() throws {
        let player = AlarmPlayer(system: .fake(FakeVolume(0.5), defaults: UserDefaults(suiteName: UUID().uuidString)!))
        defer { player.stop() }

        player.preview(siren)
        try XCTSkipIf(player.previewingToneID == nil, "No audio output available on this machine")

        let stopped = NSPredicate { _, _ in player.previewingToneID == nil }
        expectation(for: stopped, evaluatedWith: nil)
        waitForExpectations(timeout: AlarmPlayer.previewSeconds + 2)
    }

    func testAPreviewNeitherPlaysOverNorStopsARingingAlarm() throws {
        let player = AlarmPlayer(system: .fake(FakeVolume(0.5), defaults: UserDefaults(suiteName: UUID().uuidString)!))
        defer { player.stop() }
        player.startRinging(alarm(volume: 0.4), tone: siren)
        try XCTSkipIf(player.playingToneID == nil, "No audio output available on this machine")

        player.preview(bell)
        XCTAssertNil(player.previewingToneID, "No preview over a ringing alarm")

        player.stopPreview()   // what leaving a screen or tab does
        XCTAssertEqual(player.playingToneID, "siren", "Leaving a screen must not silence an alarm")
    }

    func testStoppingWithoutRingingLeavesTheVolumeAlone() {
        let phone = FakeVolume(0.3)
        let player = AlarmPlayer(system: .fake(phone, defaults: UserDefaults(suiteName: UUID().uuidString)!))

        player.stop()

        XCTAssertEqual(phone.level, 0.3, accuracy: 0.001)
    }
}
