import PhoneUseProtocol
import XCTest

final class ControlCapabilitiesTests: XCTestCase {
    func testPointerOnlyCapabilityCannotAuthorizeKeyboardOrShortcuts() throws {
        let capabilities = ControlCapabilities(
            pointer: true,
            keyboard: false,
            shortcuts: false
        )
        let token = String(repeating: "a", count: 64)

        XCTAssertTrue(
            capabilities.supports(
                try ControlCommand(
                    type: "tap",
                    x: 0.5,
                    y: 0.5,
                    expectedFrameToken: token
                ).validated().action
            )
        )
        XCTAssertFalse(
            capabilities.supports(
                try ControlCommand(
                    type: "type",
                    text: "hello",
                    expectedFrameToken: token
                ).validated().action
            )
        )
        XCTAssertFalse(
            capabilities.supports(
                try ControlCommand(
                    type: "shortcut",
                    name: "home",
                    expectedFrameToken: token
                ).validated().action
            )
        )
    }
}
