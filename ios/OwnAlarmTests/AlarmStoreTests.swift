import XCTest
@testable import OwnAlarm

/// Records what the store asked the scheduler to do, so behaviour can be asserted
/// without touching UNUserNotificationCenter.
final class SpyScheduler: AlarmScheduling {
    private(set) var scheduled: [(alarm: Alarm, tone: AlarmTone, lockScreen: Bool)] = []
    private(set) var snoozed: [(alarm: Alarm, tone: AlarmTone, minutes: Int)] = []
    private(set) var cancelled: [Alarm] = []
    private(set) var cancelledSnoozes: [Alarm] = []
    private(set) var cancelledAll: [[Alarm]] = []
    var cancelAllCount: Int { cancelledAll.count }
    private(set) var tests: [(alarm: Alarm, tone: AlarmTone, seconds: TimeInterval)] = []
    private(set) var cancelledTestCount = 0
    /// Whether a test ring could make a sound — the permission answer.
    var canRing = true
    var onFinished: ((UUID) -> Void)?
    var language: AppLanguage = .english

    func schedule(_ alarm: Alarm, tone: AlarmTone, showOnLockScreen: Bool) {
        scheduled.append((alarm, tone, showOnLockScreen))
    }
    func scheduleSnooze(_ alarm: Alarm, tone: AlarmTone, minutes: Int) {
        snoozed.append((alarm, tone, minutes))
    }
    func cancel(_ alarm: Alarm) { cancelled.append(alarm) }
    func cancelSnooze(_ alarm: Alarm) { cancelledSnoozes.append(alarm) }
    func cancelAll(_ alarms: [Alarm]) { cancelledAll.append(alarms) }
    func scheduleTest(_ alarm: Alarm, tone: AlarmTone, in seconds: TimeInterval) {
        tests.append((alarm, tone, seconds))
    }
    func cancelTest() { cancelledTestCount += 1 }
    func canRingTest() async -> Bool { canRing }
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

    /// A new install: empty, as real users get it.
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

        store.save(alarm, isNew: true)

        let next = Alarm.newAlarm(from: store.settings.defaults)
        XCTAssertEqual(next.volume, 0.42, accuracy: 0.0001)
        XCTAssertEqual(next.toneID, "whisper")
        XCTAssertEqual(next.snoozeMinutes, 5)
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
        var switchedOff = makeAlarm(task: "Switched off")
        switchedOff.isEnabled = false
        store.add(switchedOff)
        let switchedOn = makeAlarm(task: "Switched on")
        store.add(switchedOn)

        // The store holds the spy it was built with, so measure the delta.
        let scheduledBefore = spy.scheduled.count
        let cancelAllBefore = spy.cancelAllCount

        store.rescheduleAll()

        let rearmed = spy.scheduled.dropFirst(scheduledBefore).map { $0.alarm.id }
        XCTAssertEqual(spy.cancelAllCount, cancelAllBefore + 1)
        XCTAssertEqual(Set(spy.cancelledAll.last?.map(\.id) ?? []), [switchedOff.id, switchedOn.id],
                       "Every alarm's old schedule is cleared, switched off or not")
        XCTAssertEqual(rearmed, [switchedOn.id], "Only the switched-on alarm is re-armed")
    }

    func testLockScreenPreferenceIsPassedToTheScheduler() {
        let store = makeStore()
        store.settings.showOnLockScreen = false

        store.add(makeAlarm())

        XCTAssertEqual(spy.scheduled.last?.lockScreen, false)
    }

    // MARK: Snooze

    func testSnoozeRingsAgainAtTheAlarmsOwnLevel() throws {
        let store = makeStore()
        let alarm = makeAlarm(volume: 0.50)
        store.add(alarm)

        store.snooze(alarm)
        store.snooze(alarm)

        XCTAssertEqual(spy.snoozed.map(\.alarm.volume), [0.50, 0.50], "Every snooze at the alarm's own level")
        XCTAssertEqual(try XCTUnwrap(spy.snoozed.last).minutes, alarm.snoozeMinutes)
    }

    func testSnoozeRingsWithTheAlarmsImportedTone() throws {
        let store = makeStore()
        let mine = AlarmTone(id: "mine.m4a", name: "Mine", character: "Yours",
                             peak: 2, fileName: "mine.m4a", source: .imported)
        store.addImportedTone(mine)
        let alarm = makeAlarm(toneID: mine.id)
        store.add(alarm)

        store.snooze(alarm)

        XCTAssertEqual(try XCTUnwrap(spy.snoozed.last).tone, mine)
    }

    func testSnoozeClearsTheRingingAlarm() {
        let store = makeStore()
        let alarm = makeAlarm()
        store.add(alarm)
        store.ringing = alarm

        store.snooze(alarm)

        XCTAssertNil(store.ringing)
    }

    // MARK: Test ring

    func testATestRingUsesWhatIsOnScreenAndLeavesTheAlarmAlone() throws {
        let store = makeStore()
        let mine = AlarmTone(id: "mine.m4a", name: "Mine", character: "Yours",
                             peak: 2, fileName: "mine.m4a", source: .imported)
        store.addImportedTone(mine)
        // Never saved: the editor tests what is on screen.
        let draft = makeAlarm(volume: 0.35, toneID: mine.id)

        store.testRing(draft)

        let test = try XCTUnwrap(spy.tests.last)
        XCTAssertNotEqual(test.alarm.id, draft.id, "Its own id, so Stop on the test never reaches the alarm")
        XCTAssertEqual(test.alarm.volume, 0.35, accuracy: 0.0001)
        XCTAssertEqual(test.tone, mine, "The imported tone, not a bundled fallback")
        XCTAssertEqual(test.seconds, AlarmStore.testLead)
        XCTAssertTrue(store.alarms.isEmpty, "A test ring saves nothing")
        XCTAssertNotNil(store.testRingsAt)
    }

    func testATestCopyIsNamedAsATestWithNothingToSnoozeTo() {
        var alarm = makeAlarm(task: "Morning run", volume: 0.6)
        alarm.snoozeMinutes = 9

        let test = AlarmStore.testCopy(of: alarm, language: .english)

        XCTAssertNotEqual(test.id, alarm.id)
        XCTAssertEqual(test.task, "Test · Morning run")
        XCTAssertEqual(test.snoozeMinutes, 0)
        XCTAssertEqual(test.volume, alarm.volume)
        XCTAssertEqual(test.toneID, alarm.toneID)
        XCTAssertEqual(AlarmStore.testCopy(of: makeAlarm(task: ""), language: .english).task, "Test · Alarm")
        XCTAssertEqual(AlarmStore.testCopy(of: alarm, language: .thai).task, "ทดลอง · Morning run")
        XCTAssertEqual(AlarmStore.testCopy(of: makeAlarm(task: ""), language: .thai).task, "ทดลอง · นาฬิกาปลุก")
    }

    // MARK: Language

    func testTheSchedulerWritesInTheAppsLanguage() {
        let store = makeStore()

        store.settings.language = .thai
        XCTAssertEqual(spy.language, .thai, "Alerts follow the setting")

        store.settings.language = .english
        XCTAssertEqual(spy.language, .english)
    }

    func testTheLanguageIsSettledOnFirstLaunchAndKeptAfter() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let file = folder.appendingPathComponent("language.json")

        let first = AlarmStore(scheduler: spy, fileURL: file, defaults: suite)
        XCTAssertNotNil(suite.data(forKey: AppSettings.storageKey), "First launch keeps the language it found")
        first.settings.language = .thai

        let later = SpyScheduler()
        let second = AlarmStore(scheduler: later, fileURL: file, defaults: suite)
        XCTAssertEqual(second.settings.language, .thai)
        XCTAssertEqual(later.language, .thai, "Handed over before anything is armed")
    }

    func testWithoutPermissionATestRingSaysSoInsteadOfCountingDown() {
        let store = makeStore()
        spy.canRing = false

        store.testRing(makeAlarm())

        let blocked = NSPredicate { _, _ in store.testBlocked && store.testRingsAt == nil }
        expectation(for: blocked, evaluatedWith: nil)
        waitForExpectations(timeout: 2)
        XCTAssertGreaterThanOrEqual(spy.cancelledTestCount, 1, "Nothing left scheduled")
    }

    func testATestThatComesDueWithTheAppOpenRingsInTheApp() throws {
        let store = makeStore()
        store.testRing(makeAlarm())
        let scheduled = try XCTUnwrap(spy.tests.last).alarm

        XCTAssertTrue(store.testArrivedInApp())

        XCTAssertEqual(store.testRingingInApp?.id, scheduled.id, "The same copy the scheduler got")
        XCTAssertNil(store.testRingsAt, "No countdown once it is ringing")
        store.stopTestInApp()
        XCTAssertNil(store.testRingingInApp)
    }

    func testACancelledTestThatArrivesAnywayIsJustANotification() {
        let store = makeStore()
        store.testRing(makeAlarm())
        store.cancelTestRing()

        XCTAssertFalse(store.testArrivedInApp())
        XCTAssertNil(store.testRingingInApp)
    }

    func testReArmingDiscardsSoundCopiesNothingWillRing() throws {
        let store = makeStore()
        let siren = AlarmTone.tone(id: "siren", in: AlarmTone.bundled)
        store.add(makeAlarm(volume: 0.7, toneID: "siren"))
        let inUse = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 0.7))
        let triedOnce = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 0.37))

        store.rescheduleAll()

        let exists = { FileManager.default.fileExists(atPath: ScaledSound.directory.appendingPathComponent($0).path) }
        XCTAssertTrue(exists(inUse), "An enabled alarm's copy stays")
        XCTAssertFalse(exists(triedOnce), "A level only tested is not kept")
    }

    func testCancellingATestRingClearsIt() {
        let store = makeStore()
        store.testRing(makeAlarm())

        store.cancelTestRing()

        XCTAssertEqual(spy.cancelledTestCount, 1)
        XCTAssertNil(store.testRingsAt)
    }

    func testATestRingIsOverOnceItsTimeHasCome() {
        let store = makeStore()
        store.testRing(makeAlarm())

        let over = NSPredicate { _, _ in store.testRingsAt == nil }
        expectation(for: over, evaluatedWith: nil)
        waitForExpectations(timeout: AlarmStore.testLead + 2)
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
        let early = makeAlarm(task: "Early", hour: 6, minute: 0, days: Set(Weekday.allCases))
        let late = makeAlarm(task: "Late", hour: 23, minute: 30, days: Set(Weekday.allCases))
        store.add(late)
        store.add(early)

        let next = try XCTUnwrap(store.nextAlarm)
        let all = store.alarms.compactMap { $0.nextFireDate() }
        XCTAssertEqual(next.date, all.min())
    }

    func testUsageCountTracksTonesInUse() {
        let store = makeStore()
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
        let rearmsBefore = spy.cancelAllCount
        store.addImportedTone(tone)

        XCTAssertEqual(store.tones.filter { $0.id == tone.id }.count, 1)
        XCTAssertEqual(spy.cancelAllCount, rearmsBefore + 1,
                       "Re-importing a file re-arms alarms, so they ring the new recording")
    }

    func testImportedTonesSurviveARelaunch() {
        let url = folder.appendingPathComponent("alarms.json")
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let tone = AlarmTone(id: "kitchen.m4a", name: "kitchen", character: "Yours",
                             peak: 2, fileName: "kitchen.m4a", source: .imported)

        let first = AlarmStore(scheduler: spy, fileURL: url, defaults: suite)
        first.addImportedTone(tone)

        let second = AlarmStore(scheduler: SpyScheduler(), fileURL: url, defaults: suite)
        XCTAssertTrue(second.tones.contains(tone), "An imported song must still be there after a relaunch")
        XCTAssertEqual(second.tones.count, AlarmTone.bundled.count + 1)
    }

    // MARK: Persistence

    func testAlarmsSurviveARelaunch() {
        let url = folder.appendingPathComponent("alarms.json")
        let suite = UserDefaults(suiteName: UUID().uuidString)!

        let first = AlarmStore(scheduler: spy, fileURL: url, defaults: suite)
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
                           toneID: String = "siren") -> Alarm {
        Alarm(task: task, hour: hour, minute: minute, repeatDays: days,
              volume: volume, overridesSilent: true,
              toneID: toneID, snoozeMinutes: 9)
    }
}
