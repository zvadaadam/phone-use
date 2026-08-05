import CoreGraphics
import XCTest

@testable import PhoneUseCore

final class WindowCaptureCommandTests: XCTestCase {
    func testBuildsWindowCaptureArguments() {
        XCTAssertEqual(
            WindowCaptureCommand.arguments(
                windowID: 42,
                outputPath: "/tmp/frame.png"
            ),
            ["-l", "42", "-x", "-o", "/tmp/frame.png"]
        )
    }

    func testSelectsApplicationWindowEvenWhenAXPointsAtLargerWelcomeWindow() {
        let candidates = [
            WindowCaptureCandidate(
                windowID: 1,
                processID: 10,
                bounds: CGRect(x: 960, y: 362, width: 640, height: 662),
                title: "Welcome to iPhone Mirroring"
            ),
            WindowCaptureCandidate(
                windowID: 2,
                processID: 10,
                bounds: CGRect(x: 1640, y: 418, width: 354, height: 781),
                title: "iPhone Mirroring"
            )
        ]

        XCTAssertEqual(
            WindowCaptureSelector.select(
                from: candidates,
                accessibilityBounds: candidates[0].bounds,
                localizedApplicationName: "iPhone Mirroring"
            )?.windowID,
            2
        )
    }

    func testSelectsApplicationTitledWindowWithoutAccessibility() {
        let candidates = [
            WindowCaptureCandidate(
                windowID: 1,
                processID: 10,
                bounds: CGRect(x: 0, y: 0, width: 900, height: 900),
                title: "Welcome to iPhone Mirroring"
            ),
            WindowCaptureCandidate(
                windowID: 2,
                processID: 10,
                bounds: CGRect(x: 50, y: 50, width: 350, height: 780),
                title: "iPhone Mirroring"
            )
        ]

        XCTAssertEqual(
            WindowCaptureSelector.select(
                from: candidates,
                accessibilityBounds: nil,
                localizedApplicationName: "iPhone Mirroring"
            )?.windowID,
            2
        )
    }

    func testFrameRateGateLimitsAcceptedFrames() {
        let gate = FrameRateGate(framesPerSecond: 10)

        XCTAssertTrue(gate.shouldAccept(at: 1))
        XCTAssertFalse(gate.shouldAccept(at: 1.05))
        XCTAssertTrue(gate.shouldAccept(at: 1.10))

        gate.reset()
        XCTAssertTrue(gate.shouldAccept(at: 1.11))
    }

    func testScreenCaptureGeometryAppliesBackingScale() {
        XCTAssertEqual(
            ScreenCaptureGeometry.pixels(
                for: CGSize(width: 354, height: 781),
                scale: 2
            ),
            ScreenCaptureGeometry(width: 708, height: 1_562)
        )
    }

    func testCapturePolicyOrdersIdleFallbackBeforeFrameExpiry() {
        XCTAssertLessThan(
            CapturePolicy.idleFallbackInterval,
            CapturePolicy.frameFreshnessInterval
        )
        XCTAssertLessThanOrEqual(
            CapturePolicy.outputFramesPerSecond,
            Double(CapturePolicy.sourceFramesPerSecond)
        )
    }

    func testCapturePolicyDecidesStreamTransitions() {
        let portrait = ScreenCaptureGeometry(width: 708, height: 1_562)
        let landscape = ScreenCaptureGeometry(width: 1_562, height: 708)
        let now = Date()

        XCTAssertTrue(
            CapturePolicy.shouldRestartStream(
                streamingWindowID: 42,
                candidateWindowID: 42,
                currentGeometry: portrait,
                expectedGeometry: landscape
            )
        )
        XCTAssertTrue(
            CapturePolicy.shouldAttemptStream(
                streamingWindowID: nil,
                candidateWindowID: 42,
                retryAt: now.addingTimeInterval(-1),
                now: now
            )
        )
        XCTAssertTrue(
            CapturePolicy.shouldUseHeartbeat(
                streamingWindowID: 42,
                candidateWindowID: 42,
                streamIsRunning: true,
                frameIsFresh: false
            )
        )
        XCTAssertFalse(
            CapturePolicy.shouldUseHeartbeat(
                streamingWindowID: 42,
                candidateWindowID: 42,
                streamIsRunning: true,
                frameIsFresh: true
            )
        )
    }
}
