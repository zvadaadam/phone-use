import Foundation
import XCTest

@testable import PhoneUseApp
@testable import PhoneUseProtocol

final class BrokerStateTests: XCTestCase {
    func testInitialStatusIsTruthfulAndCapabilityFree() {
        let status = BrokerState().snapshot()
        XCTAssertEqual(status.phase, .unavailable)
        XCTAssertEqual(status.proof, .unimplemented)
        XCTAssertEqual(status.controlCapabilities, .none)
        XCTAssertNil(status.frame)
    }

    func testStatusObserversReceiveRuntimeAndLogs() {
        let state = BrokerState()
        let recorder = SnapshotRecorder()
        let observer = state.observeStatus { recorder.append($0) }

        state.update(
            DeviceHubRuntimeStatus(
                phase: .stopped,
                proof: .unimplemented,
                message: "Stopped for test",
                controlCapabilities: .none,
                frame: nil
            )
        )
        state.log("test event")
        state.removeStatusObserver(observer)

        let snapshots = recorder.values
        XCTAssertEqual(snapshots.count, 3)
        XCTAssertEqual(snapshots[1].phase, .stopped)
        XCTAssertEqual(snapshots.last?.logs, ["test event"])
    }
}

private final class SnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [PhoneUseStatus] = []

    var values: [PhoneUseStatus] {
        lock.withLock { snapshots }
    }

    func append(_ snapshot: PhoneUseStatus) {
        lock.withLock { snapshots.append(snapshot) }
    }
}
