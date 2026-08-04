import XCTest

@testable import MirrorCore

final class RelayStatusReducerTests: XCTestCase {
    private let capture = CaptureStatus(
        phase: .streaming,
        message: "Frames available",
        width: 354,
        height: 781
    )
    private let authorized = RelayPermissions(
        screenCaptureAuthorized: true,
        accessibilityAuthorized: true
    )

    func testPermissionsTakePriorityOverSessionAndCapture() {
        let status = RelayStatusReducer.reduce(
            session: .connected,
            capture: capture,
            permissions: RelayPermissions(
                screenCaptureAuthorized: false,
                accessibilityAuthorized: true
            ),
            hasFreshPublishedFrame: true
        )

        XCTAssertEqual(status.phase, .permission)
        XCTAssertEqual(status.message, "Screen Recording permission is required")
    }

    func testConnectedSessionRequiresANewPublishedFrame() {
        let status = RelayStatusReducer.reduce(
            session: .connected,
            capture: capture,
            permissions: authorized,
            hasFreshPublishedFrame: false
        )

        XCTAssertEqual(status.phase, .reconnecting)
        XCTAssertEqual(status.message, "Waiting for the first connected iPhone frame")
    }

    func testConnectedSessionPublishesCaptureStateAfterFreshFrame() {
        let status = RelayStatusReducer.reduce(
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
