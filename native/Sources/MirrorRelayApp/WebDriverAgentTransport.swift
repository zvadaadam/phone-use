import ApplicationServices
import CoreGraphics
import Foundation
import MirrorCore

final class WebDriverAgentTransport: PhoneTransport, @unchecked Sendable {
    let name = "webdriveragent"

    private struct PointerGesture {
        var startX: Double
        var startY: Double
        var lastX: Double
        var lastY: Double
        var startedAt: ContinuousClock.Instant
    }

    private let state: BrokerState
    private let launcher: WebDriverAgentLauncher?
    private let projectManager: WebDriverAgentProjectManager?
    private let connectionLock = NSLock()
    private let pointerLock = NSLock()
    private let sessionLock = NSLock()
    private let startupLock = NSLock()
    private var client: WebDriverAgentClient
    private var baseURL: URL
    private var pointerGesture: PointerGesture?
    private var sessionRunning = false
    private var pollingTask: Task<Void, Never>?
    private var startupTask: Task<Void, Error>?

    init(
        state: BrokerState,
        baseURL: URL,
        launcher: WebDriverAgentLauncher? = nil,
        projectManager: WebDriverAgentProjectManager? = nil
    ) {
        self.state = state
        self.launcher = launcher
        self.projectManager = projectManager
        self.baseURL = baseURL
        client = WebDriverAgentClient(baseURL: baseURL)
    }

    func start() {
        let baseURL = currentBaseURL()
        state.status(
            phase: "waiting",
            message: "Waiting for WebDriverAgent at \(baseURL.absoluteString)",
            screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
            accessibilityAuthorized: AXIsProcessTrusted()
        )
        state.log("WebDriverAgent transport selected")
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        launcher?.stop()
    }

    func isAvailable() async -> Bool {
        await currentClient().isReady()
    }

    func ensureSession(timeout: Duration) async throws {
        if await isRunning() {
            return
        }

        let task = startupLock.withLock { () -> Task<Void, Error> in
            if let startupTask {
                return startupTask
            }
            let task = Task { [weak self] in
                guard let self else {
                    throw SessionError("WebDriverAgent transport stopped during startup")
                }
                try await establishSession(timeout: timeout)
            }
            startupTask = task
            return task
        }
        do {
            try await task.value
            startupLock.withLock {
                startupTask = nil
            }
        } catch {
            startupLock.withLock {
                startupTask = nil
            }
            throw error
        }
    }

    private func establishSession(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        if !(await currentClient().isReady()), let launcher {
            state.status(
                phase: "launching",
                message: "Starting the signed WebDriverAgentRunner",
                screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
                accessibilityAuthorized: AXIsProcessTrusted()
            )
            do {
                let endpoint = try await launcher.start(
                    timeout: Self.seconds(in: timeout)
                ) { [weak self] message in
                    guard !message.isEmpty else { return }
                    self?.state.log("WDA: \(message.suffix(600))")
                }
                updateEndpoint(endpoint)
                state.log("WebDriverAgent endpoint discovered at \(endpoint.absoluteString)")
            } catch {
                state.status(
                    phase: "setup",
                    message: error.localizedDescription,
                    screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
                    accessibilityAuthorized: AXIsProcessTrusted()
                )
                throw SessionError(error.localizedDescription)
            }
        }

        while clock.now < deadline {
            let client = currentClient()
            if await client.isReady() {
                do {
                    let screen = try await client.openSession()
                    setSessionRunning(true)
                    state.status(
                        phase: "binding",
                        message: "WebDriverAgent session started; capturing the iPhone",
                        width: Int(screen.width),
                        height: Int(screen.height),
                        screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
                        accessibilityAuthorized: AXIsProcessTrusted()
                    )
                    try await captureAndPublish(screen: screen)
                    startPolling(screen: screen)
                    return
                } catch {
                    setSessionRunning(false)
                    throw error
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }

        throw SessionError(
            "WebDriverAgent is not reachable at \(currentBaseURL().absoluteString). "
                + "Connect the iPhone, unlock it, enable Developer Mode and UI Automation, "
                + "then start the signed WebDriverAgentRunner."
        )
    }

    func send(_ command: ControlCommand) async throws {
        let client = currentClient()
        if command.type == "pointer" {
            try await sendPointer(command, client: client)
            return
        }
        try await client.perform(command)
        try await captureAndPublish(screen: try await client.screen())
    }

    func sourceJSON() async throws -> Data {
        try await currentClient().sourceJSON()
    }

    func closeSession() async -> Bool {
        pollingTask?.cancel()
        pollingTask = nil
        do {
            let client = currentClient()
            try await client.closeSession()
            setSessionRunning(false)
            state.status(
                phase: "stopped",
                message: "WebDriverAgent session closed",
                screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
                accessibilityAuthorized: AXIsProcessTrusted()
            )
            launcher?.stop()
            return true
        } catch {
            launcher?.stop()
            state.log("Could not close WebDriverAgent session: \(error.localizedDescription)")
            return false
        }
    }

    func isRunning() async -> Bool {
        sessionLock.withLock { sessionRunning }
    }

    func prepareProject() async throws -> URL {
        guard let projectManager else {
            throw SessionError(
                "This WebDriverAgent project path is externally managed and cannot be prepared by Mirror Relay"
            )
        }
        state.status(
            phase: "setup",
            message: "Preparing WebDriverAgent for one-time Xcode signing",
            screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
            accessibilityAuthorized: AXIsProcessTrusted()
        )
        let projectURL = try await projectManager.prepare { [weak self] message in
            self?.state.log(message)
        }
        state.status(
            phase: "setup",
            message: "Choose your development team for WebDriverAgentRunner in Xcode",
            screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
            accessibilityAuthorized: AXIsProcessTrusted()
        )
        return projectURL
    }

    private func sendPointer(
        _ command: ControlCommand,
        client: WebDriverAgentClient
    ) async throws {
        guard let phase = command.phase,
              let x = command.x,
              let y = command.y
        else {
            throw SessionError("Pointer command is incomplete")
        }

        switch phase {
        case "down":
            pointerLock.withLock {
                pointerGesture = PointerGesture(
                    startX: x,
                    startY: y,
                    lastX: x,
                    lastY: y,
                    startedAt: ContinuousClock.now
                )
            }
        case "move":
            pointerLock.withLock {
                pointerGesture?.lastX = x
                pointerGesture?.lastY = y
            }
        case "up":
            let gesture = pointerLock.withLock {
                let value = pointerGesture
                pointerGesture = nil
                return value
            }

            guard let gesture else {
                try await client.tap(x: x, y: y)
                try await captureAndPublish(screen: try await client.screen())
                return
            }
            let distance = hypot(x - gesture.startX, y - gesture.startY)
            if distance < 0.012 {
                try await client.tap(x: x, y: y)
            } else {
                let duration = gesture.startedAt.duration(to: .now)
                let components = duration.components
                let seconds = Double(components.seconds)
                    + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
                try await client.drag(
                    fromX: gesture.startX,
                    fromY: gesture.startY,
                    toX: x,
                    toY: y,
                    duration: seconds
                )
            }
            try await captureAndPublish(screen: try await client.screen())
        default:
            throw SessionError("Unknown pointer phase")
        }
    }

    private func startPolling(screen: WebDriverAgentScreen) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await captureAndPublish(screen: screen)
                } catch {
                    state.status(
                        phase: "reconnecting",
                        message: "WebDriverAgent capture failed: \(error.localizedDescription)",
                        width: Int(screen.width),
                        height: Int(screen.height),
                        screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
                        accessibilityAuthorized: AXIsProcessTrusted()
                    )
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func captureAndPublish(screen: WebDriverAgentScreen) async throws {
        let frame = try await currentClient().screenshotJPEG()
        state.status(
            phase: "streaming",
            message: "Real iPhone is live through WebDriverAgent",
            width: Int(screen.width),
            height: Int(screen.height),
            screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
            accessibilityAuthorized: AXIsProcessTrusted()
        )
        state.frame(frame)
    }

    private func setSessionRunning(_ value: Bool) {
        sessionLock.withLock {
            sessionRunning = value
        }
    }

    private func currentClient() -> WebDriverAgentClient {
        connectionLock.withLock { client }
    }

    private func currentBaseURL() -> URL {
        connectionLock.withLock { baseURL }
    }

    private func updateEndpoint(_ url: URL) {
        connectionLock.withLock {
            baseURL = url
            client = WebDriverAgentClient(baseURL: url)
        }
    }

    private static func seconds(in duration: Duration) -> TimeInterval {
        let components = duration.components
        return max(
            1,
            Double(components.seconds)
                + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
        )
    }
}
