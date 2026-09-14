import XCTest
@testable import OwnAlarm

/// Buzzing while an alarm rings in the app. The motor is replaced by a counter, so
/// these run on any machine — no audio output or real phone needed.
@MainActor
final class VibrationTests: XCTestCase {

    private final class Counter { var buzzes = 0 }

    private let siren = AlarmTone.tone(id: "siren", in: AlarmTone.bundled)

    private func makePlayer(_ counter: Counter) -> AlarmPlayer {
        AlarmPlayer(system: .fake(FakeVolume(0.5), defaults: UserDefaults(suiteName: UUID().uuidString)!),
                    vibrate: { counter.buzzes += 1 })
    }

    private func alarm(vibrates: Bool) -> Alarm {
        var alarm = Alarm(task: "Wake", hour: 7, minute: 0, repeatDays: [],
                          volume: 0.4, overridesSilent: true, toneID: "siren")
        alarm.vibrates = vibrates
        return alarm
    }

    /// Lets the run loop go for a while, so a repeating timer gets its chance to fire.
    private func waitAWhile(_ seconds: TimeInterval) {
        let nothing = expectation(description: "time passes")
        nothing.isInverted = true
        wait(for: [nothing], timeout: seconds)
    }

    func testARingingAlarmBuzzesAtOnceAndKeepsBuzzing() {
        let counter = Counter()
        let player = makePlayer(counter)
        defer { player.stop() }

        player.startRinging(alarm(vibrates: true), tone: siren)
        XCTAssertEqual(counter.buzzes, 1, "It buzzes straight away")

        let again = NSPredicate { _, _ in counter.buzzes >= 2 }
        expectation(for: again, evaluatedWith: nil)
        waitForExpectations(timeout: AlarmPlayer.vibrationInterval + 2)
    }

    func testStoppingTheAlarmStopsTheBuzzing() {
        let counter = Counter()
        let player = makePlayer(counter)

        player.startRinging(alarm(vibrates: true), tone: siren)
        player.stop()
        let afterStop = counter.buzzes

        waitAWhile(AlarmPlayer.vibrationInterval + 0.5)
        XCTAssertEqual(counter.buzzes, afterStop, "No buzz after Stop")
    }

    func testAnAlarmSetNotToVibrateNeverBuzzes() {
        let counter = Counter()
        let player = makePlayer(counter)
        defer { player.stop() }

        player.startRinging(alarm(vibrates: false), tone: siren)

        waitAWhile(AlarmPlayer.vibrationInterval + 0.5)
        XCTAssertEqual(counter.buzzes, 0)
    }

    func testSwitchingVibrateOnGivesOneBuzz() {
        let counter = Counter()
        let player = makePlayer(counter)

        player.buzzOnce()

        XCTAssertEqual(counter.buzzes, 1)
    }
}
