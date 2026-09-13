import SwiftUI

struct EditAlarmView: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var player: AlarmPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var alarm: Alarm
    @State private var time: Date
    @State private var showingSoundPicker = false
    private let isNew: Bool

    init(alarm: Alarm, isNew: Bool) {
        _alarm = State(initialValue: alarm)
        _time = State(initialValue: Self.date(hour: alarm.hour, minute: alarm.minute))
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    timePicker
                    detailsCard
                    volumeCard
                    snoozeCard
                    if !isNew { deleteButton }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
                .readableWidth()
            }
            .background(Tokens.background)
            .scrollDismissesKeyboard(.interactively)
            // Touching any other control ends a slider preview at once — including
            // after iOS cancelled the drag without the slider reporting it.
            .onChange(of: alarm.fadeInSeconds) { _ in player.stopPreviews() }
            .onChange(of: alarm.overridesSilent) { _ in player.stopPreviews() }
            .onChange(of: alarm.snoozeMinutes) { _ in player.stopPreviews() }
            .onChange(of: alarm.louderAfterSnooze) { _ in player.stopPreviews() }
            .onChange(of: alarm.repeatDays) { _ in player.stopPreviews() }
            .onChange(of: time) { _ in player.stopPreviews() }
            .navigationTitle(isNew ? "New alarm" : alarm.task.isEmpty ? "Alarm" : alarm.task)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                }
            }
            .sheet(isPresented: $showingSoundPicker) {
                SoundPickerView(alarm: $alarm)
            }
        }
    }

    // MARK: Time

    private var timePicker: some View {
        DatePicker("Alarm time", selection: $time, displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel)
            .labelsHidden()
            // `DatePicker` takes its 12/24-hour cycle from the locale, not from us,
            // so the app's Clock setting is applied by handing it a locale with the
            // matching hour cycle.
            .environment(\.locale, pickerLocale)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private var pickerLocale: Locale {
        switch store.settings.timeFormat {
        case .twentyFourHour: return Locale(identifier: "en_GB")
        case .twelveHour: return Locale(identifier: "en_US")
        case .automatic: return .current
        }
    }

    // MARK: Details

    private var detailsCard: some View {
        CardGroup {
            SettingsRow(title: "Task") {
                TextField("What is this alarm for?", text: $alarm.task)
                    .font(Typo.rowValue)
                    .foregroundStyle(Tokens.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Repeat")
                    .font(Typo.rowLabel)
                    .foregroundStyle(Tokens.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Adaptive columns let the day pills reflow instead of overflowing
                // on a narrow phone or at large text sizes.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Metrics.minTapTarget), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(Weekday.localeOrdered) { day in
                        DayPill(day: day, isOn: alarm.repeatDays.contains(day)) {
                            if alarm.repeatDays.contains(day) {
                                alarm.repeatDays.remove(day)
                            } else {
                                alarm.repeatDays.insert(day)
                            }
                        }
                    }
                }

                Text(alarm.repeatSummary)
                    .font(Typo.caption)
                    .foregroundStyle(Tokens.textMuted)
            }
            .padding(16)

            Rectangle().fill(Tokens.divider).frame(height: 1).padding(.leading, 16)

            Button {
                showingSoundPicker = true
            } label: {
                SettingsRow(title: "Sound", showsDivider: false) {
                    RowValue(value: store.tone(for: alarm).name)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("soundRow")
        }
    }

    // MARK: Volume — the centre of the screen

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Volume for this task")
                        .font(Typo.sectionLabel)
                        .tracking(1.1)
                        .foregroundStyle(Tokens.accentLabel)
                    Text("100% is your iPhone's maximum — your volume comes back after")
                        .font(Typo.caption)
                        .foregroundStyle(Tokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("\(alarm.volumePercent)%")
                    .font(Typo.display(38, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.accentText)
                    .accessibilityIdentifier("volumeReadout")
            }

            // Plays the tone while dragging, so the level is set by ear.
            VolumeSlider(volume: $alarm.volume) { editing in
                if editing {
                    player.beginScrub(store.tone(for: alarm), at: alarm.volume)
                } else {
                    player.endScrub()
                }
            }
            .onChange(of: alarm.volume) { player.scrub(to: $0) }
            .onDisappear { player.stop() }

            HStack {
                Text("Whisper").font(Typo.caption).foregroundStyle(Tokens.textFaint)
                Spacer()
                Text("Room").font(Typo.caption).foregroundStyle(Tokens.textFaint)
                Spacer()
                Text("Wake the dead").font(Typo.caption).foregroundStyle(Tokens.textFaint)
            }

            Divider().background(Tokens.border)

            Toggle(isOn: Binding(
                get: { alarm.fadeInSeconds > 0 },
                set: { alarm.fadeInSeconds = $0 ? store.settings.defaults.fadeInWhenSwitchedOn : 0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fade in")
                        .font(Typo.body(14, relativeTo: .subheadline, weight: .semibold))
                        .foregroundStyle(Tokens.textPrimary)
                    Text(fadeDescription)
                        .font(Typo.caption)
                        .foregroundStyle(Tokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.alarm)

            if alarm.fadeInSeconds > 0 {
                Stepper(
                    "Fade over \(alarm.fadeInSeconds) seconds",
                    value: $alarm.fadeInSeconds,
                    in: 5...120,
                    step: 5
                )
                .font(Typo.caption)
                .foregroundStyle(Tokens.textSecondary)
            }

            // On iOS 26+ every alarm rings through Silent, so there is nothing to choose.
            if !RingPermission.alwaysRingsThroughSilent {
                Toggle(isOn: $alarm.overridesSilent) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Override Silent & Focus")
                            .font(Typo.body(14, relativeTo: .subheadline, weight: .semibold))
                            .foregroundStyle(Tokens.textPrimary)
                        Text("Rings even when the phone is muted")
                            .font(Typo.caption)
                            .foregroundStyle(Tokens.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.alarm)
            }
        }
        .padding(18)
        .cardSurface(radius: 22)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Tokens.accentBorder, lineWidth: 1)
        )
    }

    private var fadeDescription: String {
        guard alarm.fadeInSeconds > 0 else { return "Starts at full volume" }
        let start = Int((alarm.startingVolume * 100).rounded())
        return "Starts at \(start)%, reaches \(alarm.volumePercent)% over \(alarm.fadeInSeconds)s"
    }

    // MARK: Snooze

    private var snoozeCard: some View {
        CardGroup {
            SettingsRow(title: "Snooze", showsDivider: alarm.snoozeMinutes > 0) {
                Toggle("", isOn: Binding(
                    get: { alarm.snoozeMinutes > 0 },
                    set: { alarm.snoozeMinutes = $0 ? store.settings.defaults.snoozeWhenSwitchedOn : 0 }
                ))
                .toggleStyle(.alarm)
                .labelsHidden()
                .accessibilityLabel("Snooze")
            }
            if alarm.snoozeMinutes > 0 {
                SettingsRow(title: "Snooze length") {
                    Stepper("\(alarm.snoozeMinutes) min", value: $alarm.snoozeMinutes, in: 1...30)
                        .font(Typo.rowValue)
                        .fixedSize()
                }
                SettingsRow(
                    title: "Louder after each snooze",
                    subtitle: "Adds 10% every time you put it off",
                    showsDivider: false
                ) {
                    Toggle("Louder after each snooze", isOn: $alarm.louderAfterSnooze)
                        .toggleStyle(.alarm)
                        .labelsHidden()
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            store.delete(alarm)
            dismiss()
        } label: {
            Text("Delete alarm")
                .font(Typo.body(16, relativeTo: .headline, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .cardSurface()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
    }

    // MARK: Actions

    private func save() {
        // Saving an alarm means you want it: an edited alarm comes back switched on.
        alarm.isEnabled = true
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        alarm.hour = parts.hour ?? alarm.hour
        alarm.minute = parts.minute ?? alarm.minute
        if alarm.task.trimmingCharacters(in: .whitespaces).isEmpty {
            alarm.task = "Alarm"
        }
        store.save(alarm, isNew: isNew)
        dismiss()
    }

    private static func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - Day pill

private struct DayPill: View {
    let day: Weekday
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Text(day.narrowSymbol)
                .font(Typo.body(14, relativeTo: .subheadline, weight: .semibold))
                .foregroundStyle(isOn ? Tokens.inkOnAccent : Tokens.textSecondary)
                .frame(minWidth: Metrics.minTapTarget, minHeight: Metrics.minTapTarget)
                .background(isOn ? Tokens.accentFill : Tokens.track)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.shortSymbol)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}
