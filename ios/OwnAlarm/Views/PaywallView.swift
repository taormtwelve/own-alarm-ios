import SwiftUI

/// Shown instead of the editor once a Free account is already at its alarm limit.
/// Explains why, and offers to upgrade or restore a purchase made elsewhere. Closes
/// itself the moment the plan actually becomes Premium.
struct PaywallView: View {
    @EnvironmentObject private var store: AlarmStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var t

    @State private var isWorking = false
    @State private var price: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 8)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Tokens.accentFill)
                    .frame(width: 72, height: 72)
                    .background(Tokens.accentSurface)
                    .clipShape(Circle())

                VStack(spacing: 8) {
                    Text(t("You've reached the free limit"))
                        .font(Typo.body(20, relativeTo: .title2, weight: .bold))
                        .foregroundStyle(Tokens.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(t("Free accounts can keep up to {0} alarms. Upgrade to Premium for unlimited alarms.",
                          AppSettings.maxFreeAlarms))
                        .font(Typo.body(15, relativeTo: .subheadline))
                        .foregroundStyle(Tokens.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                PrimaryButton(title: upgradeTitle, systemImage: "bolt.fill") { purchase() }
                    .opacity(isWorking ? 0.6 : 1)
                    .disabled(isWorking)

                Button(t("Restore purchases")) { restore() }
                    .font(Typo.caption)
                    .foregroundStyle(Tokens.textMuted)
                    .disabled(isWorking)
            }
            .padding(28)
            .padding(.horizontal, Metrics.gutter)
            .readableWidth()
            .background(Tokens.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Maybe later")) { dismiss() }
                }
            }
            .task { price = await store.premiumPriceText }
            .onChange(of: store.settings.subscriptionTier) { tier in
                if tier == .premium { dismiss() }
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

    private var upgradeTitle: String {
        price.map { t("Upgrade · {0}", $0) } ?? t("Upgrade to Premium")
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
}
