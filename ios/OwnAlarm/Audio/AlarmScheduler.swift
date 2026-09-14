import Foundation
import UserNotifications

protocol AlarmScheduling: AnyObject {
    func schedule(_ alarm: Alarm, tone: AlarmTone, showOnLockScreen: Bool)
    func scheduleSnooze(_ alarm: Alarm, tone: AlarmTone, minutes: Int)
    func cancel(_ alarm: Alarm)
    func cancelSnooze(_ alarm: Alarm)
    /// Clears these alarms' schedules before a full re-arm. Snoozes are left alone:
    /// each is a countdown the user is waiting on.
    func cancelAll(_ alarms: [Alarm])

    /// Rings `alarm` for real in `seconds` — the same route, sound and volume as a
    /// scheduled alarm — so the user hears exactly what they have set. `alarm` is a
    /// throwaway copy with its own id (`AlarmStore.testCopy`). One at a time: a new
    /// test replaces a pending one, and a cancel stops one still being set up.
    func scheduleTest(_ alarm: Alarm, tone: AlarmTone, in seconds: TimeInterval)
    func cancelTest()
    /// Whether a test ring can make a sound at all — permission to ring, by AlarmKit
    /// or by a notification with sound.
    func canRingTest() async -> Bool

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
    private let defaults: UserDefaults

    static let categoryIdentifier = "ownalarm.alarm"
    static let snoozeAction = "ownalarm.snooze"
    static let stopAction = "ownalarm.stop"
    static let testIdentifier = "ownalarm.test"

    /// When each one-shot is due, and when each snooze ends. A notification cannot
    /// say it has been answered, so these are how a one-shot is known to be done.
    private static let onceKey = "ownalarm.notifications.once"
    private static let snoozeKey = "ownalarm.notifications.snoozes"

    /// Whether iOS will honour a critical sound's volume. Without Apple's approval it
    /// downgrades one to a plain full-level sound, so until this is known to be true
    /// alarms use the scaled copy that works for everyone.
    static var criticalAlertsEnabled = false

    var onFinished: ((UUID) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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
        let settings = await center.notificationSettings()
        criticalAlertsEnabled = settings.criticalAlertSetting == .enabled
        return settings.authorizationStatus
    }

    static func criticalAlertsGranted() async -> Bool {
        criticalAlertsEnabled = await UNUserNotificationCenter.current()
            .notificationSettings()
            .criticalAlertSetting == .enabled
        return criticalAlertsEnabled
    }

    // MARK: Scheduling

    func schedule(_ alarm: Alarm, tone: AlarmTone, showOnLockScreen: Bool) {
        // A one-shot mid-snooze has rung for today; arming it for tomorrow would
        // outlive the Stop the user is about to give it.
        if alarm.repeatDays.isEmpty, let end = dates(Self.snoozeKey)[alarm.id.uuidString], end > Date() {
            return
        }

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
        if alarm.repeatDays.isEmpty {
            setDate(triggers.first?.1.nextTriggerDate(), for: alarm.id, in: Self.onceKey)
        }
    }

    func scheduleSnooze(_ alarm: Alarm, tone: AlarmTone, minutes: Int) {
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutes * 60),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier(for: alarm, suffix: "snooze"),
            content: content(for: alarm, tone: tone, showOnLockScreen: true),
            trigger: trigger
        )
        center.add(request)
        setDate(Date().addingTimeInterval(trigger.timeInterval), for: alarm.id, in: Self.snoozeKey)
        // Say so straight away, rather than leaving a silent gap until it returns.
        SnoozeNotice.post(alarmID: alarm.id, task: alarm.task, minutes: minutes)
    }

    // MARK: Test ring

    func scheduleTest(_ alarm: Alarm, tone: AlarmTone, in seconds: TimeInterval) {
        cancelTest()
        let request = UNNotificationRequest(
            identifier: Self.testIdentifier,
            content: testContent(for: alarm, tone: tone),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        )
        center.add(request)
    }

    func cancelTest() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.testIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.testIdentifier])
    }

    func canRingTest() async -> Bool {
        let settings = await center.notificationSettings()
        // Provisional notifications arrive quietly; only full permission rings.
        return settings.authorizationStatus == .authorized && settings.soundSetting == .enabled
    }

    /// The alarm's own notification — `alarm` is already the named test copy —
    /// marked as a test: no Stop / Snooze buttons (there is no alarm to act on) and
    /// no alarm id. With the app open the router rings it in the app, as a real
    /// alarm rings there.
    func testContent(for alarm: Alarm, tone: AlarmTone) -> UNNotificationContent {
        let content = self.content(for: alarm, tone: tone, showOnLockScreen: true)
        content.categoryIdentifier = ""
        content.userInfo = ["test": true]
        return content
    }

    // MARK: Content

    func content(for alarm: Alarm, tone: AlarmTone, showOnLockScreen: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alarm.task.isEmpty ? "Alarm" : alarm.task
        content.body = "\(alarm.volumePercent)% · \(tone.name)"
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["alarmID": alarm.id.uuidString]
        content.interruptionLevel = alarm.overridesSilent ? .critical : .timeSensitive

        if alarm.overridesSilent && Self.criticalAlertsEnabled {
            // The alarm's own level, independent of the ringer. An imported tone is
            // not in the bundle, so it plays from a full-level copy in Library/Sounds,
            // where the system looks.
            let name = tone.source == .imported
                ? ScaledSound.fileName(for: tone, volume: 1) ?? tone.fileName
                : tone.fileName
            content.sound = .criticalSoundNamed(UNNotificationSoundName(rawValue: name),
                                                withAudioVolume: Float(alarm.volume))
        } else {
            // A normal notification sound follows the ringer — as does a critical one
            // iOS was not approved to play — so the task's level is baked into the
            // file instead (see `ScaledSound`).
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

    /// Every request an alarm's own schedule can make — all but its snooze.
    private static let scheduleSuffixes = ["once"] + Weekday.allCases.map { "d\($0.rawValue)" }

    func cancel(_ alarm: Alarm) {
        center.removePendingNotificationRequests(
            withIdentifiers: (Self.scheduleSuffixes + ["snooze"]).map { identifier(for: alarm, suffix: $0) }
        )
        setDate(nil, for: alarm.id, in: Self.onceKey)
        setDate(nil, for: alarm.id, in: Self.snoozeKey)
    }

    func cancelSnooze(_ alarm: Alarm) {
        center.removePendingNotificationRequests(
            withIdentifiers: [identifier(for: alarm, suffix: "snooze")]
        )
        center.removeDeliveredNotifications(
            withIdentifiers: [identifier(for: alarm, suffix: "snooze")]
        )
        setDate(nil, for: alarm.id, in: Self.snoozeKey)
        SnoozeNotice.clear(alarmID: alarm.id)
    }

    func cancelAll(_ alarms: [Alarm]) {
        reportFinishedOneShots()
        center.removePendingNotificationRequests(
            withIdentifiers: alarms.flatMap { alarm in
                Self.scheduleSuffixes.map { identifier(for: alarm, suffix: $0) }
            }
        )
    }

    // MARK: Finished one-shots

    /// A one-shot whose time — and any snooze after it — has passed has rung, whether
    /// or not anyone tapped Stop. Reported so the store can switch it off; otherwise
    /// every re-arm would set it for the next day.
    func reportFinishedOneShots(now: Date = Date()) {
        let snoozes = dates(Self.snoozeKey)
        var once = dates(Self.onceKey)
        let finished = once.filter { id, due in
            due <= now && (snoozes[id].map { $0 <= now } ?? true)
        }.keys
        guard !finished.isEmpty else { return }
        finished.forEach { once[$0] = nil }
        defaults.set(once, forKey: Self.onceKey)
        finished.compactMap(UUID.init(uuidString:)).forEach { id in
            setDate(nil, for: id, in: Self.snoozeKey)
            onFinished?(id)
        }
    }

    private func dates(_ key: String) -> [String: Date] {
        defaults.dictionary(forKey: key) as? [String: Date] ?? [:]
    }

    private func setDate(_ date: Date?, for id: UUID, in key: String) {
        var all = dates(key)
        all[id.uuidString] = date
        defaults.set(all, forKey: key)
    }

    private func identifier(for alarm: Alarm, suffix: String) -> String {
        "\(alarm.id.uuidString).\(suffix)"
    }
}
