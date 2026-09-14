import XCTest
import UserNotifications
@testable import OwnAlarm

/// Guards the notification content, which is where per-task volume actually lives.
/// If these break, alarms stop being louder or quieter than the ringer.
final class AlarmSchedulerTests: XCTestCase {

    private let scheduler = AlarmScheduler()
    private let tone = AlarmTone.tone(id: "siren", in: AlarmTone.bundled)

    func testOverridingSilentProducesACriticalAlert() {
        let alarm = makeAlarm(volume: 0.85, overridesSilent: true)
        let content = scheduler.content(for: alarm, tone: tone, showOnLockScreen: true)

        XCTAssertEqual(content.interruptionLevel, .critical,
                       "Only a critical alert rings through Silent and Focus")
        XCTAssertNotNil(content.sound)
    }

    func testNotOverridingSilentStaysTimeSensitive() {
        let alarm = makeAlarm(volume: 0.55, overridesSilent: false)
        let content = scheduler.content(for: alarm, tone: tone, showOnLockScreen: true)

        XCTAssertEqual(content.interruptionLevel, .timeSensitive)
        XCTAssertNotNil(content.sound)
    }

    func testContentCarriesTheTaskAndItsVolume() {
        let alarm = makeAlarm(task: "Morning run", volume: 0.85)
        let content = scheduler.content(for: alarm, tone: tone, showOnLockScreen: true)

        XCTAssertEqual(content.title, "Morning run")
        XCTAssertTrue(content.body.contains("85%"), "got \(content.body)")
        XCTAssertTrue(content.body.contains(tone.name), "got \(content.body)")
    }

    func testAnUnnamedAlarmStillHasATitle() {
        let content = scheduler.content(for: makeAlarm(task: ""), tone: tone, showOnLockScreen: true)
        XCTAssertEqual(content.title, "Alarm")
    }

    func testContentIdentifiesItsAlarmForRouting() throws {
        let alarm = makeAlarm()
        let content = scheduler.content(for: alarm, tone: tone, showOnLockScreen: true)

        let raw = try XCTUnwrap(content.userInfo["alarmID"] as? String)
        XCTAssertEqual(UUID(uuidString: raw), alarm.id)
        XCTAssertEqual(content.categoryIdentifier, AlarmScheduler.categoryIdentifier)
    }

    func testLockScreenOffSuppressesEverythingVisible() {
        let alarm = makeAlarm(task: "Private thing")
        let content = scheduler.content(for: alarm, tone: tone, showOnLockScreen: false)

        XCTAssertEqual(content.title, "")
        XCTAssertEqual(content.body, "")
        XCTAssertNil(content.sound, "Nothing should be audible from the Lock Screen")
    }

    func testATestRingIsTheAlarmsOwnNotificationMarkedAsATest() {
        let alarm = makeAlarm(task: "Morning run", volume: 0.6)
        let real = scheduler.content(for: alarm, tone: tone, showOnLockScreen: true)
        let test = scheduler.testContent(for: alarm, tone: tone)

        XCTAssertNotNil(test.sound)
        // UNNotificationSound compares by identity; the description names the file.
        XCTAssertEqual(String(describing: test.sound), String(describing: real.sound),
                       "The very sound the real alarm rings with")
        XCTAssertEqual(test.interruptionLevel, real.interruptionLevel)
        XCTAssertEqual(test.userInfo["test"] as? Bool, true)
        XCTAssertNil(test.userInfo["alarmID"], "No alarm to open or stop")
        XCTAssertEqual(test.categoryIdentifier, "", "No Stop / Snooze buttons")
        XCTAssertTrue(test.title.hasPrefix("Test"), "got \(test.title)")
        XCTAssertTrue(test.title.contains("Morning run"))
    }

    func testAOneShotIsReportedFinishedOnceItsTimeHasPassed() {
        let scheduler = AlarmScheduler(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        var finished: [UUID] = []
        scheduler.onFinished = { finished.append($0) }
        let alarm = makeAlarm()
        scheduler.schedule(alarm, tone: tone, showOnLockScreen: true)

        scheduler.reportFinishedOneShots(now: Date())
        XCTAssertTrue(finished.isEmpty, "Not rung yet")

        scheduler.reportFinishedOneShots(now: Date().addingTimeInterval(2 * 86_400))
        XCTAssertEqual(finished, [alarm.id])
        scheduler.cancel(alarm)
    }

    func testReArmingLeavesAPendingSnoozeAlone() async throws {
        let center = UNUserNotificationCenter.current()
        let scheduler = AlarmScheduler(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let alarm = makeAlarm()
        let snoozeID = "\(alarm.id.uuidString).snooze"
        defer { scheduler.cancelSnooze(alarm) }

        scheduler.scheduleSnooze(alarm, tone: tone, minutes: 9)
        let before = await center.pendingNotificationRequests().map(\.identifier)
        try XCTSkipUnless(before.contains(snoozeID), "Notifications are not allowed in this test host")

        scheduler.cancelAll([alarm])   // what every launch and return to the app does

        let after = await center.pendingNotificationRequests().map(\.identifier)
        XCTAssertTrue(after.contains(snoozeID), "Opening the app must not delete a snooze")
    }

    func testEveryBundledToneResolvesToAFileInTheBundle() {
        for tone in AlarmTone.bundled {
            let name = (tone.fileName as NSString).deletingPathExtension
            let ext = (tone.fileName as NSString).pathExtension
            XCTAssertNotNil(
                Bundle.main.url(forResource: name, withExtension: ext),
                "\(tone.fileName) is referenced but not in the app bundle"
            )
        }
    }

    private func makeAlarm(task: String = "Test",
                           volume: Double = 0.7,
                           overridesSilent: Bool = true) -> Alarm {
        Alarm(task: task, hour: 7, minute: 0, repeatDays: [],
              volume: volume, fadeInSeconds: 0, overridesSilent: overridesSilent,
              toneID: "siren")
    }
}
