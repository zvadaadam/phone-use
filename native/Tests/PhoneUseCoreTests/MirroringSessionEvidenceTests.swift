import XCTest

@testable import PhoneUseCore

final class MirroringSessionEvidenceTests: XCTestCase {
    typealias Element = MirroringSessionEvidence.Element

    func testNestedLiveControlIsCandidateLive() {
        let tree = Element(children: [
            Element(children: [
                Element(identifier: "app.grid.3x3")
            ])
        ])

        XCTAssertEqual(MirroringSessionEvidence.classify(root: tree), .candidateLive)
    }

    func testAppSwitcherControlIsCandidateLive() {
        let tree = Element(identifier: "iphone.app.switcher")

        XCTAssertEqual(MirroringSessionEvidence.classify(root: tree), .candidateLive)
    }

    func testOpaqueLiveWindowIsCandidateLive() {
        let bareWindow = Element(role: "AXWindow", title: "iPhone Mirroring")
        let windowWithEmptyContainer = Element(
            role: "AXWindow",
            title: "iPhone Mirroring",
            children: [Element(role: "AXGroup")]
        )

        XCTAssertEqual(
            MirroringSessionEvidence.classify(root: bareWindow),
            .candidateLive
        )
        XCTAssertEqual(
            MirroringSessionEvidence.classify(root: windowWithEmptyContainer),
            .candidateLive
        )
    }

    func testConnectingStatusIsPaused() {
        let tree = Element(children: [
            Element(role: "AXStaticText", title: "Connecting to iPhone")
        ])

        XCTAssertEqual(MirroringSessionEvidence.classify(root: tree), .paused)
    }

    func testPausedActionTakesPriorityOverConnectedToolbar() {
        let tree = Element(children: [
            Element(identifier: "app.grid.3x3"),
            Element(role: "AXButton", title: "Connect")
        ])

        XCTAssertEqual(MirroringSessionEvidence.classify(root: tree), .paused)
    }

    func testHiddenOrDisabledControlsAreIgnored() {
        let tree = Element(children: [
            Element(identifier: "app.grid.3x3", isHidden: true),
            Element(identifier: "iphone.app.switcher", isEnabled: false)
        ])

        XCTAssertEqual(MirroringSessionEvidence.classify(root: tree), .paused)
    }

    func testHiddenOrDisabledAncestorsHideTheirEvidence() {
        let hiddenConnectedTree = Element(
            isHidden: true,
            children: [
                Element(identifier: "app.grid.3x3")
            ])
        XCTAssertEqual(
            MirroringSessionEvidence.classify(root: hiddenConnectedTree),
            .paused
        )

        let visibleConnectedTree = Element(children: [
            Element(identifier: "app.grid.3x3"),
            Element(
                isEnabled: false,
                children: [
                    Element(role: "AXButton", title: "Connect")
                ])
        ])
        XCTAssertEqual(
            MirroringSessionEvidence.classify(root: visibleConnectedTree),
            .candidateLive
        )
    }

    func testTraversalHonorsDepthBoundary() {
        var inside = Element(identifier: "app.grid.3x3")
        for _ in 0..<7 {
            inside = Element(children: [inside])
        }
        XCTAssertEqual(MirroringSessionEvidence.classify(root: inside), .candidateLive)

        let outside = Element(children: [inside])
        XCTAssertEqual(MirroringSessionEvidence.classify(root: outside), .paused)
    }

    func testMissingAndUnrelatedControlsArePaused() {
        let tree = Element(children: [
            Element(identifier: "CloseButton"),
            Element(role: "AXButton", title: "Settings")
        ])

        XCTAssertEqual(MirroringSessionEvidence.classify(root: tree), .paused)
    }

    func testDescendantReadFailureIsIndeterminateInsteadOfOpaqueLive() {
        let apparentlyOpaqueTree = Element(
            role: "AXWindow",
            children: [Element(role: "AXGroup")]
        )

        XCTAssertEqual(
            MirroringSessionEvidence.classify(
                root: apparentlyOpaqueTree,
                hadReadFailure: true
            ),
            .indeterminate
        )
    }

    func testReadinessRequiresConsecutiveLiveCaptureSamples() {
        var readiness = MirroringSessionReadiness(requiredConsecutiveSamples: 3)

        XCTAssertFalse(readiness.observe(.candidateLive, captureIsReady: true))
        XCTAssertFalse(readiness.observe(.candidateLive, captureIsReady: true))
        XCTAssertTrue(readiness.observe(.candidateLive, captureIsReady: true))
    }

    func testReadinessResetsWhenEitherEvidenceDisappears() {
        var readiness = MirroringSessionReadiness(requiredConsecutiveSamples: 2)

        XCTAssertFalse(readiness.observe(.candidateLive, captureIsReady: true))
        XCTAssertFalse(readiness.observe(.candidateLive, captureIsReady: false))
        XCTAssertFalse(readiness.observe(.candidateLive, captureIsReady: true))
        XCTAssertFalse(readiness.observe(.paused, captureIsReady: true))
        XCTAssertFalse(readiness.observe(.candidateLive, captureIsReady: true))
        XCTAssertTrue(readiness.observe(.candidateLive, captureIsReady: true))
    }
}
