import XCTest

@testable import MirrorCore

final class ControlCommandTests: XCTestCase {
    func testAcceptsNormalizedTap() throws {
        let command = ControlCommand(type: "tap", x: 0.25, y: 0.75)
        XCTAssertNoThrow(try command.validated())
    }

    func testRejectsOutOfBoundsCoordinates() {
        let command = ControlCommand(type: "tap", x: -0.1, y: 0.5)
        XCTAssertThrowsError(try command.validated())
    }

    func testValidatesSwipeDuration() {
        let command = ControlCommand(
            type: "swipe",
            x: 0.5,
            y: 0.8,
            x2: 0.5,
            y2: 0.2,
            durationMs: 350
        )
        XCTAssertNoThrow(try command.validated())
    }

    func testOnlyAllowsKnownShortcuts() {
        XCTAssertNoThrow(
            try ControlCommand(type: "shortcut", name: "home").validated()
        )
        XCTAssertThrowsError(
            try ControlCommand(type: "shortcut", name: "power").validated()
        )
    }

    func testRejectsLegacyPointerPhases() {
        XCTAssertThrowsError(
            try ControlCommand(type: "pointer", x: 0.5, y: 0.5).validated()
        )
    }
}
