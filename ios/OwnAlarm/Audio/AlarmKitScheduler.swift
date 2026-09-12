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
/// Note: our model type `Alarm` shadows AlarmKit's, so AlarmKit's is always written
/// `AlarmKit.Alarm` here.
@available(iOS 26.0, *)
final class AlarmKitScheduler: AlarmScheduling {
    struct Metadata: AlarmMetadata {}

    private let manager = AlarmManager.shared
    private let fallback: AlarmScheduling

    init(fallback: AlarmScheduling) {
        self.fallback = fallback
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

        let configuration = makeConfiguration(for: alarm, tone: tone)
        Task { [manager, fallback] in
            do {
                _ = try await manager.schedule(id: alarm.id, configuration: configuration)
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
        try? manager.cancel(id: alarm.id)
        fallback.cancel(alarm)
    }

    func cancelSnooze(_ alarm: Alarm) {
        fallback.cancelSnooze(alarm)
    }

    func cancelAll() {
        for scheduled in (try? manager.alarms) ?? [] {
            try? manager.cancel(id: scheduled.id)
        }
        fallback.cancelAll()
    }

    // MARK: Configuration

    private func makeConfiguration(for alarm: Alarm, tone: AlarmTone)
        -> AlarmManager.AlarmConfiguration<Metadata> {
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

        let attributes = AlarmAttributes<Metadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: Metadata(),
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
