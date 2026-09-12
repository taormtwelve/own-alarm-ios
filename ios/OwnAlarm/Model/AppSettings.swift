import Foundation

// SwiftUI is only needed for the one `ColorScheme` bridge below. Keeping the import
// conditional lets the model layer compile — and be tested — off Apple platforms.
#if canImport(SwiftUI)
import SwiftUI
#endif

/// How clocks are rendered app-wide. Defaults to 24-hour, per the approved design,
/// but `.automatic` is offered so the app can follow the device region instead.
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

/// What a freshly created alarm starts from.
struct AlarmDefaults: Codable, Equatable {
    var volume: Double = 0.70
    var fadeInSeconds: Int = 30
    var overridesSilent: Bool = true
    var toneID: String = "marimba"
    var snoozeMinutes: Int = 9
    var louderAfterSnooze: Bool = true
}

struct AppSettings: Codable, Equatable {
    var timeFormat: TimeFormat = .twentyFourHour
    var theme: ThemePreference = .light
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
