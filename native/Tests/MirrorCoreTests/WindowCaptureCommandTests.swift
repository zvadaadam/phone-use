import CoreGraphics
import XCTest

@testable import MirrorCore

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
}
