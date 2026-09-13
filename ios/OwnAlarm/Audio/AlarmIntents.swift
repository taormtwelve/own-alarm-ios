#if canImport(AlarmKit)
import AlarmKit
import AppIntents

/// Runs in the app when Snooze is tapped on a Lock Screen alarm.
///
/// Without an intent behind it, tapping Snooze dismissed the alarm and nothing
/// followed. This starts AlarmKit's snooze countdown (which the widget extension
/// draws on the Lock Screen and in the Dynamic Island) and posts a plain notification
/// saying when the alarm returns — so the snooze shows even if the countdown does not.
@available(iOS 26.0, *)
struct SnoozeAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze alarm"
    static let isDiscoverable = false

    @Parameter(title: "Alarm") var alarmID: String
    @Parameter(title: "Task") var task: String
    @Parameter(title: "Minutes") var minutes: Int

    init() {}

    init(alarmID: UUID, task: String, minutes: Int) {
        self.alarmID = alarmID.uuidString
        self.task = task
        self.minutes = minutes
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        // If AlarmKit already started the countdown this throws; that is fine.
        try? AlarmManager.shared.countdown(id: id)
        SnoozeNotice.post(alarmID: id, task: task, minutes: minutes)
        return .result()
    }
}

/// Runs in the app when Stop is tapped on a Lock Screen alarm: stops it and clears
/// any "snoozed" notice left from earlier.
@available(iOS 26.0, *)
struct StopAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop alarm"
    static let isDiscoverable = false

    @Parameter(title: "Alarm") var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        // If AlarmKit already stopped it this throws; that is fine.
        try? AlarmManager.shared.stop(id: id)
        SnoozeNotice.clear(alarmID: id)
        return .result()
    }
}
#endif
