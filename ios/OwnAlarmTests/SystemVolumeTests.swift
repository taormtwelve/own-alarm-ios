import XCTest
@testable import OwnAlarm

/// A pretend phone volume, so the bookkeeping can be tested without a device.
final class FakeVolume {
    var level: Float
    init(_ level: Float) { self.level = level }
}

@MainActor
extension SystemVolume {
    static func fake(_ volume: FakeVolume, defaults: UserDefaults) -> SystemVolume {
        SystemVolume(defaults: defaults, read: { volume.level }, write: { volume.level = $0 })
    }
}

/// The promise: whatever the app does to the phone's volume, the user's own level
/// comes back.
@MainActor
final class SystemVolumeTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    func testTakingOverSetsTheLevelAndRestoringPutsTheUsersBack() {
        let phone = FakeVolume(0.3)
        let volume = SystemVolume.fake(phone, defaults: freshDefaults())

        volume.takeOver(at: 0.9)
        XCTAssertEqual(phone.level, 0.9, accuracy: 0.001)

        volume.restore()
        XCTAssertEqual(phone.level, 0.3, accuracy: 0.001)
    }

    func testMovingTheSliderKeepsTheFirstOriginal() {
        let phone = FakeVolume(0.3)
        let volume = SystemVolume.fake(phone, defaults: freshDefaults())

        volume.takeOver(at: 0.9)
        volume.set(0.5)
        volume.takeOver(at: 0.7)   // e.g. a second drag before the first ended
        volume.restore()

        XCTAssertEqual(phone.level, 0.3, accuracy: 0.001,
                       "The user's level, not one the app set along the way")
    }

    func testRestoringWhenNotInChargeLeavesTheVolumeAlone() {
        let phone = FakeVolume(0.4)
        let volume = SystemVolume.fake(phone, defaults: freshDefaults())

        volume.restore()

        XCTAssertEqual(phone.level, 0.4, accuracy: 0.001)
    }

    func testTheNextLaunchPutsTheVolumeBackIfTheAppClosedMidWay() {
        let phone = FakeVolume(0.25)
        let defaults = freshDefaults()

        SystemVolume.fake(phone, defaults: defaults).takeOver(at: 1.0)
        XCTAssertEqual(phone.level, 1.0, accuracy: 0.001)

        // The app is killed without restoring; a new launch starts a new instance.
        SystemVolume.fake(phone, defaults: defaults).recoverIfNeeded()

        XCTAssertEqual(phone.level, 0.25, accuracy: 0.001)
    }

    func testLevelsAreClampedToTheDevicesRange() {
        let phone = FakeVolume(0.5)
        let volume = SystemVolume.fake(phone, defaults: freshDefaults())

        volume.set(1.4)
        XCTAssertEqual(phone.level, 1.0, accuracy: 0.001)
        volume.set(-0.2)
        XCTAssertEqual(phone.level, 0.0, accuracy: 0.001)
    }
}
