import SwiftUI

struct AlarmListView: View {
    @EnvironmentObject private var store: AlarmStore
    @State private var editing: Alarm?
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            // A List rather than a ScrollView: `.swipeActions` only exists on list
            // rows, and it brings full-swipe delete and VoiceOver actions with it.
            List {
                ForEach(store.sortedAlarms) { alarm in
                    AlarmRow(alarm: alarm)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = alarm }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.delete(alarm)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(alarm)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listCardRow()
                }

                if store.alarms.isEmpty {
                    EmptyAlarms { isCreating = true }
                        .listCardRow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .readableWidth()
            .background(Tokens.background)
            .navigationTitle("Alarms")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                    }
                    .accessibilityLabel("New alarm")
                }
            }
            .sheet(item: $editing) { alarm in
                EditAlarmView(alarm: alarm, isNew: false)
            }
            .sheet(isPresented: $isCreating) {
                EditAlarmView(alarm: Alarm.newAlarm(from: store.settings.defaults), isNew: true)
            }
        }
    }
}

// MARK: - Row

private struct AlarmRow: View {
    @EnvironmentObject private var store: AlarmStore
    let alarm: Alarm

    private var tone: AlarmTone { store.tone(for: alarm) }

    var body: some View {
        // The switch always sits on the right, at every text size; the details
        // column gives way and wraps instead.
        HStack(alignment: .center, spacing: 14) {
            details
            toggle
                .fixedSize()
        }
        .padding(16)
        .cardSurface()
        .opacity(alarm.isEnabled ? 1 : 0.55)
        // One container per row. Without it SwiftUI copies the identifier onto every
        // child — texts, meter, switch — and "alarmRow" matches seven times per alarm.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alarmRow")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(TimeText.string(hour: alarm.hour, minute: alarm.minute,
                                     format: store.settings.timeFormat))
                    .font(Typo.display(30, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(alarm.isEnabled ? Tokens.textPrimary : Tokens.textMuted)

                Circle()
                    .fill(Tokens.textFaint.opacity(0.5))
                    .frame(width: 3, height: 3)

                Text(alarm.repeatSummary)
                    .font(Typo.caption)
                    .foregroundStyle(Tokens.textTertiary)
            }

            Text(alarm.task.isEmpty ? "Alarm" : alarm.task)
                .font(Typo.body(15, relativeTo: .subheadline, weight: .semibold))
                .foregroundStyle(alarm.isEnabled ? Tokens.textPrimary : Tokens.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                VolumeMeter(volume: alarm.volume, isDimmed: !alarm.isEnabled)
                Text("\(alarm.volumePercent)%")
                    .font(Typo.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(alarm.isEnabled ? Tokens.accentText : Tokens.textMuted)
                Text(summary)
                    .font(Typo.caption)
                    .foregroundStyle(Tokens.textFaint)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: String {
        alarm.fadeInSeconds > 0
            ? "\(tone.name) · ramp \(alarm.fadeInSeconds)s"
            : "\(tone.name) · no ramp"
    }

    private var toggle: some View {
        Toggle("", isOn: Binding(
            get: { alarm.isEnabled },
            set: { store.setEnabled($0, for: alarm) }
        ))
        .toggleStyle(.alarm)
        .labelsHidden()
        .accessibilityLabel("\(alarm.task) alarm")
    }
}

// MARK: - Empty state

private struct EmptyAlarms: View {
    let create: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "alarm")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Tokens.textFaint)
            Text("No alarms yet")
                .font(Typo.body(17, relativeTo: .headline, weight: .semibold))
                .foregroundStyle(Tokens.textPrimary)
            Text("Every alarm you add keeps its own volume, so a medication reminder can stay quiet while a wake-up is loud.")
                .font(Typo.caption)
                .foregroundStyle(Tokens.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Add an alarm", systemImage: "plus", action: create)
                .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}
