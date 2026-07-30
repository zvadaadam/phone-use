import Foundation
import MirrorCore

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
    let transportName: String
    private let transport: PhoneTransport

    init(state: BrokerState) {
        self.state = state
        let environment = ProcessInfo.processInfo.environment
        if environment["MIRROR_RELAY_TRANSPORT"] == "webdriveragent" {
            let rawURL = environment["MIRROR_RELAY_WDA_URL"]
                ?? "http://127.0.0.1:8100"
            let baseURL = URL(string: rawURL)
                ?? URL(string: "http://127.0.0.1:8100")!
            let applicationSupport = Self.applicationSupportDirectory()
            let configuredProject = environment["MIRROR_RELAY_WDA_PROJECT"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            let projectManager = configuredProject == nil
                ? WebDriverAgentProjectManager(
                    projectRootURL: applicationSupport.appendingPathComponent(
                        "WebDriverAgent",
                        isDirectory: true
                    )
                )
                : nil
            let projectURL = configuredProject
                ?? projectManager!.projectURL
            let executableURL = URL(
                fileURLWithPath: environment["MIRROR_RELAY_WDA_XCODEBUILD"]
                    ?? "/usr/bin/xcrun"
            )
            let launcher = WebDriverAgentLauncher(
                configuration: .init(
                    projectURL: projectURL,
                    executableURL: executableURL,
                    deviceIdentifier: environment["MIRROR_RELAY_WDA_DEVICE_ID"],
                    derivedDataURL: applicationSupport.appendingPathComponent(
                        "WDA DerivedData",
                        isDirectory: true
                    ),
                    remotePort: UInt16(environment["MIRROR_RELAY_WDA_REMOTE_PORT"] ?? "")
                        ?? 8_100,
                    environment: [
                        "MIRROR_RELAY_MOCK_WDA_PORT":
                            environment["MIRROR_RELAY_MOCK_WDA_PORT"] ?? ""
                    ].filter { !$0.value.isEmpty }
                )
            )
            transport = WebDriverAgentTransport(
                state: state,
                baseURL: baseURL,
                launcher: launcher,
                projectManager: projectManager
            )
        } else {
            transport = AppleMirroringTransport(state: state)
        }
        transportName = transport.name
        state.setTransport(transport.name)
    }

    func start() {
        transport.start()
    }

    func stop() {
        transport.stop()
    }

    func ensureSession(timeout: Duration = .seconds(90)) async throws {
        try await transport.ensureSession(timeout: timeout)
    }

    func act(_ command: ControlCommand) async throws -> ActResult {
        _ = try command.validated()
        try await ensureSession()
        let before = state.frameMarker()
        try await transport.send(command)
        let shouldVerifyFrame = command.type != "pointer" || command.phase == "up"
        let after = shouldVerifyFrame
            ? await waitForChangedFrame(after: before, timeout: .seconds(2))
            : state.frameMarker()
        let snapshot = state.snapshot()
        return ActResult(
            success: true,
            beforeFrameID: before.id,
            afterFrameID: after.id,
            screenChanged: after.contentHash != before.contentHash,
            phase: snapshot.phase,
            message: snapshot.message
        )
    }

    func sourceJSON() async throws -> Data {
        try await ensureSession()
        return try await transport.sourceJSON()
    }

    func closeSession() async -> Bool {
        await transport.closeSession()
    }

    func sessionIsRunning() async -> Bool {
        await transport.isRunning()
    }

    func prepareAutomation() async throws -> URL {
        guard let transport = transport as? WebDriverAgentTransport else {
            throw SessionError(
                "WebDriverAgent setup is available only when the fallback transport is selected"
            )
        }
        return try await transport.prepareProject()
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

    private static func applicationSupportDirectory() -> URL {
        let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return (base ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("Mirror Relay", isDirectory: true)
    }
}
