import Foundation
import UserNotifications

/// The notification that appears the moment an alarm is snoozed — "Morning run ·
/// snoozed", "Rings again at 07:39 · in 9 min" — so a snooze is never invisible,
/// whether or not the Lock Screen countdown shows.
///
/// One per alarm: snoozing again replaces it, and stopping the alarm clears it.
enum SnoozeNotice {
    static func identifier(for alarmID: UUID) -> String {
        "\(alarmID.uuidString).snoozed"
    }

    static func post(alarmID: UUID, task: String, minutes: Int, now: Date = Date()) {
        let content = UNMutableNotificationContent()
        content.title = SnoozeText.title(task: task)
        content.body = SnoozeText.body(minutes: minutes, now: now,
                                       format: AppSettings.stored().timeFormat)
        content.threadIdentifier = "ownalarm.snoozed"
        // Informational: silent, so it never feels like the alarm ringing again.
        content.sound = nil
        content.interruptionLevel = .active

        let request = UNNotificationRequest(identifier: identifier(for: alarmID),
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func clear(alarmID: UUID) {
        let ids = [identifier(for: alarmID)]
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
