import XCTest

@testable import PhoneUseCore

final class BrokerStatusReducerTests: XCTestCase {
    private let capture = CaptureStatus(
        phase: .streaming,
        message: "Frames available",
        width: 354,
        height: 781
    )
    private let authorized = BrokerPermissions(
        screenCaptureAuthorized: true,
        accessibilityAuthorized: true
    )

    func testPermissionsTakePriorityOverSessionAndCapture() {
        let status = BrokerStatusReducer.reduce(
            session: .connected,
            capture: capture,
            permissions: BrokerPermissions(
                screenCaptureAuthorized: false,
                accessibilityAuthorized: true
            ),
            hasFreshPublishedFrame: true
        )

        XCTAssertEqual(status.phase, .permission)
        XCTAssertEqual(status.message, "Screen Recording permission is required")
    }

    func testConnectedSessionRequiresANewPublishedFrame() {
        let status = BrokerStatusReducer.reduce(
            session: .connected,
            capture: capture,
            permissions: authorized,
            hasFreshPublishedFrame: false
        )

        XCTAssertEqual(status.phase, .reconnecting)
        XCTAssertEqual(status.message, "Waiting for the first connected iPhone frame")
    }

    func testConnectedSessionPublishesCaptureStateAfterFreshFrame() {
        let status = BrokerStatusReducer.reduce(
            session: .connected,
            capture: capture,
            permissions: authorized,
            hasFreshPublishedFrame: true
        )

        XCTAssertEqual(status.phase, .streaming)
        XCTAssertEqual(status.width, 354)
        XCTAssertEqual(status.height, 781)
    }
}
