import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: AlarmStore
    @Environment(\.appLanguage) private var t
    @State private var criticalAlertsGranted: Bool?
    @State private var isWorking = false
    @State private var premiumPrice: String?
    @State private var errorMessage: String?

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

                    section(t("Subscription")) {
                        CardGroup {
                            SettingsRow(
                                title: t("Plan"),
                                subtitle: planSubtitle,
                                showsDivider: store.settings.subscriptionTier == .free
                            ) {
                                RowValue(value: t(store.settings.subscriptionTier.label), showsChevron: false)
                            }

                            if store.settings.subscriptionTier == .free {
                                Button {
                                    purchase()
                                } label: {
                                    SettingsRow(title: upgradeTitle, subtitle: t("Unlimited alarms")) {
                                        trailingIndicator
                                    }
                                }
                                .buttonStyle(.plain)
                                .opacity(isWorking ? 0.6 : 1)
                                .disabled(isWorking)
                            }

                            Button {
                                restore()
                            } label: {
                                SettingsRow(title: t("Restore purchases"), showsDivider: false) {
                                    trailingIndicator
                                }
                            }
                            .buttonStyle(.plain)
                            .opacity(isWorking ? 0.6 : 1)
                            .disabled(isWorking)
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
            .task {
                premiumPrice = await store.premiumPriceText
            }
            .onChange(of: store.settings.showOnLockScreen) { _ in
                store.rescheduleAll()
            }
            // Lock Screen alerts and notifications are written when an alarm is
            // armed, so re-arming puts them in the new language.
            .onChange(of: store.settings.language) { _ in
                store.rescheduleAll()
            }
            .alert(
                t("Couldn't complete the purchase"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button(t("OK")) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Subscription

    private var planSubtitle: String {
        store.settings.subscriptionTier == .premium
            ? t("Unlimited alarms")
            : t("Up to {0} alarms", AppSettings.maxFreeAlarms)
    }

    private var upgradeTitle: String {
        premiumPrice.map { t("Upgrade · {0}", $0) } ?? t("Upgrade to Premium")
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        if isWorking {
            ProgressView()
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.textFaint)
        }
    }

    private func purchase() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            await store.purchasePremium()
            isWorking = false
            reportErrorIfAny()
        }
    }

    private func restore() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            await store.restorePurchases()
            isWorking = false
            reportErrorIfAny()
        }
    }

    private func reportErrorIfAny() {
        guard let message = store.subscriptionError else { return }
        errorMessage = message
        store.subscriptionError = nil
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
