import Foundation
import UserNotifications

protocol AlarmScheduling: AnyObject {
    func schedule(_ alarm: Alarm, tone: AlarmTone, showOnLockScreen: Bool)
    func scheduleSnooze(_ alarm: Alarm, minutes: Int)
    func cancel(_ alarm: Alarm)
    func cancelSnooze(_ alarm: Alarm)
    func cancelAll()

    /// Set by the store. Called with an alarm's id when the system reports that the
    /// alarm has rung and been stopped. Only AlarmKit can tell; other schedulers
    /// never call it.
    var onFinished: ((UUID) -> Void)? { get set }
}

extension AlarmScheduling {
    var onFinished: ((UUID) -> Void)? {
        get { nil }
        set {}
    }
}

/// What the user did with an alarm notification: tapped it, or one of its buttons.
enum AlarmResponse: Equatable {
    case open, snooze, stop

    init(actionIdentifier: String?) {
        switch actionIdentifier {
        case AlarmScheduler.snoozeAction:
            self = .snooze
        case AlarmScheduler.stopAction, UNNotificationDismissActionIdentifier:
            self = .stop
        default:
            self = .open
        }
    }
}

/// Schedules alarms as notifications — the route on iOS 16–25, and the fallback on
/// iOS 26 when AlarmKit cannot be used.
///
/// A terminated app cannot wake up and play audio, so the level has to ride on the
/// notification itself. `UNNotificationSound.criticalSoundNamed(_:withAudioVolume:)`
/// plays at a volume the app chooses and through Silent, but needs Apple's Critical
/// Alerts entitlement; otherwise the task's level is baked into the sound file
/// (`ScaledSound`) and plays relative to the ringer.
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
        // Say so straight away, rather than leaving a silent gap until it returns.
        SnoozeNotice.post(alarmID: alarm.id, task: alarm.task, minutes: minutes)
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
            // A normal notification sound follows the ringer, so the task's level is
            // baked into the file instead: a 30% task gets a file 30% as loud.
            let name = ScaledSound.fileName(for: tone, volume: alarm.volume) ?? tone.fileName
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: name))
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
        SnoozeNotice.clear(alarmID: alarm.id)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    private func identifier(for alarm: Alarm, suffix: String) -> String {
        "\(alarm.id.uuidString).\(suffix)"
    }
}
