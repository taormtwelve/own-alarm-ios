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

    // MARK: Repeat summary

    func testRepeatSummaryNamesCommonPatterns() {
        XCTAssertEqual(makeAlarm(days: []).repeatSummary(in: .english), "Once")
        XCTAssertEqual(makeAlarm(days: Set(Weekday.allCases)).repeatSummary(in: .english), "Every day")
        XCTAssertEqual(
            makeAlarm(days: [.monday, .tuesday, .wednesday, .thursday, .friday]).repeatSummary(in: .english),
            "Mon – Fri"
        )
        XCTAssertEqual(makeAlarm(days: [.saturday, .sunday]).repeatSummary(in: .english), "Weekends")
    }

    func testRepeatSummaryListsIrregularDaysInWeekOrder() {
        let summary = makeAlarm(days: [.thursday, .tuesday]).repeatSummary(in: .english)
        let tuesday = Weekday.tuesday.shortSymbol(in: .english)
        let thursday = Weekday.thursday.shortSymbol(in: .english)
        XCTAssertEqual(summary, "\(tuesday), \(thursday)")
    }

    func testRepeatSummaryReadsInThai() {
        XCTAssertEqual(makeAlarm(days: []).repeatSummary(in: .thai), "ครั้งเดียว")
        XCTAssertEqual(makeAlarm(days: Set(Weekday.allCases)).repeatSummary(in: .thai), "ทุกวัน")
        XCTAssertEqual(
            makeAlarm(days: [.monday, .tuesday, .wednesday, .thursday, .friday]).repeatSummary(in: .thai),
            "จันทร์ – ศุกร์"
        )
        XCTAssertEqual(makeAlarm(days: [.saturday, .sunday]).repeatSummary(in: .thai), "สุดสัปดาห์")

        let tuesday = Weekday.tuesday.shortSymbol(in: .thai)
        let thursday = Weekday.thursday.shortSymbol(in: .thai)
        XCTAssertEqual(makeAlarm(days: [.thursday, .tuesday]).repeatSummary(in: .thai), "\(tuesday), \(thursday)")
        XCTAssertNotEqual(tuesday, Weekday.tuesday.shortSymbol(in: .english), "Thai day names, not English")
    }

    func testThaiDayPillsAreSevenDifferentDays() {
        let pills = Weekday.allCases.map { $0.narrowSymbol(in: .thai) }
        XCTAssertEqual(Set(pills).count, 7, "got \(pills)")
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
        let original = makeAlarm(volume: 0.42, days: [.monday, .friday])
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
        settings.language = .thai

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
        let text = TimeText.string(hour: 6, minute: 45, format: .twentyFourHour, language: .english,
                                   locale: Locale(identifier: "en_GB"), calendar: calendar)
        XCTAssertTrue(text.contains("45"), "got \(text)")
        XCTAssertFalse(text.uppercased().contains("AM"), "got \(text)")
        XCTAssertFalse(text.uppercased().contains("PM"), "got \(text)")
    }

    func testAfternoonIsTwentyFourHourNotTwelve() {
        let text = TimeText.string(hour: 13, minute: 15, format: .twentyFourHour, language: .english,
                                   locale: Locale(identifier: "en_GB"), calendar: calendar)
        XCTAssertTrue(text.contains("13"), "expected a 13 in \(text)")
    }

    func testTwelveHourFormatKeepsTheMeridiem() {
        let text = TimeText.string(hour: 13, minute: 15, format: .twelveHour, language: .english,
                                   locale: Locale(identifier: "en_US"), calendar: calendar)
        XCTAssertTrue(text.uppercased().contains("PM"), "got \(text)")
        XCTAssertTrue(text.hasPrefix("1:15"), "got \(text)")
        XCTAssertFalse(text.contains("13"), "got \(text)")
    }

    func testThaiTimesKeepTheClockSettingAndSpeakThai() {
        // An English-region phone with the app in Thai: the setting decides the hour
        // cycle, the language the words.
        let twentyFour = TimeText.string(hour: 13, minute: 15, format: .twentyFourHour, language: .thai,
                                         locale: Locale(identifier: "en_US"), calendar: calendar)
        XCTAssertTrue(twentyFour.contains("13:15"), "got \(twentyFour)")

        let twelve = TimeText.string(hour: 13, minute: 15, format: .twelveHour, language: .thai,
                                     locale: Locale(identifier: "en_US"), calendar: calendar)
        XCTAssertTrue(twelve.contains("1:15"), "got \(twelve)")
        XCTAssertFalse(twelve.uppercased().contains("PM"), "Thai, not English: \(twelve)")
        XCTAssertTrue(twelve.contains("เที่ยง"), "Thai's afternoon marker: \(twelve)")
    }

    func testAutomaticFollowsTheLocale() {
        XCTAssertTrue(TimeFormat.automatic.uses24Hour(in: Locale(identifier: "en_GB")))
        XCTAssertFalse(TimeFormat.automatic.uses24Hour(in: Locale(identifier: "en_US")))
        XCTAssertTrue(TimeFormat.twentyFourHour.uses24Hour(in: Locale(identifier: "en_US")))
        XCTAssertFalse(TimeFormat.twelveHour.uses24Hour(in: Locale(identifier: "en_GB")))
    }

    func testRelativeCountdownReads() {
        let now = reference()
        XCTAssertEqual(TimeText.relative(to: now.addingTimeInterval(6 * 3600 + 12 * 60), from: now,
                                         language: .english), "in 6h 12m")
        XCTAssertEqual(TimeText.relative(to: now.addingTimeInterval(45 * 60), from: now, language: .english), "in 45m")
        XCTAssertEqual(TimeText.relative(to: now.addingTimeInterval(2 * 3600), from: now, language: .english), "in 2h")
        XCTAssertEqual(TimeText.relative(to: now.addingTimeInterval(-500), from: now, language: .english), "in 0m")
        XCTAssertEqual(TimeText.relative(to: now.addingTimeInterval(6 * 3600 + 12 * 60), from: now,
                                         language: .thai), "อีก 6 ชม. 12 นาที")
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

    func testFactoryDefaultsAreHalfVolumeAndANineMinuteSnooze() {
        let defaults = AlarmDefaults()
        XCTAssertEqual(defaults.volume, 0.5, accuracy: 0.0001)
        XCTAssertEqual(defaults.snoozeMinutes, 9)
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
        XCTAssertEqual(settings.language, AppLanguage.preferred(), "Language follows the phone's")
    }

    func testEveryOptionHasALabel() {
        XCTAssertEqual(TimeFormat.allCases.map(\.label), ["24-hour", "AM / PM", "Match device"])
        XCTAssertEqual(ThemePreference.allCases.map(\.label), ["Light", "Dark", "Auto"])
        XCTAssertEqual(AppLanguage.allCases.map(\.label), ["English", "ไทย"], "Each named in itself")

        let thai = AppLanguage.thai
        XCTAssertEqual(TimeFormat.allCases.map { thai($0.label) }, ["24 ชั่วโมง", "12 ชั่วโมง", "ตามเครื่อง"])
        XCTAssertEqual(ThemePreference.allCases.map { thai($0.label) }, ["สว่าง", "มืด", "อัตโนมัติ"])
    }

    // MARK: Snooze notice

    func testSnoozeNoticeSaysWhenTheAlarmReturns() {
        let now = reference().addingTimeInterval(30 * 60)   // 08:30
        let body = SnoozeText.body(minutes: 9, now: now, format: .twentyFourHour, language: .english,
                                   locale: Locale(identifier: "en_GB"), calendar: calendar)
        XCTAssertTrue(body.contains("08:39"), "got \(body)")
        XCTAssertTrue(body.contains("9 min"), "got \(body)")
    }

    func testSnoozeNoticeNamesTheTask() {
        XCTAssertEqual(SnoozeText.title(task: "Morning run", language: .english), "Morning run · snoozed")
        XCTAssertEqual(SnoozeText.title(task: "", language: .english), "Alarm snoozed")
    }

    func testSnoozeNoticeReadsInThai() {
        let now = reference().addingTimeInterval(30 * 60)   // 08:30
        let body = SnoozeText.body(minutes: 9, now: now, format: .twentyFourHour, language: .thai,
                                   locale: Locale(identifier: "en_GB"), calendar: calendar)
        XCTAssertTrue(body.hasPrefix("ปลุกอีกครั้งเวลา "), "got \(body)")
        XCTAssertTrue(body.contains("08:39"), "got \(body)")
        XCTAssertTrue(body.hasSuffix("อีก 9 นาที"), "got \(body)")
        XCTAssertEqual(SnoozeText.title(task: "วิ่งตอนเช้า", language: .thai), "วิ่งตอนเช้า · เลื่อนปลุกแล้ว")
        XCTAssertEqual(SnoozeText.title(task: "", language: .thai), "เลื่อนปลุกแล้ว")
    }

    func testStoredSettingsFallBackToDefaultsThenReadWhatWasSaved() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        XCTAssertEqual(AppSettings.stored(in: suite), AppSettings(), "Nothing saved yet")

        var saved = AppSettings()
        saved.timeFormat = .twelveHour
        suite.set(try JSONEncoder().encode(saved), forKey: AppSettings.storageKey)

        XCTAssertEqual(AppSettings.stored(in: suite).timeFormat, .twelveHour)
    }

    // MARK: Saves from older versions

    /// Exactly what an older build wrote to disk — with fade-in and louder-after-snooze,
    /// both since removed. If this stops loading, an update wipes every alarm the user
    /// has.
    func testAnAlarmSavedByAnOlderBuildStillLoads() throws {
        let json = """
        {"id":"8B1F0B8E-6F1A-4C44-9F3B-3E1B7C1D2A10","task":"Old","hour":6,"minute":30,\
        "repeatDays":[2,3],"isEnabled":true,"volume":0.5,"fadeInSeconds":30,\
        "overridesSilent":true,"toneID":"siren","snoozeMinutes":9,"louderAfterSnooze":true,\
        "vibrates":false}
        """
        let alarm = try JSONDecoder().decode(Alarm.self, from: Data(json.utf8))

        XCTAssertEqual(alarm.task, "Old")
        XCTAssertEqual(alarm.repeatDays, [.monday, .tuesday])
        XCTAssertEqual(alarm.volume, 0.5, accuracy: 0.0001)
        XCTAssertEqual(alarm.snoozeMinutes, 9)
        XCTAssertFalse(alarm.vibrates, "A saved choice to not vibrate is kept")
    }

    /// Exactly what a build without `vibrates` wrote to disk.
    func testAnAlarmSavedBeforeVibrationExistedVibrates() throws {
        let json = """
        {"id":"8B1F0B8E-6F1A-4C44-9F3B-3E1B7C1D2A10","task":"Old","hour":6,"minute":30,\
        "repeatDays":[2,3],"isEnabled":true,"volume":0.5,\
        "overridesSilent":true,"toneID":"siren","snoozeMinutes":9}
        """
        let alarm = try JSONDecoder().decode(Alarm.self, from: Data(json.utf8))

        XCTAssertTrue(alarm.vibrates, "Older alarms vibrate, as they always did")
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

    func testSettingsSavedByAnOlderBuildStillLoad() throws {
        let json = """
        {"timeFormat":"twelveHour","theme":"dark","showOnLockScreen":false,\
        "defaults":{"volume":0.4,"fadeInSeconds":0,"overridesSilent":true,"toneID":"whisper",\
        "snoozeMinutes":5,"louderAfterSnooze":false}}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.timeFormat, .twelveHour, "The rest of the settings survive")
        XCTAssertEqual(settings.defaults.toneID, "whisper")
        XCTAssertEqual(settings.defaults.snoozeMinutes, 5)
        XCTAssertTrue(settings.defaults.vibrates, "Missing in the save: vibration on, as before")
        XCTAssertEqual(settings.language, AppLanguage.preferred(), "Saved before languages: the phone's")
    }

    func testALanguageThisVersionDoesNotKnowCostsNothingElse() throws {
        let json = """
        {"timeFormat":"twelveHour","theme":"dark","showOnLockScreen":false,"language":"ja",\
        "defaults":{"volume":0.4,"overridesSilent":true,"toneID":"whisper","snoozeMinutes":5,"vibrates":true}}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.language, AppLanguage.preferred())
        XCTAssertEqual(settings.timeFormat, .twelveHour)
        XCTAssertEqual(settings.defaults.toneID, "whisper")
    }

    // MARK: Weekdays

    func testLocaleOrderedCoversEveryDayExactlyOnce() {
        let ordered = Weekday.localeOrdered
        XCTAssertEqual(ordered.count, 7)
        XCTAssertEqual(Set(ordered).count, 7)
    }

    // MARK: Languages

    func testFirstUseTakesThaiFromAThaiPhoneAndEnglishFromAnyOther() {
        XCTAssertEqual(AppLanguage.preferred(from: ["th-TH", "en-US"]), .thai)
        XCTAssertEqual(AppLanguage.preferred(from: ["th"]), .thai)
        XCTAssertEqual(AppLanguage.preferred(from: ["en-GB", "th-TH"]), .english)
        XCTAssertEqual(AppLanguage.preferred(from: ["ja-JP", "th-TH"]), .english, "Not offered: English")
        XCTAssertEqual(AppLanguage.preferred(from: []), .english)
    }

    func testEveryThaiLineIsThaiAndKeepsItsPlaceholders() {
        let keys = AppLanguage.thaiLines.map { $0.0 }
        XCTAssertEqual(Set(keys).count, keys.count, "A line entered twice")
        for (english, thai) in AppLanguage.thaiLines {
            XCTAssertNotEqual(thai, english, "Untranslated: \(english)")
            XCTAssertTrue(thai.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) },
                          "No Thai in: \(thai)")
            XCTAssertEqual(placeholders(in: thai), placeholders(in: english), "Placeholders differ: \(english)")
        }
    }

    func testLinesTranslateAndTakeTheirNumbers() {
        let thai = AppLanguage.thai
        let english = AppLanguage.english
        XCTAssertEqual(thai("Save"), "บันทึก")
        XCTAssertEqual(thai("Snooze {0} min", 9), "เลื่อนปลุก 9 นาที")
        XCTAssertEqual(english("Snooze {0} min", 9), "Snooze 9 min")
        XCTAssertEqual(english("{0} · used by {1} alarms", "Warm", 2), "Warm · used by 2 alarms")
        XCTAssertEqual(thai("A line with no Thai yet"), "A line with no Thai yet", "Missing: shown in English")
        XCTAssertEqual(english("{0} alarm", "Pay {1}"), "Pay {1} alarm", "An argument is never filled in itself")
    }

    func testALineAroundALiveCountdownSplitsAtItsPlaceholder() {
        let line = AppLanguage.thai.around("Rings in {0} · lock the phone to hear it as the Lock Screen alarm")
        XCTAssertEqual(line.before, "ดังในอีก ")
        XCTAssertTrue(line.after.hasPrefix(" · "), "got \(line.after)")
    }

    func testEveryBundledToneAndOptionReadsInThai() {
        let thai = AppLanguage.thai
        for tone in AlarmTone.bundled {
            XCTAssertNotEqual(tone.name(in: .thai), tone.name, "Untranslated tone: \(tone.name)")
            XCTAssertNotEqual(tone.character(in: .thai), tone.character, "Untranslated: \(tone.character)")
        }
        for label in TimeFormat.allCases.map(\.label) + ThemePreference.allCases.map(\.label) {
            XCTAssertNotEqual(thai(label), label, "Untranslated option: \(label)")
        }
        for name in ["Alarms permission", "Critical Alerts permission"] {
            XCTAssertNotEqual(thai(name), name, "Untranslated: \(name)")
        }
    }

    func testAnImportedToneKeepsItsNameAndItsLineIsReadInThai() {
        var tone = AlarmTone(id: "song.m4a", name: "Siren", character: "Yours · first 29 s rings",
                             peak: 2, fileName: "song.m4a", source: .imported)
        XCTAssertEqual(tone.name(in: .thai), "Siren", "A file's name is the user's, never translated")
        XCTAssertEqual(tone.character(in: .thai), "ของคุณ · ดังเพียง 29 วินาทีแรก")
        XCTAssertEqual(tone.character(in: .english), "Yours · first 29 s rings")

        tone.character = "Yours"
        XCTAssertEqual(tone.character(in: .thai), "ของคุณ")
    }

    // MARK: Helpers

    /// "{0}", "{1}"… in a line, sorted, so two languages can be compared.
    private func placeholders(in text: String) -> [String] {
        var found: [String] = []
        var rest = text[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            found.append(String(rest[open...close]))
            rest = rest[rest.index(after: close)...]
        }
        return found.sorted()
    }

    private func makeAlarm(hour: Int = 7,
                           minute: Int = 0,
                           volume: Double = 0.7,
                           days: Set<Weekday> = []) -> Alarm {
        Alarm(task: "Test alarm",
              hour: hour,
              minute: minute,
              repeatDays: days,
              volume: volume,
              overridesSilent: true,
              toneID: "siren")
    }
}
