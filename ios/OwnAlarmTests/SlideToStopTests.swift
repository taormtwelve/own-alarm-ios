import XCTest
@testable import OwnAlarm

/// Where a slide becomes a deliberate stop.
final class SlideToStopTests: XCTestCase {

    func testASlideMostOfTheWayAcrossStops() {
        XCTAssertTrue(SlideToStop.completes(offset: 85, travel: 100))
        XCTAssertTrue(SlideToStop.completes(offset: 100, travel: 100))
    }

    func testAShortSlideSpringsBack() {
        XCTAssertFalse(SlideToStop.completes(offset: 84, travel: 100))
        XCTAssertFalse(SlideToStop.completes(offset: 40, travel: 100))
        XCTAssertFalse(SlideToStop.completes(offset: 0, travel: 100))
    }

    func testATrackWithNoRoomNeverStops() {
        XCTAssertFalse(SlideToStop.completes(offset: 0, travel: 0),
                       "Before layout there is no track to slide along")
    }
}
