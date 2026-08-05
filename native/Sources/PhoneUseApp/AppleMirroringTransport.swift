import AppKit
import ApplicationServices
import Foundation
import PhoneUseCore
import PhoneUseProtocol

final class AppleMirroringTransport: @unchecked Sendable {
    private let state: BrokerState
    private let target: WindowTarget
    private let session: SessionController
    private let capture: MirrorCapture
    private let input: InputController
    private var captureTask: Task<Void, Never>?
    private var sessionMonitorTask: Task<Void, Never>?

    init(state: BrokerState) {
        let target = WindowTarget()
        self.state = state
        self.target = target
        session = SessionController(target: target)
        capture = MirrorCapture(output: state, target: target)
        input = InputController(logger: state, target: target)
    }

    func start() {
        if captureTask == nil {
            captureTask = Task { [capture] in
                await capture.run()
            }
        }
        if sessionMonitorTask == nil {
            sessionMonitorTask = Task { [weak self] in
                await self?.monitorSession()
            }
        }
    }

    func stop() {
        captureTask?.cancel()
        captureTask = nil
        sessionMonitorTask?.cancel()
        sessionMonitorTask = nil
        _ = session.requestClose()
        state.updateSession(.waitingForApplication)
        state.clearFrame()
    }

    func ensureSession(timeout: Duration) async throws {
        if state.snapshot().phase == .streaming, target.current() != nil {
            return
        }
        try await session.open()
        state.updatePermissions(
            BrokerPermissions(
                screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
                accessibilityAuthorized: AXIsProcessTrusted()
            )
        )
        state.updateSession(.confirming)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            let snapshot = state.snapshot()
            if snapshot.phase == .streaming, target.current() != nil {
                return
            }
            if !snapshot.screenCaptureAuthorized {
                throw SessionError("Screen Recording permission is required")
            }
            if !snapshot.accessibilityAuthorized {
                throw SessionError("Accessibility permission is required for iPhone control")
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw SessionError(
            "iPhone Mirroring did not reach a connected state. Keep the iPhone powered on, "
                + "near this Mac, recently unlocked, then lock it and try again."
        )
    }

    func send(_ command: ControlCommand) async throws -> InputDelivery {
        guard let targetSnapshot = target.current() else {
            throw SessionError(
                "iPhone Mirroring is no longer connected. Lock the iPhone and try again."
            )
        }
        let isFrontmost =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
            == targetSnapshot.processID
        guard isFrontmost else {
            throw SessionError(
                "Phone Use never changes Mac focus. Control is unavailable unless iPhone "
                    + "Mirroring is already frontmost."
            )
        }
        guard state.snapshot().phase == .streaming,
            session.inspect().state == .candidateLive
        else {
            throw SessionError(
                "iPhone Mirroring is no longer connected. Lock the iPhone and try again."
            )
        }
        let delivery = try input.handle(command)
        guard delivery.eventPosted else {
            throw SessionError("The bridge could not deliver the control command")
        }
        return delivery
    }

    func closeSession() async -> Bool {
        let monitorTask = sessionMonitorTask
        sessionMonitorTask = nil
        monitorTask?.cancel()
        await monitorTask?.value

        captureTask?.cancel()
        await captureTask?.value
        captureTask = nil
        let closed = await session.close()
        state.updateSession(.waitingForApplication)
        state.clearFrame()
        start()
        return closed
    }

    private func monitorSession() async {
        var readiness = MirroringSessionReadiness()
        while !Task.isCancelled {
            let permissions = BrokerPermissions(
                screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
                accessibilityAuthorized: AXIsProcessTrusted()
            )
            state.updatePermissions(permissions)

            guard permissions.screenCaptureAuthorized,
                permissions.accessibilityAuthorized
            else {
                readiness.reset()
                state.updateSession(.confirming)
                try? await Task.sleep(for: .milliseconds(250))
                continue
            }

            let inspection = session.inspect()
            switch inspection.state {
            case .candidateLive:
                let ready = readiness.observe(
                    .candidateLive,
                    captureIsReady: state.captureIsReady()
                )
                state.updateSession(ready ? .connected : .confirming)
            case .paused:
                readiness.reset()
                state.updateSession(.waitingForPhone)
            case .indeterminate:
                let ready = readiness.observe(
                    .indeterminate,
                    captureIsReady: state.captureIsReady()
                )
                state.updateSession(ready ? .connected : .confirming)
            case .noWindow:
                // WindowServer and Accessibility can briefly disagree while
                // ScreenCaptureKit still delivers the already-verified window.
                // Preserve continuity only for as long as that capture is fresh.
                let ready = readiness.observe(
                    .indeterminate,
                    captureIsReady: state.captureIsReady()
                )
                state.updateSession(ready ? .connected : .waitingForApplication)
            case .notRunning:
                readiness.reset()
                state.updateSession(.waitingForApplication)
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

}
