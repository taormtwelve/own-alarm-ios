import XCTest
@testable import OwnAlarm

/// The plans as the app sees them, through the stand-in membership UI tests use —
/// the App Store itself cannot be reached from a test.
@MainActor
final class MembershipTests: XCTestCase {

    func testAFreeUserCanHoldThreeAlarms() {
        let membership = Membership(stub: .free)

        XCTAssertTrue(membership.canAddAlarm(having: 0))
        XCTAssertTrue(membership.canAddAlarm(having: 2))
        XCTAssertFalse(membership.canAddAlarm(having: 3), "A fourth alarm needs membership")
    }

    func testSubscribingMakesAMemberWithNoLimit() async {
        let membership = Membership(stub: .free)

        let outcome = await membership.purchase()

        XCTAssertEqual(outcome, .purchased)
        XCTAssertEqual(membership.plan, .member)
        XCTAssertTrue(membership.canAddAlarm(having: 50))
        XCTAssertNil(membership.note, "Nothing to explain after a clean purchase")
    }

    func testAMemberHasNoLimit() {
        XCTAssertTrue(Membership(stub: .member).canAddAlarm(having: 100))
    }

    func testTheStandInOffersAPriceSoTheButtonCanBeTried() {
        XCTAssertEqual(Membership(stub: .free).offer, .available(price: "$6.00"))
    }

    func testTheSubscriptionIsTheYearlyMemberProduct() {
        XCTAssertEqual(Membership.productID, "com.ownalarm.app.member.yearly",
                       "Must match the product set up in App Store Connect")
    }
}
