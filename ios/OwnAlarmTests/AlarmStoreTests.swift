import XCTest
@testable import OwnAlarm

/// Records what the store asked the scheduler to do, so behaviour can be asserted
/// without touching UNUserNotificationCenter.
final class SpyScheduler: AlarmScheduling {
    private(set) var scheduled: [(alarm: Alarm, tone: AlarmTone, lockScreen: Bool)] = []
    private(set) var snoozed: [(alarm: Alarm, minutes: Int)] = []
    private(set) var cancelled: [Alarm] = []
    private(set) var cancelledSnoozes: [Alarm] = []
    private(set) var cancelAllCount = 0

    func schedule(_ alarm: Alarm, tone: AlarmTone, showOnLockScreen: Bool) {
        scheduled.append((alarm, tone, showOnLockScreen))
    }
    func scheduleSnooze(_ alarm: Alarm, minutes: Int) { snoozed.append((alarm, minutes)) }
    func cancel(_ alarm: Alarm) { cancelled.append(alarm) }
    func cancelSnooze(_ alarm: Alarm) { cancelledSnoozes.append(alarm) }
    func cancelAll() { cancelAllCount += 1 }
}

@MainActor
final class AlarmStoreTests: XCTestCase {

    private var folder: URL!
    private var spy: SpyScheduler!

    override func setUp() {
        super.setUp()
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        spy = SpyScheduler()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func makeStore() -> AlarmStore {
        AlarmStore(
            scheduler: spy,
            fileURL: folder.appendingPathComponent("alarms.json"),
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
    }

    // MARK: First run

    func testFirstRunStartsEmpty() {
        XCTAssertTrue(makeStore().alarms.isEmpty,
                      "A new user should not find alarms they did not set")
    }

    func testASeedIsOnlyUsedWhenAskedFor() {
        let store = AlarmStore(scheduler: spy,
                               fileURL: folder.appendingPathComponent("seeded.json"),
                               defaults: UserDefaults(suiteName: UUID().uuidString)!,
                               seed: Alarm.starter)
        XCTAssertEqual(store.alarms.count, Alarm.starter.count)
    }

    func testAlarmsAreSortedByTimeOfDay() {
        let store = makeStore()
        store.add(makeAlarm(task: "Late", hour: 22, minute: 0))
        store.add(makeAlarm(task: "Early", hour: 6, minute: 45))
        store.add(makeAlarm(task: "Noon", hour: 13, minute: 15))

        XCTAssertEqual(store.sortedAlarms.map(\.task), ["Early", "Noon", "Late"])
    }

    // MARK: Remembering choices

    func testSavingAnAlarmRemembersItsChoicesForTheNextOne() {
        let store = makeStore()
        var alarm = makeAlarm(volume: 0.42, toneID: "whisper")
        alarm.snoozeMinutes = 5
        alarm.fadeInSeconds = 15

        store.save(alarm, isNew: true)

        let next = Alarm.newAlarm(from: store.settings.defaults)
        XCTAssertEqual(next.volume, 0.42, accuracy: 0.0001)
        XCTAssertEqual(next.toneID, "whisper")
        XCTAssertEqual(next.snoozeMinutes, 5)
        XCTAssertEqual(next.fadeInSeconds, 15)
    }

    func testEditingAnAlarmAlsoUpdatesWhatIsRemembered() {
        let store = makeStore()
        var alarm = makeAlarm(volume: 0.8)
        store.save(alarm, isNew: true)

        alarm.volume = 0.25
        store.save(alarm, isNew: false)

        XCTAssertEqual(store.settings.defaults.volume, 0.25, accuracy: 0.0001)
    }

    func testTogglingAnAlarmDoesNotChangeWhatIsRemembered() {
        let store = makeStore()
        store.add(makeAlarm(volume: 0.9))
        let before = store.settings.defaults

        store.setEnabled(false, for: store.alarms[0])

        XCTAssertEqual(store.settings.defaults, before)
    }

    func testRememberedChoicesSurviveARelaunch() {
        let url = folder.appendingPathComponent("alarms.json")
        let suite = UserDefaults(suiteName: UUID().uuidString)!

        let first = AlarmStore(scheduler: spy, fileURL: url, defaults: suite)
        first.save(makeAlarm(volume: 0.33, toneID: "marimba"), isNew: true)

        let second = AlarmStore(scheduler: SpyScheduler(), fileURL: url, defaults: suite)
        XCTAssertEqual(second.settings.defaults.volume, 0.33, accuracy: 0.0001)
        XCTAssertEqual(second.settings.defaults.toneID, "marimba")
    }

    // MARK: Scheduling side effects

    func testAddingAnAlarmSchedulesIt() {
        let store = makeStore()
        let alarm = makeAlarm(task: "Stretch")
        store.add(alarm)

        XCTAssertTrue(store.alarms.contains { $0.id == alarm.id })
        XCTAssertEqual(spy.scheduled.last?.alarm.id, alarm.id)
    }

    func testDisablingAnAlarmCancelsWithoutRescheduling() {
        let store = makeStore()
        let alarm = makeAlarm()
        store.add(alarm)
        let scheduledBefore = spy.scheduled.count

        store.setEnabled(false, for: alarm)

        XCTAssertTrue(spy.cancelled.contains { $0.id == alarm.id })
        XCTAssertEqual(spy.scheduled.count, scheduledBefore,
                       "A disabled alarm must not be rescheduled")
    }

    func testDeletingAnAlarmCancelsIt() {
        let store = makeStore()
        let alarm = makeAlarm()
        store.add(alarm)

        store.delete(alarm)

        XCTAssertFalse(store.alarms.contains { $0.id == alarm.id })
        XCTAssertTrue(spy.cancelled.contains { $0.id == alarm.id })
    }

    func testRescheduleAllSkipsDisabledAlarms() {
        let store = makeStore()
        store.alarms.forEach { store.setEnabled(false, for: $0) }
        let enabled = makeAlarm(task: "Only one")
        store.add(enabled)

        // The store holds the spy it was built with, so measure the delta rather
        // than swapping in a fresh spy it would never see.
        let scheduledBefore = spy.scheduled.count
        let cancelAllBefore = spy.cancelAllCount

        store.rescheduleAll()

        let newlyScheduled = Array(spy.scheduled.dropFirst(scheduledBefore))
        XCTAssertEqual(spy.cancelAllCount, cancelAllBefore + 1)
        XCTAssertEqual(newlyScheduled.count, 1, "Only the enabled alarm should be re-armed")
        XCTAssertEqual(newlyScheduled.first?.alarm.id, enabled.id)
    }

    func testLockScreenPreferenceIsPassedToTheScheduler() {
        let store = makeStore()
        store.settings.showOnLockScreen = false

        store.add(makeAlarm())

        XCTAssertEqual(spy.scheduled.last?.lockScreen, false)
    }

    // MARK: Snooze — the volume rule

    func testSnoozeReturnsTenPercentLouder() {
        let store = makeStore()
        let alarm = makeAlarm(volume: 0.50, louderAfterSnooze: true)
        store.add(alarm)

        store.snooze(alarm)

        let snoozed = try? XCTUnwrap(spy.snoozed.last)
        XCTAssertEqual(snoozed?.alarm.volume ?? 0, 0.60, accuracy: 0.0001)
        XCTAssertEqual(snoozed?.minutes, alarm.snoozeMinutes)
    }

    func testSnoozeKeepsVolumeWhenTheRuleIsOff() {
        let store = makeStore()
        let alarm = makeAlarm(volume: 0.50, louderAfterSnooze: false)
        store.add(alarm)

        store.snooze(alarm)

        XCTAssertEqual(spy.snoozed.last?.alarm.volume ?? 0, 0.50, accuracy: 0.0001)
    }

    func testSnoozeNeverExceedsFullVolume() {
        let store = makeStore()
        let alarm = makeAlarm(volume: 0.97, louderAfterSnooze: true)
        store.add(alarm)

        store.snooze(alarm)

        XCTAssertEqual(spy.snoozed.last?.alarm.volume ?? 0, 1.0, accuracy: 0.0001)
    }

    func testSnoozeClearsTheRingingAlarm() {
        let store = makeStore()
        let alarm = makeAlarm()
        store.add(alarm)
        store.ringing = alarm

        store.snooze(alarm)

        XCTAssertNil(store.ringing)
    }

    // MARK: Stop

    func testStoppingAOneShotAlarmDisablesIt() throws {
        let store = makeStore()
        let alarm = makeAlarm(days: [])
        store.add(alarm)

        store.stop(alarm)

        let stored = try XCTUnwrap(store.alarm(withID: alarm.id))
        XCTAssertFalse(stored.isEnabled, "A one-shot alarm should not stay armed")
    }

    func testStoppingARepeatingAlarmLeavesItArmed() throws {
        let store = makeStore()
        let alarm = makeAlarm(days: [.monday, .wednesday])
        store.add(alarm)

        store.stop(alarm)

        let stored = try XCTUnwrap(store.alarm(withID: alarm.id))
        XCTAssertTrue(stored.isEnabled, "A repeating alarm must survive being stopped")
    }

    // MARK: Derived values

    func testNextAlarmIsTheSoonestEnabledOne() throws {
        let store = makeStore()
        store.alarms.forEach { store.delete($0) }

        let soon = makeAlarm(task: "Soon", hour: 6, minute: 0, days: Set(Weekday.allCases))
        let later = makeAlarm(task: "Later", hour: 23, minute: 30, days: Set(Weekday.allCases))
        store.add(later)
        store.add(soon)

        let next = try XCTUnwrap(store.nextAlarm)
        let all = store.alarms.compactMap { $0.nextFireDate() }
        XCTAssertEqual(next.date, all.min())
    }

    func testUsageCountTracksTonesInUse() {
        let store = makeStore()
        store.alarms.forEach { store.delete($0) }
        let siren = AlarmTone.tone(id: "siren", in: AlarmTone.bundled)

        XCTAssertEqual(store.usageCount(of: siren), 0)
        store.add(makeAlarm(toneID: "siren"))
        store.add(makeAlarm(toneID: "siren"))
        store.add(makeAlarm(toneID: "marimba"))

        XCTAssertEqual(store.usageCount(of: siren), 2)
    }

    func testImportedTonesAreNotAddedTwice() {
        let store = makeStore()
        let tone = AlarmTone(id: "mine.m4a", name: "Mine", character: "Yours",
                             peak: 2, fileName: "mine.m4a", source: .imported)
        store.addImportedTone(tone)
        store.addImportedTone(tone)

        XCTAssertEqual(store.tones.filter { $0.id == tone.id }.count, 1)
    }

    // MARK: Persistence

    func testAlarmsSurviveARelaunch() {
        let url = folder.appendingPathComponent("alarms.json")
        let suite = UserDefaults(suiteName: UUID().uuidString)!

        let first = AlarmStore(scheduler: spy, fileURL: url, defaults: suite)
        first.alarms.forEach { first.delete($0) }
        first.add(makeAlarm(task: "Persisted"))

        let second = AlarmStore(scheduler: SpyScheduler(), fileURL: url, defaults: suite)
        XCTAssertEqual(second.alarms.count, 1)
        XCTAssertEqual(second.alarms.first?.task, "Persisted")
    }

    func testSettingsSurviveARelaunch() {
        let url = folder.appendingPathComponent("alarms.json")
        let suite = UserDefaults(suiteName: UUID().uuidString)!

        let first = AlarmStore(scheduler: spy, fileURL: url, defaults: suite)
        first.settings.timeFormat = .twelveHour
        first.settings.theme = .dark

        let second = AlarmStore(scheduler: SpyScheduler(), fileURL: url, defaults: suite)
        XCTAssertEqual(second.settings.timeFormat, .twelveHour)
        XCTAssertEqual(second.settings.theme, .dark)
    }

    // MARK: Helpers

    private func makeAlarm(task: String = "Test",
                           hour: Int = 7,
                           minute: Int = 0,
                           volume: Double = 0.7,
                           days: Set<Weekday> = [],
                           toneID: String = "siren",
                           louderAfterSnooze: Bool = true) -> Alarm {
        Alarm(task: task, hour: hour, minute: minute, repeatDays: days,
              volume: volume, fadeInSeconds: 0, overridesSilent: true,
              toneID: toneID, snoozeMinutes: 9, louderAfterSnooze: louderAfterSnooze)
    }
}
