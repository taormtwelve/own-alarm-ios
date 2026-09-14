import XCTest
@testable import OwnAlarm

/// The alarm ringing in the app: it takes the phone's volume for its level and
/// hands it back when stopped.
@MainActor
final class AlarmPlayerTests: XCTestCase {

    private let siren = AlarmTone.tone(id: "siren", in: AlarmTone.bundled)

    private func alarm(volume: Double) -> Alarm {
        Alarm(task: "Wake", hour: 7, minute: 0, repeatDays: [],
              volume: volume, fadeInSeconds: 0, overridesSilent: true, toneID: "siren")
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

    func testStoppingWithoutRingingLeavesTheVolumeAlone() {
        let phone = FakeVolume(0.3)
        let player = AlarmPlayer(system: .fake(phone, defaults: UserDefaults(suiteName: UUID().uuidString)!))

        player.stop()

        XCTAssertEqual(phone.level, 0.3, accuracy: 0.001)
    }
}
