import Foundation
import PhoneUseCore
import PhoneUseProtocol

struct ActResult: Codable, Sendable {
    let success: Bool
    let beforeFrameID: UInt64
    let afterFrameID: UInt64
    let screenChanged: Bool
    let phase: String
    let message: String
}

final class BridgeCoordinator: @unchecked Sendable {
    let state: BrokerState
    let transportName = "iphone-mirroring"

    private let transport: AppleMirroringTransport
    private let operations = AsyncMutex()

    init(state: BrokerState) {
        self.state = state
        transport = AppleMirroringTransport(state: state)
        state.setTransport(transportName)
    }

    func start() {
        transport.start()
    }

    func stop() {
        transport.stop()
        state.clearFrame()
    }

    func ensureSession(timeout: Duration = .seconds(90)) async throws {
        try await operations.withLock { [transport] in
            try await transport.ensureSession(timeout: timeout)
        }
    }

    func act(_ command: ControlCommand) async throws -> ActResult {
        try await operations.withLock { [self] in
            let command = try command.validated()
            try await transport.ensureSession(timeout: .seconds(90))
            let before = state.frameMarker()
            try await transport.send(command)
            let after = await waitForChangedFrame(after: before, timeout: .seconds(2))
            let snapshot = state.snapshot()
            return ActResult(
                success: true,
                beforeFrameID: before.id,
                afterFrameID: after.id,
                screenChanged: after.contentHash != before.contentHash,
                phase: snapshot.phase.rawValue,
                message: snapshot.message
            )
        }
    }

    func closeSession() async -> Bool {
        await operations.withLock { [self] in
            let closed = await transport.closeSession()
            state.clearFrame()
            return closed
        }
    }

    private func waitForChangedFrame(
        after marker: FrameMarker,
        timeout: Duration
    ) async -> FrameMarker {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            let current = state.frameMarker()
            if current.id > marker.id, current.contentHash != marker.contentHash {
                return current
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return state.frameMarker()
    }
}
