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
    private let intentLock = NSLock()
    private var sessionIntent = SessionIntent.passive
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
        setSessionIntent(.closing)
        _ = session.requestClose()
        state.updateSession(.waitingForApplication)
        state.clearFrame()
    }

    func ensureSession(timeout: Duration) async throws {
        setSessionIntent(.requested)
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

    func send(_ command: ControlCommand) async throws {
        guard state.snapshot().phase == .streaming,
            target.current() != nil,
            session.inspect().state == .candidateLive
        else {
            throw SessionError(
                "iPhone Mirroring is no longer connected. Lock the iPhone and try again."
            )
        }
        guard try input.handle(command) else {
            throw SessionError("The bridge could not deliver the control command")
        }
    }

    func closeSession() async -> Bool {
        setSessionIntent(.closing)
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
        setSessionIntent(.passive)
        start()
        return closed
    }

    private func monitorSession() async {
        var readiness = MirroringSessionReadiness()
        var pausedSamples = 0
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
                pausedSamples = 0
                let ready = readiness.observe(
                    .candidateLive,
                    captureIsReady: state.captureIsReady()
                )
                state.updateSession(ready ? .connected : .confirming)
            case .paused:
                readiness.reset()
                state.updateSession(.waitingForPhone)
                if currentSessionIntent() == .requested {
                    if pausedSamples.isMultiple(of: 20) {
                        _ = session.performReconnectAction(from: inspection)
                    }
                    pausedSamples += 1
                } else {
                    pausedSamples = 0
                }
            case .indeterminate:
                pausedSamples = 0
                readiness.reset()
                state.updateSession(.confirming)
            case .noWindow, .notRunning:
                pausedSamples = 0
                readiness.reset()
                state.updateSession(.waitingForApplication)
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func setSessionIntent(_ intent: SessionIntent) {
        intentLock.lock()
        sessionIntent = intent
        intentLock.unlock()
    }

    private func currentSessionIntent() -> SessionIntent {
        intentLock.lock()
        defer { intentLock.unlock() }
        return sessionIntent
    }
}

private enum SessionIntent {
    case passive
    case requested
    case closing
}
