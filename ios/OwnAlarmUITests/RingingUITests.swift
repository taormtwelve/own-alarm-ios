import XCTest

/// The in-app ringing screen: a small Snooze, and Stop as a slide so a stray tap
/// cannot silence an alarm. Launched with `-ringFirstAlarm`, which opens the ringing
/// screen for the first sample alarm — the repeating 06:45 Morning run.
final class RingingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-ringFirstAlarm"]
        app.launch()
    }

    private var slide: XCUIElement {
        app.descendants(matching: .any)["slideToStop"]
    }

    private var snooze: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Snooze'")).firstMatch
    }

    func testTheRingingScreenOffersSlideToStopAndASmallerSnooze() {
        XCTAssertTrue(slide.waitForExistence(timeout: 10), "The ringing screen should open")
        XCTAssertTrue(snooze.exists, "The sample alarm snoozes")

        XCTAssertLessThan(snooze.frame.width, slide.frame.width * 0.75,
                          "Snooze should be the smaller control")
        XCTAssertLessThan(snooze.frame.height, slide.frame.height)
    }

    func testAShortSlideDoesNotStopTheAlarm() {
        XCTAssertTrue(slide.waitForExistence(timeout: 10))

        drag(to: 0.4)

        XCTAssertTrue(slide.exists, "A half-hearted slide must not stop the alarm")
    }

    func testSlidingAllTheWayStopsTheAlarm() {
        XCTAssertTrue(slide.waitForExistence(timeout: 10))

        drag(to: 0.98)

        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: slide)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["Morning run"].waitForExistence(timeout: 5),
                      "Stopping returns to the list")
    }

    func testSnoozeClosesTheRingingScreen() {
        XCTAssertTrue(slide.waitForExistence(timeout: 10))

        snooze.tap()

        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: slide)
        waitForExpectations(timeout: 5)
    }

    /// Press on the knob at the left end of the track and drag to `fraction` of the
    /// track's width.
    private func drag(to fraction: CGFloat) {
        let start = slide.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
        let end = slide.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
    }
}
