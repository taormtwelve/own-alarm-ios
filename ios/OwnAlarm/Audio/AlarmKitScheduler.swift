import Foundation
import SwiftUI

extension AlarmScheduler {
    /// Real alarms where the OS offers them, notifications otherwise.
    static func makeDefault() -> AlarmScheduling {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmKitScheduler(fallback: AlarmScheduler())
        }
        #endif
        return AlarmScheduler()
    }
}

#if canImport(AlarmKit)
import AlarmKit
import ActivityKit

/// Schedules real alarms through AlarmKit (iOS 26+).
///
/// This is what makes an alarm *ring* instead of posting a notification: AlarmKit
/// alarms take over the Lock Screen, keep sounding until stopped, and break through
/// Silent and Focus — the treatment the Clock app gets. No special entitlement, just
/// the user's permission.
///
/// AlarmKit has no volume parameter, so the task's level is baked into the sound
/// file (`ScaledSound`). It plays at the phone's alarm level, and a 30% task rings
/// with a file 30% as loud.
///
/// Snooze is an AlarmKit countdown, drawn live on the Lock Screen and in the Dynamic
/// Island by the OwnAlarmWidgets extension. AlarmKit also reveals when an alarm has
/// rung and been stopped — it drops out of `alarmUpdates` — which is how a one-shot
/// alarm gets switched off in the app. A snoozed alarm is still counting down, so it
/// stays on until the user finally taps Stop.
///
/// Note: our model type `Alarm` shadows AlarmKit's, so AlarmKit's is always written
/// `AlarmKit.Alarm` here.
@available(iOS 26.0, *)
final class AlarmKitScheduler: AlarmScheduling {
    var onFinished: ((UUID) -> Void)? {
        didSet { deliverPending() }
    }

    private static let armedKey = "ownalarm.alarmkit.armed"

    private let manager = AlarmManager.shared
    private let fallback: AlarmScheduling
    private let defaults: UserDefaults
    private let lock = NSLock()
    /// Alarms handed to AlarmKit. One that vanishes from AlarmKit's list without us
    /// cancelling it has rung and been stopped. Persisted, so alarms stopped while
    /// the app was not running are still caught on the next launch.
    private var armed: Set<UUID>
    private var pending: [UUID] = []
    private var updates: Task<Void, Never>?

    init(fallback: AlarmScheduling, defaults: UserDefaults = .standard) {
        self.fallback = fallback
        self.defaults = defaults
        armed = Set((defaults.stringArray(forKey: Self.armedKey) ?? [])
            .compactMap(UUID.init(uuidString:)))

        // Anything armed last time and gone now finished while the app was closed.
        if let present = try? manager.alarms.map(\.id) {
            let finished = armed.subtracting(present)
            armed.subtract(finished)
            pending = Array(finished)
            persistArmed()
        }

        updates = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                self?.reconcile(present: Set(alarms.map(\.id)))
            }
        }
    }

    deinit {
        updates?.cancel()
    }

    static func requestAuthorization() async {
        _ = try? await AlarmManager.shared.requestAuthorization()
    }

    private var isAuthorized: Bool {
        manager.authorizationState == .authorized
    }

    // MARK: AlarmScheduling

    func schedule(_ alarm: Alarm, tone: AlarmTone, showOnLockScreen: Bool) {
        // No permission — or the user wants nothing on the Lock Screen, which an
        // AlarmKit alarm cannot honour — means notifications, which can stay hidden.
        guard isAuthorized, showOnLockScreen else {
            fallback.schedule(alarm, tone: tone, showOnLockScreen: showOnLockScreen)
            return
        }
        // Snoozing or ringing right now: leave it be. Scheduling again would wipe
        // the countdown the user is waiting on.
        if isActive(alarm.id) { return }

        let configuration = makeConfiguration(for: alarm, tone: tone)
        Task { [weak self, manager, fallback] in
            do {
                _ = try await manager.schedule(id: alarm.id, configuration: configuration)
                self?.setArmed(alarm.id, true)
            } catch {
                print("AlarmKit refused \(alarm.task): \(error). Using a notification instead.")
                fallback.schedule(alarm, tone: tone, showOnLockScreen: showOnLockScreen)
            }
        }
    }

    func scheduleSnooze(_ alarm: Alarm, minutes: Int) {
        // AlarmKit snoozes by itself (the countdown below). This path is only reached
        // from the in-app ringing screen, which the notification route drives.
        fallback.scheduleSnooze(alarm, minutes: minutes)
    }

    func cancel(_ alarm: Alarm) {
        // Disarm first, so the update that follows is not read as "it rang".
        setArmed(alarm.id, false)
        try? manager.cancel(id: alarm.id)
        fallback.cancel(alarm)
    }

    func cancelSnooze(_ alarm: Alarm) {
        fallback.cancelSnooze(alarm)
    }

    func cancelAll() {
        // Alarms are re-armed on every launch; that must not cancel one that is
        // snoozing or ringing at this moment.
        for scheduled in (try? manager.alarms) ?? [] {
            guard case .scheduled = scheduled.state else { continue }
            setArmed(scheduled.id, false)
            try? manager.cancel(id: scheduled.id)
        }
        fallback.cancelAll()
    }

    // MARK: Tracking

    private func isActive(_ id: UUID) -> Bool {
        guard let alarm = (try? manager.alarms)?.first(where: { $0.id == id }) else { return false }
        if case .scheduled = alarm.state { return false }
        return true
    }

    private func reconcile(present: Set<UUID>) {
        lock.lock()
        let finished = armed.subtracting(present)
        armed.subtract(finished)
        lock.unlock()
        guard !finished.isEmpty else { return }
        persistArmed()
        finished.forEach(report)
    }

    private func report(_ id: UUID) {
        if let onFinished {
            onFinished(id)
        } else {
            lock.lock()
            pending.append(id)
            lock.unlock()
        }
    }

    private func deliverPending() {
        guard let onFinished else { return }
        lock.lock()
        let ids = pending
        pending = []
        lock.unlock()
        ids.forEach(onFinished)
    }

    private func setArmed(_ id: UUID, _ isArmed: Bool) {
        lock.lock()
        if isArmed { armed.insert(id) } else { armed.remove(id) }
        lock.unlock()
        persistArmed()
    }

    private func persistArmed() {
        lock.lock()
        let ids = armed.map(\.uuidString)
        lock.unlock()
        defaults.set(ids, forKey: Self.armedKey)
    }

    // MARK: Configuration

    private func makeConfiguration(for alarm: Alarm, tone: AlarmTone)
        -> AlarmManager.AlarmConfiguration<OwnAlarmMetadata> {
        let title = alarm.task.isEmpty ? "Alarm" : alarm.task
        let snoozes = alarm.snoozeMinutes > 0

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource("\(title)"),
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
            secondaryButton: snoozes
                ? AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")
                : nil,
            secondaryButtonBehavior: snoozes ? .countdown : nil
        )

        // While snoozed, the widget extension draws a live countdown from these.
        let presentation = snoozes
            ? AlarmPresentation(
                alert: alert,
                countdown: AlarmPresentation.Countdown(
                    title: "Snoozed",
                    pauseButton: AlarmButton(text: "Pause", textColor: .white,
                                             systemImageName: "pause.fill")),
                paused: AlarmPresentation.Paused(
                    title: "Paused",
                    resumeButton: AlarmButton(text: "Resume", textColor: .white,
                                              systemImageName: "play.fill")))
            : AlarmPresentation(alert: alert)

        let attributes = AlarmAttributes<OwnAlarmMetadata>(
            presentation: presentation,
            metadata: OwnAlarmMetadata(task: title, volumePercent: alarm.volumePercent),
            tintColor: Color(hex: 0xE8940F)
        )

        let time = AlarmKit.Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
        let repeats: AlarmKit.Alarm.Schedule.Relative.Recurrence = alarm.repeatDays.isEmpty
            ? .never
            : .weekly(alarm.repeatDays.sorted().map(\.localeWeekday))

        let sound: AlertConfiguration.AlertSound = ScaledSound
            .fileName(for: tone, volume: alarm.volume)
            .map { .named($0) } ?? .default

        return AlarmManager.AlarmConfiguration(
            countdownDuration: snoozes
                ? AlarmKit.Alarm.CountdownDuration(
                    preAlert: nil,
                    postAlert: TimeInterval(alarm.snoozeMinutes * 60))
                : nil,
            schedule: .relative(.init(time: time, repeats: repeats)),
            attributes: attributes,
            // The app's own code behind the Lock Screen buttons: Snooze starts the
            // countdown and posts the "snoozed" notice; Stop clears it.
            stopIntent: StopAlarmIntent(alarmID: alarm.id),
            secondaryIntent: snoozes
                ? SnoozeAlarmIntent(alarmID: alarm.id, task: title, minutes: alarm.snoozeMinutes)
                : nil,
            sound: sound
        )
    }
}

@available(iOS 26.0, *)
private extension Weekday {
    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday: return .sunday
        case .monday: return .monday
        case .tuesday: return .tuesday
        case .wednesday: return .wednesday
        case .thursday: return .thursday
        case .friday: return .friday
        case .saturday: return .saturday
        }
    }
}
#endif

/// The permission that lets an alarm ring on the Lock Screen and through Silent:
/// AlarmKit's on iOS 26 and later, Critical Alerts before that.
///
/// Both are requested on first launch. Critical Alerts only ever shows a prompt for
/// apps Apple has approved for the entitlement; for everyone else iOS skips the
/// question silently, which is why iOS 26's AlarmKit is the route that matters.
enum RingPermission {
    /// True where every alarm rings through Silent and Focus on its own (AlarmKit,
    /// iOS 26+). A per-alarm "override Silent" choice means nothing there, so the
    /// switch for it is hidden.
    static var alwaysRingsThroughSilent: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    static var name: String {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return "Alarms permission" }
        #endif
        return "Critical Alerts permission"
    }

    static func isGranted() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState == .authorized
        }
        #endif
        return await AlarmScheduler.criticalAlertsGranted()
    }
}
