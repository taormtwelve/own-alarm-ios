import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

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
        // A notification only shows the app icon by itself; the snooze symbol rides
        // along as an attachment, so the notice reads as a snooze at a glance.
        if let icon = snoozeIcon() { content.attachments = [icon] }

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

    /// The "zzz" symbol in the app's amber on its dark ink, as a PNG the notification
    /// system takes over. Nil where it cannot be drawn; the notice still posts.
    private static func snoozeIcon() -> UNNotificationAttachment? {
        #if canImport(UIKit)
        let side: CGFloat = 256
        let size = CGSize(width: side, height: side)
        let configuration = UIImage.SymbolConfiguration(pointSize: 132, weight: .bold)
        guard let symbol = UIImage(systemName: "zzz", withConfiguration: configuration)?
            .withTintColor(UIColor(red: 1.0, green: 0.69, blue: 0.23, alpha: 1), renderingMode: .alwaysOriginal)
        else { return nil }

        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: 0.07, green: 0.06, blue: 0.05, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 56).fill()
            symbol.draw(in: CGRect(x: (side - symbol.size.width) / 2,
                                   y: (side - symbol.size.height) / 2,
                                   width: symbol.size.width,
                                   height: symbol.size.height))
        }

        // The system moves the file into its own store, so each notice gets its own.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ownalarm-snooze-\(UUID().uuidString).png")
        guard let data = image.pngData(), (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "snooze", url: url, options: nil)
        #else
        return nil
        #endif
    }
}
