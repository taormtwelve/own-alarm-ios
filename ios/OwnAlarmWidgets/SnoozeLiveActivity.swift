import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@main
struct OwnAlarmWidgets: WidgetBundle {
    var body: some Widget {
        SnoozeLiveActivity()
    }
}

/// The Lock Screen and Dynamic Island while an alarm is snoozed: the task, and a
/// live countdown to when it rings again. AlarmKit runs the countdown and starts and
/// ends this Live Activity itself — this only draws it.
struct SnoozeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<OwnAlarmMetadata>.self) { context in
            LockScreenSnooze(task: taskName(context.attributes.metadata), state: context.state)
                .padding(16)
                .activityBackgroundTint(ink)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(taskName(context.attributes.metadata), systemImage: "alarm.fill")
                        .font(.headline)
                        .foregroundStyle(amber)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(amber)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Snoozed — rings again when the timer ends")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(amber)
            } compactTrailing: {
                Countdown(state: context.state)
                    .foregroundStyle(amber)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(amber)
            }
        }
    }
}

private let amber = Color(red: 1.0, green: 0.69, blue: 0.23)
private let ink = Color(red: 0.07, green: 0.06, blue: 0.05)

/// Takes the metadata as optional so this reads the same whether AlarmKit hands it
/// over optional or not.
private func taskName(_ metadata: OwnAlarmMetadata?) -> String {
    guard let task = metadata?.task, !task.isEmpty else { return "Alarm" }
    return task
}

private struct LockScreenSnooze: View {
    let task: String
    let state: AlarmPresentationState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "alarm.fill")
                .font(.title2)
                .foregroundStyle(amber)

            VStack(alignment: .leading, spacing: 2) {
                Text(task)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Snoozed")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 8)

            Countdown(state: state)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(amber)
        }
    }
}

/// Counts down to the moment the snoozed alarm rings again.
private struct Countdown: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            // Clamped: a fire date already in the past would make an invalid range.
            Text(timerInterval: Date.now ... max(Date.now, countdown.fireDate), countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        case .paused:
            Text("Paused")
        default:
            Text("Ringing")
        }
    }
}
