import SwiftUI

struct AlarmListView: View {
    @EnvironmentObject private var store: AlarmStore
    @Environment(\.appLanguage) private var t
    @State private var editing: Alarm?
    @State private var isCreating = false
    @State private var showingLimit = false
    @EnvironmentObject private var membership: Membership

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
                                Label(t("Delete"), systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(alarm)
                            } label: {
                                Label(t("Delete"), systemImage: "trash")
                            }
                        }
                        .listCardRow()
                }

                if store.alarms.isEmpty {
                    EmptyAlarms { newAlarm() }
                        .listCardRow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .readableWidth()
            .background(Tokens.background)
            .navigationTitle(t("Alarms"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newAlarm()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                    }
                    .accessibilityLabel(t("New alarm"))
                }
            }
            .sheet(item: $editing) { alarm in
                EditAlarmView(alarm: alarm, isNew: false)
            }
            .sheet(isPresented: $isCreating) {
                EditAlarmView(alarm: Alarm.newAlarm(from: store.settings.defaults), isNew: true)
            }
            // The free plan keeps three alarms. At the limit, + explains and offers
            // membership; the alarms already set keep ringing either way.
            .alert(t("Free plan: up to {0} alarms", Plan.freeAlarmLimit), isPresented: $showingLimit) {
                if canSubscribe {
                    Button(t("Become a member")) {
                        Task { await becomeMember() }
                    }
                    Button(t("Not now"), role: .cancel) {}
                } else {
                    Button(t("OK"), role: .cancel) {}
                }
            } message: {
                Text(canSubscribe
                     ? t("Become a member for unlimited alarms. Every alarm you have keeps ringing.")
                     : t("Membership needs OwnAlarm from the App Store. Every alarm you have keeps ringing."))
            }
        }
    }

    /// Opens a new alarm, or, on the free plan at its limit, the offer to become a member.
    private func newAlarm() {
        if membership.canAddAlarm(having: store.alarms.count) {
            isCreating = true
        } else {
            showingLimit = true
        }
    }

    private var canSubscribe: Bool {
        if case .available = membership.offer { return true }
        return false
    }

    /// Subscribes, then opens the alarm that was asked for.
    private func becomeMember() async {
        guard await membership.purchase() == .purchased else { return }
        // Let the alert finish closing before the editor slides up.
        try? await Task.sleep(nanoseconds: 400_000_000)
        isCreating = true
    }
}

// MARK: - Row

private struct AlarmRow: View {
    @EnvironmentObject private var store: AlarmStore
    @Environment(\.appLanguage) private var t
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
                                     format: store.settings.timeFormat, language: t))
                    .font(Typo.display(30, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(alarm.isEnabled ? Tokens.textPrimary : Tokens.textMuted)

                Circle()
                    .fill(Tokens.textFaint.opacity(0.5))
                    .frame(width: 3, height: 3)

                Text(alarm.repeatSummary(in: t))
                    .font(Typo.caption)
                    .foregroundStyle(Tokens.textTertiary)
            }

            Text(alarm.task.isEmpty ? t("Alarm") : alarm.task)
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
        tone.name(in: t)
    }

    private var toggle: some View {
        Toggle("", isOn: Binding(
            get: { alarm.isEnabled },
            set: { store.setEnabled($0, for: alarm) }
        ))
        .toggleStyle(.alarm)
        .labelsHidden()
        .accessibilityLabel(t("{0} alarm", alarm.task))
    }
}

// MARK: - Empty state

private struct EmptyAlarms: View {
    let create: () -> Void
    @Environment(\.appLanguage) private var t

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "alarm")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Tokens.textFaint)
            Text(t("No alarms yet"))
                .font(Typo.body(17, relativeTo: .headline, weight: .semibold))
                .foregroundStyle(Tokens.textPrimary)
            Text(t("Every alarm you add keeps its own volume, so a medication reminder can stay quiet while your wake-up alarm is loud."))
                .font(Typo.caption)
                .foregroundStyle(Tokens.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: t("Add an alarm"), systemImage: "plus", action: create)
                .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}
