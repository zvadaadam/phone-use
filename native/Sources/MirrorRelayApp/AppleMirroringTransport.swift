import AppKit
import ApplicationServices
import Foundation
import MirrorCore

final class AppleMirroringTransport: PhoneTransport, @unchecked Sendable {
    let name = "iphone-mirroring"

    private let state: BrokerState
    private let target = WindowTarget()
    private let session = SessionController()
    private let capture: MirrorCapture
    private let input: InputController
    private var captureTask: Task<Void, Never>?

    init(state: BrokerState) {
        self.state = state
        capture = MirrorCapture(output: state, target: target)
        input = InputController(output: state, target: target)
    }

    func start() {
        guard captureTask == nil else { return }
        captureTask = Task { [capture] in
            await capture.run()
        }
    }

    func stop() {
        captureTask?.cancel()
        captureTask = nil
    }

    func isAvailable() async -> Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: SessionController.mirroringBundleIdentifier
        ) != nil
    }

    func ensureSession(timeout: Duration) async throws {
        try await session.open()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var attempts = 0
        while clock.now < deadline {
            let snapshot = state.snapshot()
            let connectionState = session.connectionState()
            if connectionState == .connected,
               target.current() != nil,
               snapshot.fps > 0 {
                state.status(
                    phase: "streaming",
                    message: "Locked iPhone is connected through iPhone Mirroring",
                    width: snapshot.width,
                    height: snapshot.height,
                    screenCaptureAuthorized: snapshot.screenCaptureAuthorized,
                    accessibilityAuthorized: snapshot.accessibilityAuthorized
                )
                return
            }
            if attempts.isMultiple(of: 5) {
                session.attemptConnect()
            }
            attempts += 1
            if !CGPreflightScreenCaptureAccess() {
                throw SessionError("Screen Recording permission is required")
            }
            if !AXIsProcessTrusted() {
                throw SessionError("Accessibility permission is required for iPhone control")
            }
            if connectionState == .paused {
                state.status(
                    phase: "waiting",
                    message: "Keep the iPhone powered on, nearby, and locked so Mirroring can connect",
                    width: snapshot.width,
                    height: snapshot.height,
                    screenCaptureAuthorized: snapshot.screenCaptureAuthorized,
                    accessibilityAuthorized: snapshot.accessibilityAuthorized
                )
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        throw SessionError(
            "iPhone Mirroring did not reach a connected state. Keep the iPhone powered on, "
                + "near this Mac, recently unlocked, then lock it and try again."
        )
    }

    func send(_ command: ControlCommand) async throws {
        guard try input.handle(command) else {
            throw SessionError("The bridge could not deliver the control command")
        }
    }

    func sourceJSON() async throws -> Data {
        throw SessionError(
            "Apple iPhone Mirroring does not expose the phone accessibility tree to Mac apps"
        )
    }

    func closeSession() async -> Bool {
        session.close()
    }

    func isRunning() async -> Bool {
        session.isRunning()
    }
}
