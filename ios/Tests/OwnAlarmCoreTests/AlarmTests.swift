import XCTest
@testable import OwnAlarmCore

/// Tests for the parts of OwnAlarm that do not need an Apple SDK: the alarm model,
/// its scheduling arithmetic, persistence, and clock formatting.
final class AlarmTests: XCTestCase {

    /// Fixed calendar so the scheduling tests cannot drift with the machine's zone.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func reference() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 14
        components.hour = 8
        components.minute = 0
        return calendar.date(from: components)!
    }

    // MARK: Volume

    func testVolumePercentRoundsToNearest() {
        XCTAssertEqual(makeAlarm(volume: 0.85).volumePercent, 85)
        XCTAssertEqual(makeAlarm(volume: 0.0).volumePercent, 0)
        XCTAssertEqual(makeAlarm(volume: 1.0).volumePercent, 100)
        XCTAssertEqual(makeAlarm(volume: 0.666).volumePercent, 67)
    }

    func testFadeInStartsBelowTargetAndNoFadeStartsAtTarget() {
        let ramped = makeAlarm(volume: 0.80, fadeInSeconds: 30)
        XCTAssertLessThan(ramped.startingVolume, ramped.volume)
        XCTAssertEqual(ramped.startingVolume, 0.80 * Alarm.fadeInFloor, accuracy: 0.0001)

        let instant = makeAlarm(volume: 0.80, fadeInSeconds: 0)
        XCTAssertEqual(instant.startingVolume, 0.80, accuracy: 0.0001)
    }

    // MARK: Repeat summary

    func testRepeatSummaryNamesCommonPatterns() {
        XCTAssertEqual(makeAlarm(days: []).repeatSummary, "Once")
        XCTAssertEqual(makeAlarm(days: Set(Weekday.allCases)).repeatSummary, "Every day")
        XCTAssertEqual(
            makeAlarm(days: [.monday, .tuesday, .wednesday, .thursday, .friday]).repeatSummary,
            "Mon – Fri"
        )
        XCTAssertEqual(makeAlarm(days: [.saturday, .sunday]).repeatSummary, "Weekends")
    }

    func testRepeatSummaryListsIrregularDaysInWeekOrder() {
        let summary = makeAlarm(days: [.thursday, .tuesday]).repeatSummary
        let tuesday = Weekday.tuesday.shortSymbol
        let thursday = Weekday.thursday.shortSymbol
        XCTAssertEqual(summary, "\(tuesday), \(thursday)")
    }

    // MARK: Next fire date

    func testNextFireDateLandsOnARepeatDayAtTheRightTime() throws {
        let alarm = makeAlarm(hour: 6, minute: 45,
                              days: [.monday, .tuesday, .wednesday, .thursday, .friday])
        let next = try XCTUnwrap(alarm.nextFireDate(after: reference(), calendar: calendar))

        XCTAssertGreaterThan(next, reference())

        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: next)
        XCTAssertEqual(parts.hour, 6)
        XCTAssertEqual(parts.minute, 45)

        let day = try XCTUnwrap(Weekday(rawValue: try XCTUnwrap(parts.weekday)))
        XCTAssertTrue(alarm.repeatDays.contains(day),
                      "Fired on \(day) which is not in the repeat set")
    }

    func testOneShotAlarmFiresWithinTheNextDay() throws {
        // 06:45 with a reference of 08:00 has already passed today, so the next
        // occurrence is tomorrow morning — under 24 hours away.
        let alarm = makeAlarm(hour: 6, minute: 45, days: [])
        let next = try XCTUnwrap(alarm.nextFireDate(after: reference(), calendar: calendar))

        let interval = next.timeIntervalSince(reference())
        XCTAssertGreaterThan(interval, 0)
        XCTAssertLessThanOrEqual(interval, 24 * 3600)

        let parts = calendar.dateComponents([.hour, .minute], from: next)
        XCTAssertEqual(parts.hour, 6)
        XCTAssertEqual(parts.minute, 45)
    }

    func testDisabledAlarmNeverSchedules() {
        var alarm = makeAlarm(days: [.monday])
        alarm.isEnabled = false
        XCTAssertNil(alarm.nextFireDate(after: reference(), calendar: calendar))
    }

    func testNextFireDateChoosesTheSoonestRepeatDay() throws {
        // Monday 08:00: of every day at 06:45, the soonest is Tuesday 06:45 — not the
        // Sunday or Monday a wrong pick would give.
        let everyDay = makeAlarm(hour: 6, minute: 45, days: Set(Weekday.allCases))
        let next = try XCTUnwrap(everyDay.nextFireDate(after: reference(), calendar: calendar))
        XCTAssertEqual(next.timeIntervalSince(reference()), 22 * 3600 + 45 * 60, accuracy: 1)
    }

    // MARK: Persistence

    func testAlarmSurvivesAJSONRoundTrip() throws {
        let original = makeAlarm(volume: 0.42, fadeInSeconds: 15,
                                 days: [.monday, .friday])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Alarm.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testStarterAlarmsAreValid() {
        XCTAssertFalse(Alarm.starter.isEmpty)
        for alarm in Alarm.starter {
            XCTAssertFalse(alarm.task.isEmpty)
            XCTAssertTrue((0...1).contains(alarm.volume), "\(alarm.task) volume out of range")
            XCTAssertTrue((0...23).contains(alarm.hour))
            XCTAssertTrue((0...59).contains(alarm.minute))
            XCTAssertTrue(
                AlarmTone.bundled.contains { $0.id == alarm.toneID },
                "\(alarm.task) points at a tone that does not ship: \(alarm.toneID)"
            )
        }
    }

    func testSettingsSurviveAJSONRoundTrip() throws {
        var settings = AppSettings()
        settings.timeFormat = .twelveHour
        settings.theme = .dark
        settings.showOnLockScreen = false
        settings.defaults.volume = 0.33

        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }

    // MARK: Tones

    func testUnknownToneFallsBackInsteadOfCrashing() {
        let tone = AlarmTone.tone(id: "does-not-exist", in: AlarmTone.bundled)
        XCTAssertEqual(tone.id, AlarmTone.fallback.id)
    }

    func testBundledToneIDsAreUnique() {
        let ids = AlarmTone.bundled.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    // MARK: Clock

    func testTwentyFourHourFormatDropsTheMeridiem() {
        let text = TimeText.string(hour: 6, minute: 45, format: .twentyFourHour,
                                   locale: Locale(identifier: "en_GB"), calendar: calendar)
        XCTAssertTrue(text.contains("45"), "got \(text)")
        XCTAssertFalse(text.uppercased().contains("AM"), "got \(text)")
        XCTAssertFalse(text.uppercased().contains("PM"), "got \(text)")
    }

    func testAfternoonIsTwentyFourHourNotTwelve() {
        let text = TimeText.string(hour: 13, minute: 15, format: .twentyFourHour,
                                   locale: Locale(identifier: "en_GB"), calendar: calendar)
        XCTAssertTrue(text.contains("13"), "expected a 13 in \(text)")
    }

    func testTwelveHourFormatKeepsTheMeridiem() {
        let text = TimeText.string(hour: 13, minute: 15, format: .twelveHour,
                                   locale: Locale(identifier: "en_US"), calendar: calendar)
        XCTAssertTrue(text.uppercased().contains("PM"), "got \(text)")
        XCTAssertTrue(text.hasPrefix("1:15"), "got \(text)")
        XCTAssertFalse(text.contains("13"), "got \(text)")
    }

    func testAutomaticFollowsTheLocale() {
        XCTAssertTrue(TimeFormat.automatic.uses24Hour(in: Locale(identifier: "en_GB")))
        XCTAssertFalse(TimeFormat.automatic.uses24Hour(in: Locale(identifier: "en_US")))
        XCTAssertTrue(TimeFormat.twentyFourHour.uses24Hour(in: Locale(identifier: "en_US")))
        XCTAssertFalse(TimeFormat.twelveHour.uses24Hour(in: Locale(identifier: "en_GB")))
    }

    func testRelativeCountdownReads() {
        let now = reference()
        XCTAssertEqual(TimeText.relative(to: now.addingTimeInterval(6 * 3600 + 12 * 60), from: now),
                       "in 6h 12m")
        XCTAssertEqual(TimeText.relative(to: now.addingTimeInterval(45 * 60), from: now), "in 45m")
        XCTAssertEqual(TimeText.relative(to: now.addingTimeInterval(2 * 3600), from: now), "in 2h")
        XCTAssertEqual(TimeText.relative(to: now.addingTimeInterval(-500), from: now), "in 0m")
    }

    // MARK: New alarms

    func testNewAlarmStartsAtTheCurrentTime() {
        let now = reference().addingTimeInterval(37 * 60)   // 08:37
        let alarm = Alarm.newAlarm(from: AlarmDefaults(), at: now, calendar: calendar)
        XCTAssertEqual(alarm.hour, 8)
        XCTAssertEqual(alarm.minute, 37)
    }

    func testNewAlarmCarriesTheDefaults() {
        var defaults = AlarmDefaults()
        defaults.volume = 0.42
        defaults.toneID = "whisper"
        defaults.snoozeMinutes = 5

        let alarm = Alarm.newAlarm(from: defaults, at: reference(), calendar: calendar)

        XCTAssertEqual(alarm.volume, 0.42, accuracy: 0.0001)
        XCTAssertEqual(alarm.toneID, "whisper")
        XCTAssertEqual(alarm.snoozeMinutes, 5)
        XCTAssertTrue(alarm.repeatDays.isEmpty)
        XCTAssertTrue(alarm.isEnabled)
    }

    func testFactoryDefaultsAreHalfVolumeWithFadeOff() {
        let defaults = AlarmDefaults()
        XCTAssertEqual(defaults.volume, 0.5, accuracy: 0.0001)
        XCTAssertEqual(defaults.fadeInSeconds, 0, "Fade-in starts switched off")
        XCTAssertEqual(defaults.snoozeMinutes, 9)
    }

    func testSwitchingFadeOnStartsAtTenSeconds() {
        var defaults = AlarmDefaults()
        XCTAssertEqual(defaults.fadeInWhenSwitchedOn, 10)

        defaults.fadeInSeconds = 45          // remembered from the user's last alarm
        XCTAssertEqual(defaults.fadeInWhenSwitchedOn, 45)
    }

    func testSwitchingSnoozeBackOnNeverLandsOnZero() {
        var defaults = AlarmDefaults()
        defaults.snoozeMinutes = 0          // the user's last alarm had snooze off
        XCTAssertEqual(defaults.snoozeWhenSwitchedOn, AlarmDefaults.standardSnoozeMinutes)

        defaults.snoozeMinutes = 4
        XCTAssertEqual(defaults.snoozeWhenSwitchedOn, 4)
    }

    func testFirstLaunchFollowsThePhone() {
        let settings = AppSettings()
        XCTAssertEqual(settings.timeFormat, .automatic, "Clock follows the phone's region")
        XCTAssertEqual(settings.theme, .automatic, "Theme follows the phone's light or dark mode")
        XCTAssertTrue(settings.showOnLockScreen)
    }

    func testEveryOptionHasALabel() {
        XCTAssertEqual(TimeFormat.allCases.map(\.label), ["24-hour", "AM / PM", "Match device"])
        XCTAssertEqual(ThemePreference.allCases.map(\.label), ["Light", "Dark", "Auto"])
    }

    // MARK: Snooze notice

    func testSnoozeNoticeSaysWhenTheAlarmReturns() {
        let now = reference().addingTimeInterval(30 * 60)   // 08:30
        let body = SnoozeText.body(minutes: 9, now: now, format: .twentyFourHour,
                                   locale: Locale(identifier: "en_GB"), calendar: calendar)
        XCTAssertTrue(body.contains("08:39"), "got \(body)")
        XCTAssertTrue(body.contains("9 min"), "got \(body)")
    }

    func testSnoozeNoticeNamesTheTask() {
        XCTAssertEqual(SnoozeText.title(task: "Morning run"), "Morning run · snoozed")
        XCTAssertEqual(SnoozeText.title(task: ""), "Alarm snoozed")
    }

    func testStoredSettingsFallBackToDefaultsThenReadWhatWasSaved() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        XCTAssertEqual(AppSettings.stored(in: suite), AppSettings(), "Nothing saved yet")

        var saved = AppSettings()
        saved.timeFormat = .twelveHour
        suite.set(try JSONEncoder().encode(saved), forKey: AppSettings.storageKey)

        XCTAssertEqual(AppSettings.stored(in: suite).timeFormat, .twelveHour)
    }

    // MARK: Vibration, and saves from older versions

    /// Exactly what a build without `vibrates` wrote to disk. If this stops loading,
    /// an update wipes every alarm the user has.
    func testAnAlarmSavedBeforeVibrationExistedStillLoads() throws {
        let json = """
        {"id":"8B1F0B8E-6F1A-4C44-9F3B-3E1B7C1D2A10","task":"Old","hour":6,"minute":30,\
        "repeatDays":[2,3],"isEnabled":true,"volume":0.5,"fadeInSeconds":0,\
        "overridesSilent":true,"toneID":"siren","snoozeMinutes":9,"louderAfterSnooze":true}
        """
        let alarm = try JSONDecoder().decode(Alarm.self, from: Data(json.utf8))

        XCTAssertEqual(alarm.task, "Old")
        XCTAssertEqual(alarm.repeatDays, [.monday, .tuesday])
        XCTAssertTrue(alarm.vibrates, "Older alarms vibrate, as they always did")
    }

    func testSettingsSavedBeforeVibrationExistedStillLoad() throws {
        let json = """
        {"timeFormat":"twelveHour","theme":"dark","showOnLockScreen":false,\
        "defaults":{"volume":0.4,"fadeInSeconds":0,"overridesSilent":true,"toneID":"whisper",\
        "snoozeMinutes":5,"louderAfterSnooze":false}}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.timeFormat, .twelveHour, "The rest of the settings survive")
        XCTAssertEqual(settings.defaults.toneID, "whisper")
        XCTAssertTrue(settings.defaults.vibrates)
    }

    func testSwitchingVibrationOffSurvivesSaving() throws {
        var alarm = makeAlarm()
        alarm.vibrates = false
        let decoded = try JSONDecoder().decode(Alarm.self, from: JSONEncoder().encode(alarm))
        XCTAssertFalse(decoded.vibrates)
    }

    func testANewAlarmCarriesTheRememberedVibration() {
        var defaults = AlarmDefaults()
        XCTAssertTrue(Alarm.newAlarm(from: defaults).vibrates, "Vibrates unless told otherwise")

        defaults.vibrates = false
        XCTAssertFalse(Alarm.newAlarm(from: defaults).vibrates)
    }

    // MARK: Weekdays

    func testLocaleOrderedCoversEveryDayExactlyOnce() {
        let ordered = Weekday.localeOrdered
        XCTAssertEqual(ordered.count, 7)
        XCTAssertEqual(Set(ordered).count, 7)
    }

    // MARK: Helpers

    private func makeAlarm(hour: Int = 7,
                           minute: Int = 0,
                           volume: Double = 0.7,
                           fadeInSeconds: Int = 0,
                           days: Set<Weekday> = []) -> Alarm {
        Alarm(task: "Test alarm",
              hour: hour,
              minute: minute,
              repeatDays: days,
              volume: volume,
              fadeInSeconds: fadeInSeconds,
              overridesSilent: true,
              toneID: "siren")
    }
}
