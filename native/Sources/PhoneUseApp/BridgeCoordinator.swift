import Foundation
import PhoneUseCore
import PhoneUseProtocol

struct ActResult: Codable, Sendable {
    let success: Bool
    let eventPosted: Bool
    let deliveryCompleted: Bool
    let focusPreserved: Bool
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
            if let expectedFrameToken = command.expectedFrameToken,
                !VisualFrameFingerprint.isEquivalent(
                    expectedFrameToken,
                    before.token
                )
            {
                throw SessionError(
                    "The observed phone frame changed before the action. Observe again and retry."
                )
            }
            let delivery = try await transport.send(command)
            let after = await waitForChangedFrame(after: before, timeout: .seconds(2))
            let snapshot = state.snapshot()
            let screenChanged = VisualFrameFingerprint.isMeaningfullyChanged(
                before.token,
                after.token
            )
            return ActResult(
                success: delivery.completed
                    && delivery.focusPreserved
                    && screenChanged,
                eventPosted: delivery.eventPosted,
                deliveryCompleted: delivery.completed,
                focusPreserved: delivery.focusPreserved,
                beforeFrameID: before.id,
                afterFrameID: after.id,
                screenChanged: screenChanged,
                phase: snapshot.phase.rawValue,
                message: resultMessage(
                    delivery: delivery,
                    screenChanged: screenChanged
                )
            )
        }
    }

    private func resultMessage(
        delivery: InputDelivery,
        screenChanged: Bool
    ) -> String {
        if !delivery.completed {
            return "Input started but did not complete; observe the phone before retrying"
        }
        if !delivery.focusPreserved {
            return "Input completed, but Mac focus changed while it was in flight"
        }
        if screenChanged {
            return "Input completed and the phone changed without changing Mac focus"
        }
        return "Input completed, but no meaningful phone screen change was observed"
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
            if current.id > marker.id,
                VisualFrameFingerprint.isMeaningfullyChanged(
                    marker.token,
                    current.token
                )
            {
                return current
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return state.frameMarker()
    }
}
