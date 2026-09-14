import Foundation

// MARK: - Weekday

enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Single letter for the day pills, in the app's language.
    func narrowSymbol(in language: AppLanguage) -> String {
        language.calendar().veryShortWeekdaySymbols[rawValue - 1]
    }

    /// "Mon", "Tue"… in the app's language.
    func shortSymbol(in language: AppLanguage) -> String {
        language.calendar().shortWeekdaySymbols[rawValue - 1]
    }

    /// Weekdays in the order this locale starts its week.
    static var localeOrdered: [Weekday] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { offset in
            Weekday(rawValue: (first - 1 + offset) % 7 + 1)!
        }
    }
}

// MARK: - Tone

struct AlarmTone: Identifiable, Codable, Equatable, Hashable {
    enum Source: String, Codable {
        case bundled      // ships with the app
        case system       // chosen from the iOS sound library
        case imported     // from Music or Files
    }

    var id: String
    var name: String
    /// Plain-language character shown under the name — "Harsh", "Warm", "Long decay".
    var character: String
    /// Relative peak loudness of the recording itself, 1...3. Two tones at the same
    /// volume setting do not land equally loud, and the meter in the list says so.
    var peak: Int
    var fileName: String
    var source: Source

    static let bundled: [AlarmTone] = [
        .init(id: "siren", name: "Siren", character: "Harsh · peaks fast", peak: 3,
              fileName: "siren.wav", source: .bundled),
        .init(id: "marimba", name: "Marimba", character: "Warm · even", peak: 2,
              fileName: "marimba.wav", source: .bundled),
        .init(id: "soft-bell", name: "Soft bell", character: "Quiet · long decay", peak: 1,
              fileName: "soft-bell.wav", source: .bundled),
        .init(id: "whisper", name: "Whisper", character: "Barely there · for night tasks", peak: 1,
              fileName: "whisper.wav", source: .bundled),
    ]

    static var fallback: AlarmTone { bundled[1] }

    static func tone(id: String, in library: [AlarmTone]) -> AlarmTone {
        library.first { $0.id == id } ?? fallback
    }
}

extension AlarmTone {
    /// The name as shown: a bundled tone's in the app's language; an imported tone
    /// keeps its file's name.
    func name(in language: AppLanguage) -> String {
        source == .bundled ? language(name) : name
    }

    /// The line under the name, in the app's language. An imported tone's was saved
    /// in English when it was added — "Yours", or "Yours · first 29 s rings" — and
    /// is read back in whichever language is chosen now.
    func character(in language: AppLanguage) -> String {
        let prefix = "Yours · first ", suffix = " s rings"
        if source == .imported, character.hasPrefix(prefix), character.hasSuffix(suffix),
           let seconds = Int(character.dropFirst(prefix.count).dropLast(suffix.count)) {
            return language("Yours · first {0} s rings", seconds)
        }
        return language(character)
    }
}

// MARK: - Alarm

struct Alarm: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var task: String
    var hour: Int
    var minute: Int
    var repeatDays: Set<Weekday>
    var isEnabled: Bool = true

    /// The whole point of the app: each alarm owns its level, 0...1, independent of
    /// the ringer. Persisted per alarm, never read from the system volume.
    var volume: Double
    /// Ring even when the phone is muted or in a Focus. Requires Critical Alerts.
    var overridesSilent: Bool

    var toneID: String
    var snoozeMinutes: Int = 9
    /// Buzz while the alarm rings in the app. On the Lock Screen iOS decides, from its
    /// own Sounds & Haptics settings — no API lets an app choose there.
    var vibrates: Bool = true

    var volumePercent: Int { Int((volume * 100).rounded()) }

    /// Next fire date, honouring the repeat set. Nil only if disabled.
    func nextFireDate(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        if repeatDays.isEmpty {
            return calendar.nextDate(after: date, matching: components,
                                     matchingPolicy: .nextTime)
        }
        return repeatDays
            .compactMap { day -> Date? in
                var c = components
                c.weekday = day.rawValue
                return calendar.nextDate(after: date, matching: c, matchingPolicy: .nextTime)
            }
            .min()
    }

    /// "Mon – Fri", "Every day", "Tue, Thu", or "Once" — in the app's language.
    func repeatSummary(in language: AppLanguage) -> String {
        if repeatDays.isEmpty { return language("Once") }
        if repeatDays.count == 7 { return language("Every day") }

        let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        if repeatDays == weekdays { return language("Mon – Fri") }
        if repeatDays == [.saturday, .sunday] { return language("Weekends") }

        return repeatDays.sorted().map { $0.shortSymbol(in: language) }.joined(separator: ", ")
    }

    /// A new alarm opens on the current time — the picker starts at "now" and the
    /// user scrolls forward — carrying the choices remembered from the last save.
    static func newAlarm(from defaults: AlarmDefaults,
                         at now: Date = Date(),
                         calendar: Calendar = .current) -> Alarm {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return Alarm(
            task: "",
            hour: parts.hour ?? 7,
            minute: parts.minute ?? 0,
            repeatDays: [],
            volume: defaults.volume,
            overridesSilent: defaults.overridesSilent,
            toneID: defaults.toneID,
            snoozeMinutes: defaults.snoozeMinutes,
            vibrates: defaults.vibrates
        )
    }
}

// MARK: - Loading older saves

extension Alarm {
    enum CodingKeys: String, CodingKey {
        case id, task, hour, minute, repeatDays, isEnabled, volume
        case overridesSilent, toneID, snoozeMinutes, vibrates
    }

    /// Alarms are saved to disk, and a field added in a later version is missing from
    /// every alarm saved before it. Swift's generated decoding would then reject the
    /// whole file — and the app would start with no alarms. Fields added after the
    /// first release are therefore read leniently. Fields since removed — fade-in,
    /// louder after snooze — are simply ignored in older saves.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        task = try c.decode(String.self, forKey: .task)
        hour = try c.decode(Int.self, forKey: .hour)
        minute = try c.decode(Int.self, forKey: .minute)
        repeatDays = try c.decode(Set<Weekday>.self, forKey: .repeatDays)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        volume = try c.decode(Double.self, forKey: .volume)
        overridesSilent = try c.decode(Bool.self, forKey: .overridesSilent)
        toneID = try c.decode(String.self, forKey: .toneID)
        snoozeMinutes = try c.decode(Int.self, forKey: .snoozeMinutes)
        // Added later: older alarms vibrate, as they always did.
        vibrates = try c.decodeIfPresent(Bool.self, forKey: .vibrates) ?? true
    }
}

// MARK: - Sample content

extension Alarm {
    /// Sample alarms for UI tests and previews. Never given to real users — a new
    /// install starts empty.
    static let starter: [Alarm] = [
        Alarm(task: "Morning run", hour: 6, minute: 45,
              repeatDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
              volume: 0.85, overridesSilent: true, toneID: "siren"),
        Alarm(task: "Take medication", hour: 7, minute: 30,
              repeatDays: Set(Weekday.allCases),
              volume: 0.30, overridesSilent: true, toneID: "soft-bell"),
        Alarm(task: "Stand-up call", hour: 13, minute: 15,
              repeatDays: [.tuesday, .thursday],
              volume: 0.55, overridesSilent: false, toneID: "marimba"),
        Alarm(task: "Wind down & charge phone", hour: 22, minute: 0,
              repeatDays: [.sunday], isEnabled: false,
              volume: 0.15, overridesSilent: false, toneID: "whisper"),
    ]
}
