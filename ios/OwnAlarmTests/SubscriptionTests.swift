import XCTest
@testable import OwnAlarm

/// Records purchase and restore calls and lets a test say what the App Store would
/// have answered, without touching StoreKit.
final class SpySubscriptionManager: SubscriptionManaging {
    var entitled = false
    var purchaseResult: Result<Bool, Error> = .success(true)
    var restoreResult: Result<Bool, Error> = .success(true)
    private(set) var purchaseCount = 0
    private(set) var restoreCount = 0
    var priceText: String? = "$2.99/mo"

    func isEntitled() async -> Bool { entitled }

    func purchase() async throws -> Bool {
        purchaseCount += 1
        let value = try purchaseResult.get()
        if value { entitled = true }
        return value
    }

    func restore() async throws -> Bool {
        restoreCount += 1
        entitled = try restoreResult.get()
        return entitled
    }
}

private struct SomeError: Error {}

@MainActor
final class SubscriptionTests: XCTestCase {

    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func makeStore(subscription: SubscriptionManaging = SpySubscriptionManager()) -> AlarmStore {
        AlarmStore(
            scheduler: SpyScheduler(),
            subscriptionManager: subscription,
            fileURL: folder.appendingPathComponent("alarms.json"),
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
    }

    private func makeAlarm(task: String = "Test") -> Alarm {
        Alarm(task: task, hour: 7, minute: 0, repeatDays: [], volume: 0.5,
              overridesSilent: true, toneID: "siren")
    }

    // MARK: The free limit

    func testFreeAccountCanAddUpToTheLimit() {
        let store = makeStore()
        XCTAssertTrue(store.canAddAlarm)

        for _ in 0..<(AppSettings.maxFreeAlarms - 1) {
            store.add(makeAlarm())
            XCTAssertTrue(store.canAddAlarm, "Still room below the limit")
        }

        store.add(makeAlarm())
        XCTAssertEqual(store.alarms.count, AppSettings.maxFreeAlarms)
        XCTAssertFalse(store.canAddAlarm, "At the limit, no more room")
    }

    func testPremiumHasNoLimit() {
        let store = makeStore()
        store.settings.subscriptionTier = .premium

        for _ in 0..<(AppSettings.maxFreeAlarms + 5) { store.add(makeAlarm()) }

        XCTAssertTrue(store.canAddAlarm, "Premium never runs out of room")
    }

    // MARK: Purchasing

    func testPurchasingPremiumUpdatesThePlan() async {
        let spy = SpySubscriptionManager()
        let store = makeStore(subscription: spy)

        await store.purchasePremium()

        XCTAssertEqual(store.settings.subscriptionTier, .premium)
        XCTAssertEqual(spy.purchaseCount, 1)
        XCTAssertNil(store.subscriptionError)
    }

    func testACancelledPurchaseLeavesThePlanAsFree() async {
        let spy = SpySubscriptionManager()
        spy.purchaseResult = .success(false)
        let store = makeStore(subscription: spy)

        await store.purchasePremium()

        XCTAssertEqual(store.settings.subscriptionTier, .free)
        XCTAssertNil(store.subscriptionError, "Cancelling is not a failure")
    }

    func testAFailedPurchaseReportsAnErrorAndLeavesThePlanAsFree() async {
        let spy = SpySubscriptionManager()
        spy.purchaseResult = .failure(SomeError())
        let store = makeStore(subscription: spy)

        await store.purchasePremium()

        XCTAssertEqual(store.settings.subscriptionTier, .free)
        XCTAssertNotNil(store.subscriptionError)
    }

    func testPurchasingPremiumSurvivesARelaunch() async throws {
        let url = folder.appendingPathComponent("alarms.json")
        let suite = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))

        let first = AlarmStore(scheduler: SpyScheduler(), subscriptionManager: SpySubscriptionManager(),
                               fileURL: url, defaults: suite)
        await first.purchasePremium()

        let second = AlarmStore(scheduler: SpyScheduler(), subscriptionManager: SpySubscriptionManager(),
                                fileURL: url, defaults: suite)
        XCTAssertEqual(second.settings.subscriptionTier, .premium)
    }

    // MARK: Restoring

    func testRestoringAnEntitledAccountUnlocksPremium() async {
        let spy = SpySubscriptionManager()
        spy.restoreResult = .success(true)
        let store = makeStore(subscription: spy)

        await store.restorePurchases()

        XCTAssertEqual(store.settings.subscriptionTier, .premium)
        XCTAssertEqual(spy.restoreCount, 1)
    }

    func testRestoringWithNothingToRestoreStaysFree() async {
        let spy = SpySubscriptionManager()
        spy.restoreResult = .success(false)
        let store = makeStore(subscription: spy)
        store.settings.subscriptionTier = .free

        await store.restorePurchases()

        XCTAssertEqual(store.settings.subscriptionTier, .free)
    }

    func testAFailedRestoreReportsAnError() async {
        let spy = SpySubscriptionManager()
        spy.restoreResult = .failure(SomeError())
        let store = makeStore(subscription: spy)

        await store.restorePurchases()

        XCTAssertNotNil(store.subscriptionError)
    }

    // MARK: Refreshing on launch

    func testRefreshingConfirmsAnActiveSubscription() async {
        let spy = SpySubscriptionManager()
        spy.entitled = true
        let store = makeStore(subscription: spy)
        store.settings.subscriptionTier = .free   // stale: bought on another device

        await store.refreshSubscriptionStatus()

        XCTAssertEqual(store.settings.subscriptionTier, .premium)
    }

    func testRefreshingDropsALapsedSubscription() async {
        let spy = SpySubscriptionManager()
        spy.entitled = false
        let store = makeStore(subscription: spy)
        store.settings.subscriptionTier = .premium   // stale: cancelled since

        await store.refreshSubscriptionStatus()

        XCTAssertEqual(store.settings.subscriptionTier, .free)
    }
}
