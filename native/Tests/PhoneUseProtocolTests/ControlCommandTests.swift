import XCTest

@testable import PhoneUseProtocol

final class ControlCommandTests: XCTestCase {
    private let token = String(repeating: "a", count: 64)

    func testRejectsCoordinatesOutsideTheNormalizedFrame() {
        XCTAssertThrowsError(
            try ControlCommand(
                type: "tap",
                x: 1.1,
                y: 0.5,
                expectedFrameToken: token
            ).validated()
        )
    }

    func testRequiresAFreshFrameToken() {
        XCTAssertThrowsError(
            try ControlCommand(type: "tap", x: 0.5, y: 0.5).validated()
        )
        XCTAssertThrowsError(
            try ControlCommand(
                type: "tap",
                x: 0.5,
                y: 0.5,
                expectedFrameToken: "not-a-token"
            ).validated()
        )
    }

    func testValidatesEverySupportedAction() throws {
        XCTAssertEqual(
            try ControlCommand(
                type: "tap",
                x: 0.25,
                y: 0.75,
                expectedFrameToken: token
            ).validated().action,
            .tap(x: 0.25, y: 0.75)
        )
        XCTAssertEqual(
            try ControlCommand(
                type: "type",
                text: "hello",
                expectedFrameToken: token
            ).validated().action,
            .type("hello")
        )
        XCTAssertEqual(
            try ControlCommand(
                type: "shortcut",
                name: "home",
                expectedFrameToken: token
            ).validated().action,
            .shortcut(.home)
        )
    }
}
