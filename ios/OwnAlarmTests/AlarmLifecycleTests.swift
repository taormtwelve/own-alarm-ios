import XCTest
@testable import OwnAlarm

/// What happens to an alarm after it rings: a one-shot switches off once the user
/// stops it, stays on through a snooze, and a repeating alarm never switches off.
@MainActor
final class AlarmLifecycleTests: XCTestCase {

    private var spy: SpyScheduler!
    private var store: AlarmStore!

    override func setUp() {
        super.setUp()
        spy = SpyScheduler()
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = AlarmStore(scheduler: spy,
                           fileURL: folder.appendingPathComponent("alarms.json"),
                           defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testAOneShotSwitchesOffOnceItHasRungAndBeenStopped() {
        let alarm = oneShot()
        store.add(alarm)

        store.alarmFinished(alarm.id)

        XCTAssertEqual(store.alarm(withID: alarm.id)?.isEnabled, false)
    }

    func testARepeatingAlarmStaysOnAfterRinging() {
        var alarm = oneShot()
        alarm.repeatDays = [.monday, .thursday]
        store.add(alarm)

        store.alarmFinished(alarm.id)

        XCTAssertEqual(store.alarm(withID: alarm.id)?.isEnabled, true)
    }

    func testSnoozingAOneShotKeepsItOn() {
        let alarm = oneShot()
        store.add(alarm)

        store.snooze(alarm)

        XCTAssertEqual(store.alarm(withID: alarm.id)?.isEnabled, true,
                       "A snoozed alarm rings again, so it must stay on")
    }

    func testTheSystemReportingAFinishedAlarmReachesTheStore() {
        let alarm = oneShot()
        store.add(alarm)

        spy.onFinished?(alarm.id)

        let switchedOff = NSPredicate { _, _ in
            self.store.alarm(withID: alarm.id)?.isEnabled == false
        }
        expectation(for: switchedOff, evaluatedWith: nil)
        waitForExpectations(timeout: 2)
    }

    private func oneShot() -> Alarm {
        Alarm(task: "Once", hour: 7, minute: 0, repeatDays: [],
              volume: 0.5, overridesSilent: true, toneID: "siren")
    }
}
