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

/// What a freshly created alarm starts from: half volume, a 9-minute snooze and
/// vibration on at first — then whatever the user last saved. `AlarmStore.save`
/// copies each saved alarm's volume, sound, snooze and vibration back into these.
struct AlarmDefaults: Codable, Equatable {
    /// Snooze length when snooze is switched on and none has been remembered.
    static let standardSnoozeMinutes = 9

    var volume: Double = 0.50
    var overridesSilent: Bool = true
    var toneID: String = "marimba"
    var snoozeMinutes: Int = AlarmDefaults.standardSnoozeMinutes
    var vibrates: Bool = true

    /// Snooze length when the user switches snooze on. The remembered value is 0
    /// whenever their last alarm had no snooze, which would leave the switch stuck off.
    var snoozeWhenSwitchedOn: Int {
        snoozeMinutes > 0 ? snoozeMinutes : Self.standardSnoozeMinutes
    }
}

extension AlarmDefaults {
    enum CodingKeys: String, CodingKey {
        case volume, overridesSilent, toneID, snoozeMinutes, vibrates
    }

    /// Every field falls back to its factory value when missing, so settings saved
    /// by an older version — before a field existed — still load instead of being
    /// thrown away. Fields since removed (fade-in, louder after snooze) are ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let factory = AlarmDefaults()
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? factory.volume
        overridesSilent = try c.decodeIfPresent(Bool.self, forKey: .overridesSilent) ?? factory.overridesSilent
        toneID = try c.decodeIfPresent(String.self, forKey: .toneID) ?? factory.toneID
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? factory.snoozeMinutes
        vibrates = try c.decodeIfPresent(Bool.self, forKey: .vibrates) ?? factory.vibrates
    }
}

/// The two ways to use OwnAlarm. Free is capped at a handful of alarms; Premium, kept
/// through a subscription, has no limit. `AlarmStore.canAddAlarm` is what actually
/// enforces the cap — this only says what each tier allows.
enum SubscriptionTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case free
    case premium

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: return "Free"
        case .premium: return "Premium"
        }
    }

    /// How many alarms this tier may keep at once. `nil` means no limit.
    var alarmLimit: Int? {
        switch self {
        case .free: return AppSettings.maxFreeAlarms
        case .premium: return nil
        }
    }
}

/// First launch follows the phone: its region decides 24-hour or AM/PM, its light or
/// dark mode the theme, and its language the app's — Thai, or else English. Each can
/// be pinned in Settings.
struct AppSettings: Codable, Equatable {
    /// The most alarms a Free account may keep at once. Premium has no limit.
    static let maxFreeAlarms = 3

    var timeFormat: TimeFormat = .automatic
    var theme: ThemePreference = .automatic
    var showOnLockScreen: Bool = true
    var defaults = AlarmDefaults()
    var language: AppLanguage = .preferred()
    var subscriptionTier: SubscriptionTier = .free
}

extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case timeFormat, theme, showOnLockScreen, defaults, language, subscriptionTier
    }

    /// Each field falls back to its first-launch value when missing, so settings saved
    /// by an older version — before there was a language to choose — still load, and
    /// take the phone's language.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let factory = AppSettings()
        timeFormat = try c.decodeIfPresent(TimeFormat.self, forKey: .timeFormat) ?? factory.timeFormat
        theme = try c.decodeIfPresent(ThemePreference.self, forKey: .theme) ?? factory.theme
        showOnLockScreen = try c.decodeIfPresent(Bool.self, forKey: .showOnLockScreen) ?? factory.showOnLockScreen
        defaults = try c.decodeIfPresent(AlarmDefaults.self, forKey: .defaults) ?? factory.defaults
        // A language this version does not know, saved by a newer one, falls back too
        // rather than costing every other setting.
        language = (try? c.decodeIfPresent(AppLanguage.self, forKey: .language)) ?? factory.language
        // Likewise a tier this version does not know — and a save from before
        // subscriptions existed, which has none at all — falls back to Free rather
        // than granting Premium for nothing.
        subscriptionTier = (try? c.decodeIfPresent(SubscriptionTier.self, forKey: .subscriptionTier))
            ?? factory.subscriptionTier
    }
}

// MARK: - Formatting

enum TimeText {
    /// Formats an alarm's time under the app's own format setting rather than the
    /// device's, so the Clock preference actually governs every screen.
    static func string(hour: Int,
                       minute: Int,
                       format: TimeFormat,
                       language: AppLanguage,
                       locale: Locale = .current,
                       calendar: Calendar = .current) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = calendar.date(from: components) ?? Date()

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        // In the app's language; 12- or 24-hour by the Clock setting, which
        // resolves "Match device" against the phone's own region.
        formatter.locale = language.locale(from: locale)
        formatter.setLocalizedDateFormatFromTemplate(format.uses24Hour(in: locale) ? "Hmm" : "hmm")
        return formatter.string(from: date)
    }

    /// "in 6h 12m" — used for the next-alarm banner.
    static func relative(to date: Date, from now: Date = Date(), language: AppLanguage) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours == 0 { return language("in {0}m", minutes) }
        if minutes == 0 { return language("in {0}h", hours) }
        return language("in {0}h {1}m", hours, minutes)
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
