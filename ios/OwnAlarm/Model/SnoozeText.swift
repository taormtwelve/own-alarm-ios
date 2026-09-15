import Foundation

/// The words of the snooze notice — "Morning run · snoozed", "Rings again at 07:39 ·
/// in 9 min". Kept free of UIKit and UserNotifications so it is tested anywhere.
enum SnoozeText {
    static func title(task: String, language: AppLanguage) -> String {
        task.isEmpty ? language("Alarm snoozed") : language("{0} · snoozed", task)
    }

    static func body(minutes: Int,
                     now: Date,
                     format: TimeFormat,
                     language: AppLanguage,
                     locale: Locale = .current,
                     calendar: Calendar = .current) -> String {
        let returns = now.addingTimeInterval(TimeInterval(minutes * 60))
        let parts = calendar.dateComponents([.hour, .minute], from: returns)
        let time = TimeText.string(hour: parts.hour ?? 0, minute: parts.minute ?? 0,
                                   format: format, language: language,
                                   locale: locale, calendar: calendar)
        return language("Rings again at {0} · in {1} min", time, minutes)
    }
}
