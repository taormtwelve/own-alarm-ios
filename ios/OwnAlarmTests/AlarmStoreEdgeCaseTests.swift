import XCTest
@testable import OwnAlarm

/// Corners of the store the main suite does not reach.
@MainActor
final class AlarmStoreEdgeCaseTests: XCTestCase {

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

    func testDeletingByListPositionRemovesExactlyThoseAlarms() {
        store.add(make(task: "Early", hour: 6))
        store.add(make(task: "Noon", hour: 12))
        store.add(make(task: "Late", hour: 22))
        let list = store.sortedAlarms

        store.delete(at: IndexSet([0, 2]), in: list)

        XCTAssertEqual(store.alarms.map(\.task), ["Noon"])
    }

    func testUpdatingAnAlarmThatNoLongerExistsDoesNothing() {
        store.update(make())
        XCTAssertTrue(store.alarms.isEmpty)
        XCTAssertTrue(spy.scheduled.isEmpty)
    }

    func testAnAlarmAddedSwitchedOffIsNeverScheduled() {
        var alarm = make()
        alarm.isEnabled = false

        store.add(alarm)

        XCTAssertTrue(spy.scheduled.isEmpty)
        XCTAssertEqual(store.enabledCount, 0)
    }

    func testEnabledCountFollowsTheSwitches() {
        store.add(make(hour: 6))
        store.add(make(hour: 7))
        XCTAssertEqual(store.enabledCount, 2)

        store.setEnabled(false, for: store.alarms[0])
        XCTAssertEqual(store.enabledCount, 1)
    }

    func testSnoozeSwitchedOffIsRememberedAndSwitchingOnUsesNineMinutes() {
        var alarm = make()
        alarm.snoozeMinutes = 0

        store.save(alarm, isNew: true)

        XCTAssertEqual(store.settings.defaults.snoozeMinutes, 0, "Next alarm starts with snooze off")
        XCTAssertEqual(store.settings.defaults.snoozeWhenSwitchedOn, 9)
    }

    func testLockScreenAndClockChoicesSurviveARelaunch() {
        // Two stores over the same storage: the second one is the app reopening.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("alarms.json")
        let suite = UserDefaults(suiteName: UUID().uuidString)!

        // Values that differ from the defaults, or a lost save would still "pass".
        let first = AlarmStore(scheduler: spy, fileURL: url, defaults: suite)
        first.settings.showOnLockScreen = false
        first.settings.timeFormat = .twelveHour

        let second = AlarmStore(scheduler: SpyScheduler(), fileURL: url, defaults: suite)
        XCTAssertFalse(second.settings.showOnLockScreen)
        XCTAssertEqual(second.settings.timeFormat, .twelveHour)
    }

    private func make(task: String = "Test", hour: Int = 7) -> Alarm {
        Alarm(task: task, hour: hour, minute: 0, repeatDays: [],
              volume: 0.5, overridesSilent: true, toneID: "siren")
    }
}
