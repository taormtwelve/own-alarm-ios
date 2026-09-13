import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: AlarmStore
    @State private var criticalAlertsGranted: Bool?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Clock") {
                        CardGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Time format")
                                    .font(Typo.rowLabel)
                                    .foregroundStyle(Tokens.textSecondary)
                                SegmentedChoice(
                                    options: TimeFormat.allCases,
                                    label: \.label,
                                    selection: $store.settings.timeFormat
                                )
                            }
                            .padding(16)
                        }
                    }

                    section("When an alarm rings") {
                        CardGroup {
                            SettingsRow(
                                title: "Show on Lock Screen",
                                subtitle: "Off, the alarm only takes over inside the app"
                            ) {
                                Toggle("Show on Lock Screen", isOn: $store.settings.showOnLockScreen)
                                    .toggleStyle(.alarm)
                                    .labelsHidden()
                            }

                            // Hidden on iOS 26+, where every alarm rings through Silent.
                            if !RingPermission.alwaysRingsThroughSilent {
                                SettingsRow(
                                    title: "Override Silent & Focus",
                                    subtitle: "Applied to new alarms"
                                ) {
                                    Toggle("Override Silent & Focus", isOn: $store.settings.defaults.overridesSilent)
                                        .toggleStyle(.alarm)
                                        .labelsHidden()
                                }
                            }

                            SettingsRow(
                                title: "Louder after each snooze",
                                subtitle: "Adds 10% every time"
                            ) {
                                Toggle("Louder after each snooze", isOn: $store.settings.defaults.louderAfterSnooze)
                                    .toggleStyle(.alarm)
                                    .labelsHidden()
                            }

                            Button {
                                openSettings()
                            } label: {
                                SettingsRow(
                                    title: RingPermission.name,
                                    subtitle: permissionExplanation,
                                    showsDivider: false
                                ) {
                                    RowValue(value: permissionLabel)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    section("Appearance") {
                        CardGroup {
                            SegmentedChoice(
                                options: ThemePreference.allCases,
                                label: \.label,
                                selection: $store.settings.theme
                            )
                            .padding(8)
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
                .readableWidth()
            }
            .background(Tokens.background)
            .navigationTitle("Settings")
            .task {
                criticalAlertsGranted = await RingPermission.isGranted()
            }
            .onChange(of: store.settings.showOnLockScreen) { _ in
                store.rescheduleAll()
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)
            content()
        }
    }

    private var permissionLabel: String {
        switch criticalAlertsGranted {
        case .some(true): return "Allowed"
        case .some(false): return "Not allowed"
        case nil: return "Checking…"
        }
    }

    private var permissionExplanation: String {
        criticalAlertsGranted == true
            ? "What lets an alarm ring at its own volume through Silent"
            : "Without it, alarms follow the ringer and the mute switch"
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
