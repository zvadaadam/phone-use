import CoreGraphics
import XCTest

@testable import PhoneUseCore

final class WindowBoundsStabilityTests: XCTestCase {
    func testRequiresConsecutiveEqualBounds() {
        var stability = WindowBoundsStability(requiredConsecutiveSamples: 3)
        let bounds = CGRect(x: 100, y: 100, width: 354, height: 781)

        XCTAssertFalse(stability.observe(bounds))
        XCTAssertFalse(stability.observe(bounds))
        XCTAssertTrue(stability.observe(bounds))
    }

    func testMovingBoundsResetTheStableSampleCount() {
        var stability = WindowBoundsStability(requiredConsecutiveSamples: 3)
        let first = CGRect(x: 100, y: 100, width: 354, height: 781)
        let second = CGRect(x: 101, y: 100, width: 354, height: 781)

        XCTAssertFalse(stability.observe(first))
        XCTAssertFalse(stability.observe(first))
        XCTAssertFalse(stability.observe(second))
        XCTAssertFalse(stability.observe(second))
        XCTAssertTrue(stability.observe(second))
    }
}
