import XCTest
import UserNotifications
@testable import OwnAlarm

/// The Lock Screen notification's buttons (iOS 16–25) and what they do to an alarm.
@MainActor
final class NotificationResponseTests: XCTestCase {

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

    // MARK: Mapping

    func testEachActionMeansWhatItSays() {
        XCTAssertEqual(AlarmResponse(actionIdentifier: AlarmScheduler.snoozeAction), .snooze)
        XCTAssertEqual(AlarmResponse(actionIdentifier: AlarmScheduler.stopAction), .stop)
        XCTAssertEqual(AlarmResponse(actionIdentifier: UNNotificationDismissActionIdentifier), .stop)
        XCTAssertEqual(AlarmResponse(actionIdentifier: UNNotificationDefaultActionIdentifier), .open)
        XCTAssertEqual(AlarmResponse(actionIdentifier: nil), .open,
                       "An alarm firing while the app is open shows the ringing screen")
    }

    // MARK: Effects

    func testTappingTheNotificationOpensTheRingingScreen() {
        let alarm = oneShot()
        store.add(alarm)

        store.respond(.open, toAlarmWithID: alarm.id)

        XCTAssertEqual(store.ringing?.id, alarm.id)
    }

    func testSnoozeSchedulesTheSnoozeAndKeepsTheAlarmOn() {
        let alarm = oneShot()
        store.add(alarm)
        store.ringing = alarm

        store.respond(.snooze, toAlarmWithID: alarm.id)

        XCTAssertEqual(spy.snoozed.last?.alarm.id, alarm.id)
        XCTAssertNil(store.ringing, "The ringing screen closes")
        XCTAssertEqual(store.alarm(withID: alarm.id)?.isEnabled, true)
    }

    func testStopSwitchesAOneShotOff() {
        let alarm = oneShot()
        store.add(alarm)

        store.respond(.stop, toAlarmWithID: alarm.id)

        XCTAssertEqual(store.alarm(withID: alarm.id)?.isEnabled, false)
        XCTAssertTrue(spy.cancelledSnoozes.contains { $0.id == alarm.id })
    }

    func testStopLeavesARepeatingAlarmOn() {
        var alarm = oneShot()
        alarm.repeatDays = [.friday]
        store.add(alarm)

        store.respond(.stop, toAlarmWithID: alarm.id)

        XCTAssertEqual(store.alarm(withID: alarm.id)?.isEnabled, true)
    }

    func testAResponseForAnAlarmDeletedSinceIsIgnored() {
        store.respond(.open, toAlarmWithID: UUID())
        XCTAssertNil(store.ringing)
        XCTAssertTrue(spy.snoozed.isEmpty)
    }

    private func oneShot() -> Alarm {
        Alarm(task: "Once", hour: 7, minute: 0, repeatDays: [],
              volume: 0.5, overridesSilent: true, toneID: "siren")
    }
}
