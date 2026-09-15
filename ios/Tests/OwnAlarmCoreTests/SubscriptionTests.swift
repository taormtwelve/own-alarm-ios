import XCTest
@testable import OwnAlarmCore

/// Tests for the subscription model: what each tier allows, and that it survives
/// saving — including a save from before subscriptions existed.
final class SubscriptionTests: XCTestCase {

    // MARK: Tiers

    func testFreeIsCappedAtTheSharedLimit() {
        XCTAssertEqual(SubscriptionTier.free.alarmLimit, AppSettings.maxFreeAlarms)
    }

    func testPremiumHasNoLimit() {
        XCTAssertNil(SubscriptionTier.premium.alarmLimit)
    }

    func testTheFreeLimitIsThree() {
        XCTAssertEqual(AppSettings.maxFreeAlarms, 3)
    }

    func testEveryTierHasALabelAndReadsInThai() {
        XCTAssertEqual(SubscriptionTier.allCases.map(\.label), ["Free", "Premium"])
        let thai = AppLanguage.thai
        for tier in SubscriptionTier.allCases {
            XCTAssertNotEqual(thai(tier.label), tier.label, "Untranslated: \(tier.label)")
        }
    }

    // MARK: Settings

    func testANewInstallStartsFree() {
        XCTAssertEqual(AppSettings().subscriptionTier, .free)
    }

    func testSettingsSurviveAJSONRoundTripWithTheTier() throws {
        var settings = AppSettings()
        settings.subscriptionTier = .premium

        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }

    /// Exactly what a build saved before subscriptions existed wrote to disk. Without
    /// this, an update would either fail to load every other setting or — far
    /// worse — read the missing field as Premium for everyone.
    func testASaveFromBeforeSubscriptionsExistedStaysFree() throws {
        let json = """
        {"timeFormat":"twelveHour","theme":"dark","showOnLockScreen":false,\
        "defaults":{"volume":0.4,"overridesSilent":true,"toneID":"whisper","snoozeMinutes":5,"vibrates":true},\
        "language":"en"}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.subscriptionTier, .free)
        XCTAssertEqual(settings.timeFormat, .twelveHour, "The rest of the settings still load")
    }

    func testATierThisVersionDoesNotKnowFallsBackToFreeAndCostsNothingElse() throws {
        let json = """
        {"timeFormat":"twelveHour","theme":"dark","showOnLockScreen":false,"subscriptionTier":"lifetime",\
        "defaults":{"volume":0.4,"overridesSilent":true,"toneID":"whisper","snoozeMinutes":5,"vibrates":true},\
        "language":"en"}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.subscriptionTier, .free, "Never grant a tier for free just because it decoded")
        XCTAssertEqual(settings.timeFormat, .twelveHour)
    }
}
