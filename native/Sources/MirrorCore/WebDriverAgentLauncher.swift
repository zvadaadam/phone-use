import Foundation

public final class WebDriverAgentLauncher: @unchecked Sendable {
    public struct Configuration: Sendable {
        public let projectURL: URL
        public let executableURL: URL
        public let deviceIdentifier: String?
        public let derivedDataURL: URL
        public let remotePort: UInt16
        public let environment: [String: String]

        public init(
            projectURL: URL,
            executableURL: URL = URL(fileURLWithPath: "/usr/bin/xcrun"),
            deviceIdentifier: String? = nil,
            derivedDataURL: URL,
            remotePort: UInt16 = 8_100,
            environment: [String: String] = [:]
        ) {
            self.projectURL = projectURL
            self.executableURL = executableURL
            self.deviceIdentifier = deviceIdentifier
            self.derivedDataURL = derivedDataURL
            self.remotePort = remotePort
            self.environment = environment
        }
    }

    private let configuration: Configuration
    private let lock = NSLock()
    private var process: Process?
    private var outputPipe: Pipe?
    private var endpoint: URL?

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    deinit {
        stop()
    }

    public func start(
        timeout: TimeInterval = 90,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> URL {
        if let endpoint = lock.withLock({ self.endpoint }),
           lock.withLock({ self.process?.isRunning == true }) {
            return endpoint
        }

        guard FileManager.default.fileExists(atPath: configuration.projectURL.path) else {
            throw WebDriverAgentLaunchError(
                "WebDriverAgent is not installed at \(configuration.projectURL.path)"
            )
        }

        let deviceIdentifier = if let configured = configuration.deviceIdentifier,
                                  !configured.isEmpty {
            configured
        } else {
            try await Self.discoverIPhoneIdentifier()
        }

        try FileManager.default.createDirectory(
            at: configuration.derivedDataURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let process = Process()
        let pipe = Pipe()
        process.executableURL = configuration.executableURL
        process.arguments = Self.xcodebuildArguments(
            executableURL: configuration.executableURL,
            projectURL: configuration.projectURL,
            deviceIdentifier: deviceIdentifier,
            derivedDataURL: configuration.derivedDataURL
        )
        var environment = ProcessInfo.processInfo.environment
        environment["USE_PORT"] = String(configuration.remotePort)
        environment["NSUnbufferedIO"] = "YES"
        for (key, value) in configuration.environment {
            environment[key] = value
        }
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe

        lock.withLock {
            self.process = process
            outputPipe = pipe
            endpoint = nil
        }

        do {
            try process.run()
            let waiter = EndpointWaiter(
                pipe: pipe,
                process: process,
                timeout: timeout,
                log: log
            )
            let endpoint = try await waiter.wait()
            lock.withLock {
                self.endpoint = endpoint
            }
            log("WebDriverAgent is reachable at \(endpoint.absoluteString)")
            return endpoint
        } catch {
            stop()
            if let error = error as? WebDriverAgentLaunchError {
                throw error
            }
            throw WebDriverAgentLaunchError(
                "Could not start WebDriverAgentRunner: \(error.localizedDescription)"
            )
        }
    }

    public func stop() {
        let values = lock.withLock { () -> (Process?, Pipe?) in
            let values = (process, outputPipe)
            process = nil
            outputPipe = nil
            endpoint = nil
            return values
        }
        values.1?.fileHandleForReading.readabilityHandler = nil
        if values.0?.isRunning == true {
            values.0?.terminate()
        }
    }

    public static func xcodebuildArguments(
        executableURL: URL,
        projectURL: URL,
        deviceIdentifier: String,
        derivedDataURL: URL
    ) -> [String] {
        var arguments: [String] = []
        if executableURL.lastPathComponent == "xcrun" {
            arguments.append("xcodebuild")
        }
        arguments += [
            "-project", projectURL.path,
            "-scheme", "WebDriverAgentRunner",
            "-destination", "id=\(deviceIdentifier)",
            "-destination-timeout", "10",
            "-derivedDataPath", derivedDataURL.path,
            "test"
        ]
        return arguments
    }

    public static func serverURL(in output: String) -> URL? {
        guard let markerStart = output.range(of: "ServerURLHere->") else {
            return nil
        }
        let remainder = output[markerStart.upperBound...]
        guard let markerEnd = remainder.range(of: "<-ServerURLHere") else {
            return nil
        }
        return URL(string: String(remainder[..<markerEnd.lowerBound]))
    }

    public static func diagnosticSummary(in output: String) -> String? {
        let diagnosticLines = output
            .split(whereSeparator: \.isNewline)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                let value = line.lowercased()
                return value.contains("error:")
                    || value.contains("requires a development team")
                    || value.contains("no signing certificate")
                    || value.contains("not available because")
                    || value.contains("provisioning profile")
            }
        guard !diagnosticLines.isEmpty else {
            return nil
        }
        return diagnosticLines.suffix(4).joined(separator: " ")
    }

    public static func firstIPhoneIdentifier(in data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let devices = result["devices"] as? [[String: Any]]
        else {
            throw WebDriverAgentLaunchError("CoreDevice returned an invalid device list")
        }
        var foundIPhone = false
        var foundUnpairedIPhone = false
        for device in devices where Self.isIPhone(device) {
            foundIPhone = true
            let connection = device["connectionProperties"] as? [String: Any]
            if let pairingState = connection?["pairingState"] as? String,
               pairingState.caseInsensitiveCompare("unpaired") == .orderedSame {
                foundUnpairedIPhone = true
                continue
            }
            let hardware = device["hardwareProperties"] as? [String: Any]
            if let udid = hardware?["udid"] as? String, !udid.isEmpty {
                return udid
            }
        }
        if foundUnpairedIPhone {
            throw WebDriverAgentLaunchError(
                "The iPhone is connected but not paired. Open Xcode → Window → "
                    + "Devices and Simulators, select the iPhone, click Pair, and "
                    + "approve the prompt on the unlocked iPhone."
            )
        }
        if foundIPhone {
            throw WebDriverAgentLaunchError(
                "CoreDevice found the iPhone but did not provide its hardware UDID"
            )
        }
        throw WebDriverAgentLaunchError(
            "No paired iPhone is visible. Connect it by USB, unlock it, and approve Trust."
        )
    }

    private static func discoverIPhoneIdentifier() async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let outputURL = fileManager.temporaryDirectory
                .appendingPathComponent("mirror-relay-devices-\(UUID().uuidString).json")
            defer {
                try? fileManager.removeItem(at: outputURL)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "devicectl", "list", "devices",
                "--json-output", outputURL.path
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let data = try? Data(contentsOf: outputURL)
            else {
                throw WebDriverAgentLaunchError("CoreDevice could not enumerate iPhones")
            }
            return try firstIPhoneIdentifier(in: data)
        }.value
    }

    private static func isIPhone(_ device: [String: Any]) -> Bool {
        let hardware = device["hardwareProperties"] as? [String: Any]
        let properties = device["deviceProperties"] as? [String: Any]
        let candidates = [
            hardware?["platform"] as? String,
            hardware?["productType"] as? String,
            properties?["deviceType"] as? String,
            properties?["name"] as? String
        ]
        return candidates.compactMap { $0 }.contains {
            let value = $0.lowercased()
            return value.contains("iphone") || value == "ios"
        }
    }
}

public final class WebDriverAgentProjectManager: @unchecked Sendable {
    public static let pinnedTag = "v16.0.3"
    public static let repositoryURL = URL(
        string: "https://github.com/appium/WebDriverAgent.git"
    )!

    public let projectRootURL: URL

    public init(projectRootURL: URL) {
        self.projectRootURL = projectRootURL
    }

    public var projectURL: URL {
        projectRootURL.appendingPathComponent(
            "WebDriverAgent.xcodeproj",
            isDirectory: true
        )
    }

    public func prepare(
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> URL {
        if FileManager.default.fileExists(atPath: projectURL.path) {
            return projectURL
        }

        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let parent = self.projectRootURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let staging = parent.appendingPathComponent(
                "WebDriverAgent.download-\(UUID().uuidString)",
                isDirectory: true
            )
            defer {
                try? fileManager.removeItem(at: staging)
            }

            log("Downloading WebDriverAgent \(Self.pinnedTag)")
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = [
                "clone",
                "--depth", "1",
                "--branch", Self.pinnedTag,
                Self.repositoryURL.absoluteString,
                staging.path
            ]
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let detail = String(
                    data: pipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? "git clone failed"
                throw WebDriverAgentLaunchError(
                    "Could not download WebDriverAgent: \(detail)"
                )
            }
            guard fileManager.fileExists(
                atPath: staging
                    .appendingPathComponent("WebDriverAgent.xcodeproj")
                    .path
            ) else {
                throw WebDriverAgentLaunchError(
                    "The WebDriverAgent download did not contain its Xcode project"
                )
            }
            try fileManager.moveItem(at: staging, to: self.projectRootURL)
            log("WebDriverAgent \(Self.pinnedTag) is ready for signing")
            return self.projectURL
        }.value
    }
}

public struct WebDriverAgentLaunchError: LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

private final class EndpointWaiter: @unchecked Sendable {
    private let pipe: Pipe
    private let process: Process
    private let timeout: TimeInterval
    private let log: @Sendable (String) -> Void
    private let lock = NSLock()
    private var buffer = ""
    private var completed = false
    private var continuation: CheckedContinuation<URL, Error>?
    private var timer: DispatchSourceTimer?

    init(
        pipe: Pipe,
        process: Process,
        timeout: TimeInterval,
        log: @escaping @Sendable (String) -> Void
    ) {
        self.pipe = pipe
        self.process = process
        self.timeout = timeout
        self.log = log
    }

    func wait() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
            }

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self?.consume(data)
            }
            process.terminationHandler = { [weak self] process in
                self?.processDidTerminate(status: process.terminationStatus)
            }

            let timer = DispatchSource.makeTimerSource(
                queue: DispatchQueue.global(qos: .userInitiated)
            )
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler { [weak self] in
                self?.finish(
                    .failure(
                        WebDriverAgentLaunchError(
                            "Timed out after \(Int(self?.timeout ?? 0)) seconds "
                                + "waiting for WebDriverAgentRunner"
                        )
                    )
                )
            }
            lock.withLock {
                self.timer = timer
            }
            timer.resume()
        }
    }

    private func consume(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        log(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let url = lock.withLock { () -> URL? in
            guard !completed else { return nil }
            buffer.append(text)
            if buffer.count > 128_000 {
                buffer.removeFirst(buffer.count - 128_000)
            }
            return WebDriverAgentLauncher.serverURL(in: buffer)
        }
        if let url {
            finish(.success(url))
        }
    }

    private func processDidTerminate(status: Int32) {
        let output = lock.withLock { buffer }
        let detail = WebDriverAgentLauncher.diagnosticSummary(in: output)
        var message = "xcodebuild exited with status \(status) before "
            + "WebDriverAgent announced its URL"
        if let detail {
            message += ": \(detail)"
        }
        finish(.failure(WebDriverAgentLaunchError(message)))
    }

    private func finish(_ result: Result<URL, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<URL, Error>? in
            guard !completed else { return nil }
            completed = true
            timer?.cancel()
            timer = nil
            let value = self.continuation
            self.continuation = nil
            return value
        }
        guard let continuation else { return }
        if case .success = result {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }
        } else {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        continuation.resume(with: result)
    }
}
