import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: AlarmStore
    @Environment(\.appLanguage) private var t
    @State private var criticalAlertsGranted: Bool?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(t("Clock")) {
                        CardGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(t("Time format"))
                                    .font(Typo.rowLabel)
                                    .foregroundStyle(Tokens.textSecondary)
                                SegmentedChoice(
                                    options: TimeFormat.allCases,
                                    label: { t($0.label) },
                                    selection: $store.settings.timeFormat
                                )
                            }
                            .padding(16)
                        }
                    }

                    section(t("When an alarm rings")) {
                        CardGroup {
                            SettingsRow(
                                title: t("Show on Lock Screen"),
                                subtitle: t("When off, alarms only show inside the app")
                            ) {
                                Toggle(t("Show on Lock Screen"), isOn: $store.settings.showOnLockScreen)
                                    .toggleStyle(.alarm)
                                    .labelsHidden()
                            }

                            // Hidden where AlarmKit rings every alarm through Silent.
                            if !RingPermission.alwaysRingsThroughSilent {
                                SettingsRow(
                                    title: t("Override Silent & Focus"),
                                    subtitle: t("Applied to new alarms")
                                ) {
                                    Toggle(t("Override Silent & Focus"), isOn: $store.settings.defaults.overridesSilent)
                                        .toggleStyle(.alarm)
                                        .labelsHidden()
                                }
                            }

                            Button {
                                openSettings()
                            } label: {
                                SettingsRow(
                                    title: t(RingPermission.name),
                                    subtitle: permissionExplanation,
                                    showsDivider: false
                                ) {
                                    RowValue(value: permissionLabel)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    section(t("Appearance")) {
                        CardGroup {
                            SegmentedChoice(
                                options: ThemePreference.allCases,
                                label: { t($0.label) },
                                selection: $store.settings.theme
                            )
                            .padding(8)
                        }
                    }

                    // Only on a phone that lists Thai among its languages; anywhere else
                    // the app speaks English and there is nothing to choose. Each
                    // language is named in itself, so someone who reads only that one
                    // can find it.
                    if store.languages.count > 1 {
                        section(t("Language")) {
                            CardGroup {
                                SegmentedChoice(
                                    options: store.languages,
                                    label: \.label,
                                    selection: $store.settings.language
                                )
                                .padding(8)
                            }
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
                .readableWidth()
            }
            .background(Tokens.background)
            .navigationTitle(t("Settings"))
            .task {
                criticalAlertsGranted = await RingPermission.isGranted()
            }
            .onChange(of: store.settings.showOnLockScreen) { _ in
                store.rescheduleAll()
            }
            // Lock Screen alerts and notifications are written when an alarm is
            // armed, so re-arming puts them in the new language.
            .onChange(of: store.settings.language) { _ in
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
        case .some(true): return t("Allowed")
        case .some(false): return t("Not allowed")
        case nil: return t("Checking…")
        }
    }

    private var permissionExplanation: String {
        criticalAlertsGranted == true
            ? t("Lets alarms ring at their own volume, even in Silent mode")
            : t("Without it, alarms follow your ringer volume and Silent mode")
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
