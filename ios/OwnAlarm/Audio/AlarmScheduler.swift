import Foundation
import UserNotifications

protocol AlarmScheduling {
    func schedule(_ alarm: Alarm, tone: AlarmTone, showOnLockScreen: Bool)
    func scheduleSnooze(_ alarm: Alarm, minutes: Int)
    func cancel(_ alarm: Alarm)
    func cancelSnooze(_ alarm: Alarm)
    func cancelAll()
}

/// Schedules alarms as notifications.
///
/// This is where per-task volume becomes real. iOS will not let a terminated app
/// wake up and play audio, so the level has to ride on the notification itself —
/// `UNNotificationSound.criticalSoundNamed(_:withAudioVolume:)` is the only API that
/// plays at a volume the app chooses rather than the one the ringer is set to, and
/// it is also what lets the sound through Silent and Focus. It requires the
/// **Critical Alerts** entitlement from Apple; without it we fall back to a normal
/// notification sound, which obeys the ringer and the mute switch.
final class AlarmScheduler: AlarmScheduling {
    private let center = UNUserNotificationCenter.current()

    static let categoryIdentifier = "ownalarm.alarm"
    static let snoozeAction = "ownalarm.snooze"
    static let stopAction = "ownalarm.stop"

    /// Registers the Stop / Snooze buttons that appear on the Lock Screen alert.
    static func registerCategories() {
        let snooze = UNNotificationAction(
            identifier: snoozeAction,
            title: "Snooze",
            options: []
        )
        let stop = UNNotificationAction(
            identifier: stopAction,
            title: "Stop",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [snooze, stop],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Critical alerts must be requested explicitly and are only granted to apps
    /// Apple has approved for the entitlement.
    static func requestAuthorization() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        var options: UNAuthorizationOptions = [.alert, .sound, .badge]
        options.insert(.criticalAlert)
        _ = try? await center.requestAuthorization(options: options)
        return await center.notificationSettings().authorizationStatus
    }

    static func criticalAlertsGranted() async -> Bool {
        await UNUserNotificationCenter.current()
            .notificationSettings()
            .criticalAlertSetting == .enabled
    }

    // MARK: Scheduling

    func schedule(_ alarm: Alarm, tone: AlarmTone, showOnLockScreen: Bool) {
        // A repeating alarm becomes one request per weekday; a one-shot becomes one.
        let triggers: [(String, UNCalendarNotificationTrigger)] = {
            if alarm.repeatDays.isEmpty {
                var components = DateComponents()
                components.hour = alarm.hour
                components.minute = alarm.minute
                return [(identifier(for: alarm, suffix: "once"),
                         UNCalendarNotificationTrigger(dateMatching: components, repeats: false))]
            }
            return alarm.repeatDays.sorted().map { day in
                var components = DateComponents()
                components.hour = alarm.hour
                components.minute = alarm.minute
                components.weekday = day.rawValue
                return (identifier(for: alarm, suffix: "d\(day.rawValue)"),
                        UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
            }
        }()

        for (id, trigger) in triggers {
            let request = UNNotificationRequest(
                identifier: id,
                content: content(for: alarm, tone: tone, showOnLockScreen: showOnLockScreen),
                trigger: trigger
            )
            center.add(request)
        }
    }

    func scheduleSnooze(_ alarm: Alarm, minutes: Int) {
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutes * 60),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier(for: alarm, suffix: "snooze"),
            content: content(for: alarm,
                             tone: AlarmTone.tone(id: alarm.toneID, in: AlarmTone.bundled),
                             showOnLockScreen: true),
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: Content

    func content(for alarm: Alarm, tone: AlarmTone, showOnLockScreen: Bool) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alarm.task.isEmpty ? "Alarm" : alarm.task
        content.body = "\(alarm.volumePercent)% · \(tone.name)"
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["alarmID": alarm.id.uuidString]
        content.interruptionLevel = alarm.overridesSilent ? .critical : .timeSensitive

        let soundName = UNNotificationSoundName(rawValue: tone.fileName)
        if alarm.overridesSilent {
            // The alarm's own level, independent of the ringer.
            content.sound = .criticalSoundNamed(soundName, withAudioVolume: Float(alarm.volume))
        } else {
            content.sound = UNNotificationSound(named: soundName)
        }

        if !showOnLockScreen {
            // Nothing on the Lock Screen: the alarm only takes over inside the app.
            // The request still has to exist so the app is woken; it just stays quiet
            // and unlisted until opened.
            content.title = ""
            content.body = ""
            content.sound = nil
        }
        return content
    }

    // MARK: Cancellation

    func cancel(_ alarm: Alarm) {
        let ids = ["once", "snooze"] + Weekday.allCases.map { "d\($0.rawValue)" }
        center.removePendingNotificationRequests(
            withIdentifiers: ids.map { identifier(for: alarm, suffix: $0) }
        )
    }

    func cancelSnooze(_ alarm: Alarm) {
        center.removePendingNotificationRequests(
            withIdentifiers: [identifier(for: alarm, suffix: "snooze")]
        )
        center.removeDeliveredNotifications(
            withIdentifiers: [identifier(for: alarm, suffix: "snooze")]
        )
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    private func identifier(for alarm: Alarm, suffix: String) -> String {
        "\(alarm.id.uuidString).\(suffix)"
    }
}
