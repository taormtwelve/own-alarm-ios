import Foundation

// SwiftUI is only needed for the one `ColorScheme` bridge below. Keeping the import
// conditional lets the model layer compile — and be tested — off Apple platforms.
#if canImport(SwiftUI)
import SwiftUI
#endif

/// How clocks are rendered app-wide. `.automatic` — the first-launch default —
/// follows the phone's region; the other two pin 24-hour or AM / PM.
enum TimeFormat: String, Codable, CaseIterable, Identifiable {
    case twentyFourHour
    case twelveHour
    case automatic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .twentyFourHour: return "24-hour"
        case .twelveHour: return "AM / PM"
        case .automatic: return "Match device"
        }
    }

    /// Resolves `.automatic` against a locale — injectable so it can be tested.
    func uses24Hour(in locale: Locale = .current) -> Bool {
        switch self {
        case .twentyFourHour: return true
        case .twelveHour: return false
        case .automatic:
            let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)
            return template?.contains("a") == false
        }
    }

    var uses24Hour: Bool { uses24Hour(in: .current) }
}

enum ThemePreference: String, Codable, CaseIterable, Identifiable {
    case light, dark, automatic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .automatic: return "Auto"
        }
    }

    #if canImport(SwiftUI)
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .automatic: return nil
        }
    }
    #endif
}

/// What a freshly created alarm starts from: half volume, fade-in off, a 9-minute
/// snooze at first — then whatever the user last saved. `AlarmStore.save` copies
/// each saved alarm's volume, sound, snooze and fade-in back into these.
struct AlarmDefaults: Codable, Equatable {
    /// Fade length when fade-in is switched on and none has been remembered.
    static let standardFadeInSeconds = 10
    /// Snooze length when snooze is switched on and none has been remembered.
    static let standardSnoozeMinutes = 9

    var volume: Double = 0.50
    var fadeInSeconds: Int = 0
    var overridesSilent: Bool = true
    var toneID: String = "marimba"
    var snoozeMinutes: Int = AlarmDefaults.standardSnoozeMinutes
    var louderAfterSnooze: Bool = true
    var vibrates: Bool = true

    /// Fade length when the user switches fade-in on. The remembered value is 0
    /// whenever their last alarm had no fade, which would leave the switch stuck off.
    var fadeInWhenSwitchedOn: Int {
        fadeInSeconds > 0 ? fadeInSeconds : Self.standardFadeInSeconds
    }

    /// Snooze length when the user switches snooze on — same reasoning.
    var snoozeWhenSwitchedOn: Int {
        snoozeMinutes > 0 ? snoozeMinutes : Self.standardSnoozeMinutes
    }
}

extension AlarmDefaults {
    enum CodingKeys: String, CodingKey {
        case volume, fadeInSeconds, overridesSilent, toneID, snoozeMinutes, louderAfterSnooze, vibrates
    }

    /// Every field falls back to its factory value when missing, so settings saved
    /// by an older version — before a field existed — still load instead of being
    /// thrown away.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let factory = AlarmDefaults()
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? factory.volume
        fadeInSeconds = try c.decodeIfPresent(Int.self, forKey: .fadeInSeconds) ?? factory.fadeInSeconds
        overridesSilent = try c.decodeIfPresent(Bool.self, forKey: .overridesSilent) ?? factory.overridesSilent
        toneID = try c.decodeIfPresent(String.self, forKey: .toneID) ?? factory.toneID
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? factory.snoozeMinutes
        louderAfterSnooze = try c.decodeIfPresent(Bool.self, forKey: .louderAfterSnooze) ?? factory.louderAfterSnooze
        vibrates = try c.decodeIfPresent(Bool.self, forKey: .vibrates) ?? factory.vibrates
    }
}

/// First launch follows the phone: its region decides 24-hour or AM/PM, and its
/// light or dark mode decides the theme. Either can be pinned in Settings.
struct AppSettings: Codable, Equatable {
    var timeFormat: TimeFormat = .automatic
    var theme: ThemePreference = .automatic
    var showOnLockScreen: Bool = true
    var defaults = AlarmDefaults()
}

// MARK: - Formatting

enum TimeText {
    /// Formats an alarm's time under the app's own format setting rather than the
    /// device's, so the Clock preference actually governs every screen.
    static func string(hour: Int,
                       minute: Int,
                       format: TimeFormat,
                       locale: Locale = .current,
                       calendar: Calendar = .current) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = calendar.date(from: components) ?? Date()

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(format.uses24Hour(in: locale) ? "Hmm" : "hmm")
        return formatter.string(from: date)
    }

    /// "in 6h 12m" — used for the next-alarm banner.
    static func relative(to date: Date, from now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours == 0 { return "in \(minutes)m" }
        if minutes == 0 { return "in \(hours)h" }
        return "in \(hours)h \(minutes)m"
    }
}

// MARK: - Storage

extension AppSettings {
    /// Where `AlarmStore` keeps the settings. Also read by code that runs without a
    /// store, such as the Lock Screen snooze.
    static let storageKey = "ownalarm.settings"

    /// The saved settings, or the defaults if nothing has been saved yet.
    static func stored(in defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }
}
