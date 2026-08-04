import AppKit
import Foundation
import PhoneUseProtocol

@main
struct PhoneUseCLI {
    private static let productName = PhoneUseProtocolMetadata.displayName
    private static let commandName = PhoneUseProtocolMetadata.commandName

    private static let baseURL: URL = {
        let port =
            UInt16(ProcessInfo.processInfo.environment["PHONE_USE_PORT"] ?? "")
            ?? 8_747
        return URL(string: "http://127.0.0.1:\(port)")!
    }()

    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(
                Data("\(commandName): \(error.localizedDescription)\n".utf8)
            )
            Foundation.exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            throw CLIError(usage)
        }
        if ["help", "--help", "-h"].contains(command) {
            print(usage)
            return
        }
        if command == "version" || command == "--version" {
            print("\(productName) \(currentVersion())")
            return
        }

        let token = try await loadTokenStartingBrokerIfNeeded()
        let brokerStatus = try await compatibleBrokerStatus(token: token)
        switch command {
        case "dashboard":
            let response = try await request(
                method: "POST",
                path: "/api/dashboard/bootstrap",
                token: token
            )
            let bootstrap = try JSONDecoder().decode(
                DashboardBootstrapResponse.self,
                from: response.data
            )
            guard let url = URL(string: bootstrap.path, relativeTo: baseURL)?.absoluteURL else {
                throw CLIError("\(productName) returned an invalid dashboard URL")
            }
            guard NSWorkspace.shared.open(url) else {
                throw CLIError("Could not open the \(productName) dashboard")
            }
            print("Opened \(productName) dashboard")
        case "doctor":
            try printDoctor(status: brokerStatus)
        case "status":
            try await printResponse(method: "GET", path: "/api/status", token: token)
        case "open":
            try await printResponse(method: "POST", path: "/api/session/open", token: token)
        case "close":
            try await printResponse(method: "POST", path: "/api/session/close", token: token)
        case "observe":
            guard arguments.count == 2 else {
                throw CLIError("Usage: \(commandName) observe <output.jpg>")
            }
            let response = try await request(method: "GET", path: "/api/observe", token: token)
            try response.data.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
            let frameID = response.http.value(forHTTPHeaderField: "X-Frame-ID") ?? "unknown"
            print("Saved frame \(frameID) to \(arguments[1])")
        case "tap":
            guard arguments.count == 3,
                let x = Double(arguments[1]),
                let y = Double(arguments[2])
            else {
                throw CLIError("Usage: \(commandName) tap <x 0...1> <y 0...1>")
            }
            try await act(ControlCommand(type: "tap", x: x, y: y), token: token)
        case "swipe":
            guard (5...6).contains(arguments.count),
                let x = Double(arguments[1]),
                let y = Double(arguments[2]),
                let x2 = Double(arguments[3]),
                let y2 = Double(arguments[4]),
                arguments.count == 5 || Int(arguments[5]) != nil
            else {
                throw CLIError(
                    "Usage: \(commandName) swipe <x> <y> <x2> <y2> [duration-ms]"
                )
            }
            try await act(
                ControlCommand(
                    type: "swipe",
                    x: x,
                    y: y,
                    x2: x2,
                    y2: y2,
                    durationMs: arguments.count == 6 ? Int(arguments[5]) : nil
                ),
                token: token
            )
        case "type":
            let text = arguments.dropFirst().joined(separator: " ")
            guard !text.isEmpty else {
                throw CLIError("Usage: \(commandName) type <text>")
            }
            try await act(ControlCommand(type: "type", text: text), token: token)
        case "home", "apps", "spotlight":
            let shortcut = command == "apps" ? "appSwitcher" : command
            try await act(ControlCommand(type: "shortcut", name: shortcut), token: token)
        default:
            throw CLIError("Unknown command: \(command)\n\n\(usage)")
        }
    }

    private static func act(_ command: ControlCommand, token: String) async throws {
        let body = try JSONEncoder().encode(command)
        try await printResponse(method: "POST", path: "/api/act", token: token, body: body)
    }

    private static func printDoctor(status: CLIStatus) throws {
        let tokenURL = try tokenFileURL()
        let attributes = try FileManager.default.attributesOfItem(atPath: tokenURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        let mirroringInstalled =
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.ScreenContinuity"
            ) != nil
        let installedApp = FileManager.default.fileExists(
            atPath: "/Applications/Phone Use.app"
        )
        let report = DoctorReport(
            ok: mirroringInstalled
                && installedApp
                && permissions == 0o600
                && status.screenCaptureAuthorized
                && status.accessibilityAuthorized,
            version: currentVersion(),
            brokerVersion: status.version ?? "unknown",
            protocolVersion: status.protocolVersion ?? 0,
            transport: status.transport,
            phase: status.phase,
            installedApp: installedApp,
            iPhoneMirroringInstalled: mirroringInstalled,
            screenCaptureAuthorized: status.screenCaptureAuthorized,
            accessibilityAuthorized: status.accessibilityAuthorized,
            tokenPermissions: String(format: "%03o", permissions ?? 0)
        )
        let data = try JSONEncoder.pretty.encode(report)
        print(String(decoding: data, as: UTF8.self))
    }

    private static func printResponse(
        method: String,
        path: String,
        token: String,
        body: Data? = nil
    ) async throws {
        let response = try await request(method: method, path: path, token: token, body: body)
        if let object = try? JSONSerialization.jsonObject(with: response.data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        {
            print(String(decoding: pretty, as: UTF8.self))
        } else {
            print(String(decoding: response.data, as: UTF8.self))
        }
    }

    private static func request(
        method: String,
        path: String,
        token: String,
        body: Data? = nil
    ) async throws -> HTTPResult {
        do {
            return try await send(method: method, path: path, token: token, body: body)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            guard try await launchBroker() else {
                throw CLIError(
                    "\(productName) is not running and no packaged app could be found"
                )
            }
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                if let result = try? await send(
                    method: method,
                    path: path,
                    token: token,
                    body: body
                ) {
                    return result
                }
            }
            throw CLIError("\(productName) did not start its local API")
        }
    }

    private static func send(
        method: String,
        path: String,
        token: String,
        body: Data?
    ) async throws -> HTTPResult {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = 180
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIError("\(productName) returned a non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail =
                (try? JSONDecoder().decode(APIError.self, from: data).error)
                ?? String(decoding: data, as: UTF8.self)
            throw CLIError("HTTP \(http.statusCode): \(detail)")
        }
        return HTTPResult(data: data, http: http)
    }

    private static func launchBroker() async throws -> Bool {
        for appURL in candidateAppURLs() where FileManager.default.fileExists(atPath: appURL.path) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            try await NSWorkspace.shared.openApplication(
                at: appURL,
                configuration: configuration
            )
            return true
        }
        return false
    }

    private static func candidateAppURLs() -> [URL] {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let containingApp = PhoneUseProtocolMetadata.enclosingApplication(for: executable)
        let registeredApp = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: PhoneUseProtocolMetadata.appBundleIdentifier
        )
        let workingDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let candidates = [
            containingApp,
            URL(fileURLWithPath: "/Applications/Phone Use.app", isDirectory: true),
            registeredApp,
            workingDirectory.appendingPathComponent("dist/Phone Use.app", isDirectory: true)
        ]
        var seen: Set<String> = []
        return candidates.compactMap { $0?.standardizedFileURL }.filter {
            seen.insert($0.path).inserted
        }
    }

    private static func currentVersion() -> String {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        guard let application = PhoneUseProtocolMetadata.enclosingApplication(for: executable) else {
            return "development"
        }
        return PhoneUseProtocolMetadata.shortVersion(of: application) ?? "development"
    }

    private static func compatibleBrokerStatus(token: String) async throws -> CLIStatus {
        let response = try await request(method: "GET", path: "/api/status", token: token)
        let status = try JSONDecoder().decode(CLIStatus.self, from: response.data)
        guard status.product == PhoneUseProtocolMetadata.productIdentifier else {
            throw CLIError(
                "The running broker is not \(productName). Quit stale copies and reopen \(productName)."
            )
        }
        guard let protocolVersion = status.protocolVersion else {
            throw CLIError(
                "The running \(productName) broker is too old. Quit it and open the packaged app."
            )
        }
        guard protocolVersion == PhoneUseProtocolMetadata.currentVersion else {
            throw CLIError(
                "Protocol mismatch: CLI expects \(PhoneUseProtocolMetadata.currentVersion), "
                    + "broker provides \(protocolVersion). Quit stale copies and reopen \(productName)."
            )
        }

        guard let brokerVersion = status.version else {
            throw CLIError(
                "The running \(productName) broker does not report a product version. "
                    + "Quit stale copies and reopen \(productName)."
            )
        }

        let cliVersion = currentVersion()
        if cliVersion != "development",
            brokerVersion != "development",
            brokerVersion != cliVersion
        {
            throw CLIError(
                "Version mismatch: CLI is \(cliVersion), broker is \(brokerVersion). "
                    + "Quit stale copies and reopen \(productName)."
            )
        }
        return status
    }

    private static func loadToken() throws -> String {
        for tokenURL in try tokenFileURLs() {
            if let token = try? String(contentsOf: tokenURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !token.isEmpty
            {
                return token
            }
        }
        throw CLIError("No local token exists. Launch \(productName) once first.")
    }

    private static func tokenFileURL() throws -> URL {
        let candidates = try tokenFileURLs()
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
            ?? candidates[0]
    }

    private static func tokenFileURLs() throws -> [URL] {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return [
            PhoneUseProtocolMetadata.applicationSupportDirectoryName,
            PhoneUseProtocolMetadata.legacyApplicationSupportDirectoryName
        ].map {
            applicationSupportURL
                .appendingPathComponent($0, isDirectory: true)
                .appendingPathComponent("token", isDirectory: false)
        }
    }

    private static func loadTokenStartingBrokerIfNeeded() async throws -> String {
        if let token = try? loadToken() {
            return token
        }
        guard try await launchBroker() else {
            throw CLIError(
                "No local token exists and no packaged \(productName) app could be found"
            )
        }
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if let token = try? loadToken() {
                return token
            }
        }
        throw CLIError("\(productName) did not create its local token")
    }

    private static let usage = """
        Usage: \(commandName) <command>

          dashboard
          doctor
          status
          open | close
          observe <output.jpg>
          tap <x 0...1> <y 0...1>
          swipe <x> <y> <x2> <y2> [duration-ms]
          type <text>
          home | apps | spotlight
          version
        """
}

private struct HTTPResult {
    let data: Data
    let http: HTTPURLResponse
}

private struct APIError: Decodable {
    let error: String
}

private struct DashboardBootstrapResponse: Decodable {
    let path: String
}

private struct CLIStatus: Decodable {
    let product: String?
    let version: String?
    let protocolVersion: Int?
    let transport: String
    let phase: String
    let screenCaptureAuthorized: Bool
    let accessibilityAuthorized: Bool
}

private struct DoctorReport: Encodable {
    let ok: Bool
    let version: String
    let brokerVersion: String
    let protocolVersion: Int
    let transport: String
    let phase: String
    let installedApp: Bool
    let iPhoneMirroringInstalled: Bool
    let screenCaptureAuthorized: Bool
    let accessibilityAuthorized: Bool
    let tokenPermissions: String
}

extension JSONEncoder {
    fileprivate static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

private struct CLIError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
