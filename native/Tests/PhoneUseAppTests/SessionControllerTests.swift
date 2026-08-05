import CoreGraphics
import XCTest

@testable import PhoneUseApp

final class SessionControllerTests: XCTestCase {
    func testSelectsTheAccessibilityWindowMatchingTheCapturedTarget() {
        let welcome = CGRect(x: 960, y: 359, width: 640, height: 662)
        let phone = CGRect(x: 2_061, y: 146, width: 354, height: 781)

        XCTAssertEqual(
            AccessibilityWindowSelector.matchingIndex(
                targetBounds: phone,
                candidateBounds: [welcome, phone]
            ),
            1
        )
    }

    func testRejectsUnrelatedAccessibilityWindows() {
        let phone = CGRect(x: 2_061, y: 146, width: 354, height: 781)
        let welcome = CGRect(x: 960, y: 359, width: 640, height: 662)

        XCTAssertNil(
            AccessibilityWindowSelector.matchingIndex(
                targetBounds: phone,
                candidateBounds: [welcome, nil]
            )
        )
    }

    func testReplacementProcessDoesNotCountAsClosed() {
        XCTAssertFalse(SessionTerminationPolicy.isComplete(runningProcessIDs: [200]))
        XCTAssertFalse(SessionTerminationPolicy.isComplete(runningProcessIDs: [201]))
        XCTAssertTrue(SessionTerminationPolicy.isComplete(runningProcessIDs: []))
    }
}
