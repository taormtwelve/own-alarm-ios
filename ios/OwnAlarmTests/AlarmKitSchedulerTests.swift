#if canImport(AlarmKit)
import AlarmKit
import XCTest
@testable import OwnAlarm

/// The AlarmKit route's fallbacks. Scheduling a real AlarmKit alarm needs the user's
/// permission, which a test run cannot grant, so these cover the paths that decide
/// *not* to use AlarmKit — the ones a wrong guard would silently break.
final class AlarmKitSchedulerTests: XCTestCase {

    private let tone = AlarmTone.tone(id: "siren", in: AlarmTone.bundled)

    func testWithoutPermissionAlarmsFallBackToNotifications() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit needs iOS 26") }
        try XCTSkipIf(AlarmManager.shared.authorizationState == .authorized,
                      "Only meaningful when alarms permission has not been granted")
        let spy = SpyScheduler()
        let scheduler = AlarmKitScheduler(fallback: spy, defaults: freshDefaults())
        let alarm = sample()

        scheduler.schedule(alarm, tone: tone, showOnLockScreen: true)

        XCTAssertEqual(spy.scheduled.last?.alarm.id, alarm.id)
    }

    func testHidingFromTheLockScreenAlwaysUsesNotifications() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit needs iOS 26") }
        // An AlarmKit alarm always appears on the Lock Screen, so "off" must go
        // through notifications, which can stay hidden.
        let spy = SpyScheduler()
        let scheduler = AlarmKitScheduler(fallback: spy, defaults: freshDefaults())

        scheduler.schedule(sample(), tone: tone, showOnLockScreen: false)

        XCTAssertEqual(spy.scheduled.last?.lockScreen, false)
    }

    func testCancellingAlsoClearsTheNotificationFallback() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit needs iOS 26") }
        let spy = SpyScheduler()
        let scheduler = AlarmKitScheduler(fallback: spy, defaults: freshDefaults())
        let alarm = sample()

        scheduler.cancel(alarm)

        XCTAssertTrue(spy.cancelled.contains { $0.id == alarm.id })
    }

    func testSnoozeOutsideAlarmKitGoesThroughNotifications() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit needs iOS 26") }
        let spy = SpyScheduler()
        let scheduler = AlarmKitScheduler(fallback: spy, defaults: freshDefaults())

        scheduler.scheduleSnooze(sample(), minutes: 5)

        XCTAssertEqual(spy.snoozed.last?.minutes, 5)
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    // Both AlarmKit and the app declare `Alarm`. Inside the app its own wins, but a
    // test file imports both, so the app's has to be named in full.
    private func sample() -> OwnAlarm.Alarm {
        OwnAlarm.Alarm(task: "Wake", hour: 6, minute: 30, repeatDays: [],
                       volume: 0.6, fadeInSeconds: 0, overridesSilent: true, toneID: "siren")
    }
}
#endif
