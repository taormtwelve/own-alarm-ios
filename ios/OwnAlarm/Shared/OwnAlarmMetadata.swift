#if canImport(AlarmKit)
import AlarmKit

/// Travels with every AlarmKit alarm, so the snooze Live Activity — drawn by the
/// OwnAlarmWidgets extension, a separate process — can name the task.
///
/// This file is compiled into both the app and the extension. The type has to be
/// the same in both for the system to pair an alarm with its Live Activity UI.
@available(iOS 26.0, *)
struct OwnAlarmMetadata: AlarmMetadata {
    var task: String
    var volumePercent: Int
    /// The app's language when the alarm was set, so the countdown reads in it.
    /// Optional: alarms set before there was a choice carry none, and read English.
    var language: AppLanguage?
}
#endif
