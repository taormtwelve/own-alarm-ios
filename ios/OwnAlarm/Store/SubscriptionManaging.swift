import Foundation
import StoreKit

/// Buys and checks the Premium subscription that lifts the free alarm limit.
/// Abstracted like `AlarmScheduling`, so `AlarmStore` can be tested against a spy
/// instead of talking to StoreKit.
protocol SubscriptionManaging: AnyObject {
    /// True when the App Store currently has this device entitled to Premium — a
    /// purchase made this launch, a restore, a renewal, or a purchase made on
    /// another device signed into the same account.
    func isEntitled() async -> Bool

    /// Buys the Premium subscription. Returns whether it is entitled afterwards —
    /// false rather than throwing when the user simply cancelled the sheet.
    @discardableResult
    func purchase() async throws -> Bool

    /// Asks the App Store to restore a purchase made elsewhere. Returns whether the
    /// account is entitled afterwards.
    @discardableResult
    func restore() async throws -> Bool

    /// The subscription's localized price, once its product has loaded from the
    /// App Store. Nil until then, or if the product could not be fetched.
    var priceText: String? { get async }
}

/// The real subscription, bought through the App Store.
///
/// `productID` must exist as an auto-renewable subscription in App Store Connect
/// before a real purchase can succeed; until then `purchase()` throws
/// `productNotFound`. For local testing without App Store Connect, add a StoreKit
/// Configuration file with the same product id and select it under the app's scheme
/// (Edit Scheme › Run › Options › StoreKit Configuration) — Xcode then serves it from
/// there instead of the network.
final class StoreKitSubscriptionManager: SubscriptionManaging {
    static let productID = "com.ownalarm.app.premium.monthly"

    private var product: Product?

    func isEntitled() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID else { continue }
            return transaction.revocationDate == nil
        }
        return false
    }

    @discardableResult
    func purchase() async throws -> Bool {
        let product = try await loadProduct()
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw SubscriptionError.unverified
            }
            await transaction.finish()
            return transaction.revocationDate == nil
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    @discardableResult
    func restore() async throws -> Bool {
        try await AppStore.sync()
        return await isEntitled()
    }

    var priceText: String? {
        get async { (try? await loadProduct())?.displayPrice }
    }

    private func loadProduct() async throws -> Product {
        if let product { return product }
        guard let fetched = try await Product.products(for: [Self.productID]).first else {
            throw SubscriptionError.productNotFound
        }
        product = fetched
        return fetched
    }
}

/// What `purchase()` throws when the App Store itself did not report a reason.
/// `AlarmStore` shows the same translated line for any failure — an app cannot
/// enumerate every possible StoreKit or network error in two languages — so this
/// exists for logging, not for display.
enum SubscriptionError: Error {
    case productNotFound
    case unverified
}
