import Foundation
import StoreKit

/// Whether the user is a member — subscribed through the App Store — and the way to
/// become one. Free users keep up to `Plan.freeAlarmLimit` alarms; members any number.
///
/// StoreKit 2. Buying only works in a build installed from the App Store or TestFlight:
/// a sideloaded build finds no product, so Settings shows the plan and says why it
/// cannot subscribe. UI-test launches use a stand-in (`init(stub:)`) that subscribes
/// at once.
@MainActor
final class Membership: ObservableObject {
    /// The auto-renewing monthly subscription, as set up in App Store Connect.
    static let productID = "com.ownalarm.app.member.monthly"

    /// What the App Store offers: loading, the price, or nothing (no App Store here).
    enum Offer: Equatable {
        case loading
        case available(price: String)
        case unavailable
    }

    enum Outcome: Equatable {
        case purchased, cancelled, pending, failed, unavailable
    }

    /// A line for Settings after a purchase or restore that did not simply succeed.
    enum Note: Equatable {
        case pending, failed, nothingToRestore
    }

    @Published private(set) var plan: Plan
    @Published private(set) var offer: Offer
    @Published private(set) var note: Note?
    @Published private(set) var isBusy = false

    private let usesAppStore: Bool
    private var product: Product?
    private var updates: Task<Void, Never>?

    /// The real thing: reads the App Store's entitlements now and whenever they change.
    init() {
        plan = .free
        offer = .loading
        usesAppStore = true
        // Renewals, refunds, and purchases approved later (Ask to Buy) arrive here
        // while the app runs.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task {
            await refresh()
            await loadOffer()
        }
    }

    /// A stand-in with no App Store, for UI-test launches and unit tests: it offers
    /// a price, and subscribing succeeds at once.
    init(stub plan: Plan) {
        self.plan = plan
        offer = .available(price: "$1.99")
        usesAppStore = false
    }

    /// Whether one more alarm can be created when `count` exist.
    func canAddAlarm(having count: Int) -> Bool {
        plan.canAddAlarm(having: count)
    }

    /// Member while the App Store holds a verified, unrevoked subscription.
    func refresh() async {
        guard usesAppStore else { return }
        var member = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                member = true
            }
        }
        plan = member ? .member : .free
    }

    /// Called when Settings opens: catches up on the subscription, and on the price if
    /// the App Store could not be reached before (offline at launch, say).
    func update() async {
        guard usesAppStore else { return }
        await refresh()
        if product == nil { await loadOffer() }
    }

    private func loadOffer() async {
        product = try? await Product.products(for: [Self.productID]).first
        if let product {
            offer = Offer.available(price: product.displayPrice)
        } else {
            offer = .unavailable
        }
    }

    /// Subscribes. The App Store shows its own confirmation sheet.
    @discardableResult
    func purchase() async -> Outcome {
        note = nil
        guard usesAppStore else {
            plan = .member
            return .purchased
        }
        guard let product else { return .unavailable }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refresh()
                return .purchased
            case .success(.unverified(_, _)):
                note = .failed
                return .failed
            case .userCancelled:
                return .cancelled
            case .pending:
                // Ask to Buy, or a payment that needs attention: it arrives later
                // through Transaction.updates.
                note = .pending
                return .pending
            @unknown default:
                note = .failed
                return .failed
            }
        } catch {
            note = .failed
            return .failed
        }
    }

    /// Brings back a subscription bought before — on another phone, or before a
    /// reinstall.
    func restore() async {
        note = nil
        guard usesAppStore else { return }
        isBusy = true
        defer { isBusy = false }
        try? await AppStore.sync()
        await refresh()
        if plan == .free { note = .nothingToRestore }
    }
}
