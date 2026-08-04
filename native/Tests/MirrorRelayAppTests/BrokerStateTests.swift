import Foundation
import MirrorCore
import XCTest

@testable import MirrorRelayApp

final class BrokerStateTests: XCTestCase {
    func testDropsFramesUntilStableSessionAndRequiresANewFrame() {
        let state = readyState()
        state.updateSession(.confirming)

        state.frame(Data("pre-session".utf8))
        XCTAssertEqual(state.frameMarker().id, 0)
        XCTAssertNil(state.latestFrame())

        state.updateSession(.connected)
        XCTAssertEqual(state.snapshot().phase, .reconnecting)
        XCTAssertNil(state.latestFrame())

        let connectedFrame = Data("connected".utf8)
        state.frame(connectedFrame)
        XCTAssertEqual(state.snapshot().phase, .streaming)
        XCTAssertEqual(state.frameMarker().id, 1)
        XCTAssertEqual(state.latestFrame()?.data, connectedFrame)
    }

    func testLeavingConnectedStateAtomicallyClearsPublishedFrame() {
        let state = readyState()
        state.updateSession(.connected)
        state.frame(Data("connected".utf8))
        XCTAssertNotNil(state.latestFrame())

        state.updateSession(.waitingForPhone)

        XCTAssertEqual(state.snapshot().phase, .waiting)
        XCTAssertEqual(state.snapshot().fps, 0)
        XCTAssertNil(state.latestFrame())
        XCTAssertEqual(state.frameMarker().contentHash, 0)
    }

    func testCaptureFailureCannotReopenPreviousFrame() {
        let state = readyState()
        state.updateSession(.connected)
        state.frame(Data("first".utf8))
        XCTAssertNotNil(state.latestFrame())

        state.status(
            CaptureStatus(
                phase: .reconnecting,
                message: "Capture paused",
                width: 354,
                height: 781
            )
        )
        state.status(streamingCaptureStatus())

        XCTAssertEqual(state.snapshot().phase, .reconnecting)
        XCTAssertNil(state.latestFrame())
        state.frame(Data("second".utf8))
        XCTAssertEqual(state.snapshot().phase, .streaming)
    }

    private func readyState() -> BrokerState {
        let state = BrokerState()
        state.updatePermissions(
            RelayPermissions(
                screenCaptureAuthorized: true,
                accessibilityAuthorized: true
            )
        )
        state.status(streamingCaptureStatus())
        return state
    }

    private func streamingCaptureStatus() -> CaptureStatus {
        CaptureStatus(
            phase: .streaming,
            message: "Frames available",
            width: 354,
            height: 781
        )
    }
}
