import AppKit
import Foundation
import PhoneUseProtocol

@main
enum PhoneUseCLI {
    private static let productName = PhoneUseProtocolMetadata.displayName
    private static let commandName = PhoneUseProtocolMetadata.commandName
    private static let baseURL = URL(string: "http://127.0.0.1:8747")!

    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch let error as CLIExitError {
            FileHandle.standardError.write(Data("\(error.message)\n".utf8))
            exit(error.exitCode)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            throw CLIError(usage)
        }
        switch command {
        case "version", "--version", "-v":
            print("\(productName) \(currentVersion())")
        case "dashboard":
            try await openDashboard()
        case "doctor":
            try await doctor()
        case "status":
            let token = try await loadTokenStartingBrokerIfNeeded()
            let response = try await request(method: "GET", path: "/api/status", token: token)
            _ = try decodeCompatibleStatus(response.data)
            printJSON(response.data)
        case "connect":
            try await runStatusMutation(path: "/api/device/connect")
        case "disconnect":
            try await runStatusMutation(path: "/api/device/disconnect")
        case "observe":
            guard arguments.count == 2 else { throw CLIError(usage) }
            try await observe(outputPath: arguments[1])
        case "tap":
            let parsed = try actionArguments(Array(arguments.dropFirst()))
            guard parsed.operands.count == 2,
                let x = Double(parsed.operands[0]),
                let y = Double(parsed.operands[1])
            else { throw CLIError(usage) }
            try await perform(
                ControlCommand(
                    type: "tap",
                    x: x,
                    y: y,
                    expectedFrameToken: parsed.frameToken
                )
            )
        case "swipe":
            let parsed = try actionArguments(Array(arguments.dropFirst()))
            guard (4...5).contains(parsed.operands.count),
                let x = Double(parsed.operands[0]),
                let y = Double(parsed.operands[1]),
                let x2 = Double(parsed.operands[2]),
                let y2 = Double(parsed.operands[3]),
                parsed.operands.count == 4 || Int(parsed.operands[4]) != nil
            else { throw CLIError(usage) }
            try await perform(
                ControlCommand(
                    type: "swipe",
                    x: x,
                    y: y,
                    x2: x2,
                    y2: y2,
                    durationMs: parsed.operands.count == 5 ? Int(parsed.operands[4]) : nil,
                    expectedFrameToken: parsed.frameToken
                )
            )
        case "type":
            let parsed = try actionArguments(Array(arguments.dropFirst()))
            guard !parsed.operands.isEmpty else { throw CLIError(usage) }
            try await perform(
                ControlCommand(
                    type: "type",
                    text: parsed.operands.joined(separator: " "),
                    expectedFrameToken: parsed.frameToken
                )
            )
        case "home", "apps", "spotlight":
            let parsed = try actionArguments(Array(arguments.dropFirst()))
            guard parsed.operands.isEmpty else { throw CLIError(usage) }
            let shortcut = command == "apps" ? "appSwitcher" : command
            try await perform(
                ControlCommand(
                    type: "shortcut",
                    name: shortcut,
                    expectedFrameToken: parsed.frameToken
                )
            )
        default:
            throw CLIError(usage)
        }
    }

    private static func openDashboard() async throws {
        let token = try await loadTokenStartingBrokerIfNeeded()
        _ = try await compatibleStatus(token: token)
        let response = try await request(
            method: "POST",
            path: "/api/dashboard/bootstrap",
            token: token
        )
        let bootstrap = try JSONDecoder().decode(DashboardBootstrapResponse.self, from: response.data)
        guard let url = URL(string: bootstrap.path, relativeTo: baseURL) else {
            throw CLIError("The broker returned an invalid dashboard URL")
        }
        NSWorkspace.shared.open(url)
    }

    private static func doctor() async throws {
        let token = try await loadTokenStartingBrokerIfNeeded()
        let status = try await compatibleStatus(token: token)
        let tokenURL = try tokenFileURL()
        let mode =
            try FileManager.default.attributesOfItem(atPath: tokenURL.path)[
                .posixPermissions
            ] as? NSNumber
        let report = DoctorReport(
            ok: status.proof == .validated,
            version: currentVersion(),
            brokerVersion: status.version,
            protocolVersion: status.protocolVersion,
            transport: status.transport,
            phase: status.phase,
            proof: status.proof,
            requirements: status.requirements,
            installedApp: candidateAppURLs().contains {
                FileManager.default.fileExists(atPath: $0.path)
            },
            controlCapabilities: status.controlCapabilities,
            macFocusPolicy: status.macFocusPolicy,
            internetRelayAvailable: status.internetRelayAvailable,
            tokenPermissions: String(format: "%03o", mode?.intValue ?? 0)
        )
        print(String(decoding: try JSONEncoder.pretty.encode(report), as: UTF8.self))
        if !report.ok {
            throw CLIExitError(
                message: "Device Hub control has not passed physical iOS 27 validation.",
                exitCode: 2
            )
        }
    }

    private static func runStatusMutation(path: String) async throws {
        let token = try await loadTokenStartingBrokerIfNeeded()
        _ = try await compatibleStatus(token: token)
        let response = try await request(method: "POST", path: path, token: token)
        printJSON(response.data)
    }

    private static func observe(outputPath: String) async throws {
        let token = try await loadTokenStartingBrokerIfNeeded()
        _ = try await compatibleStatus(token: token)
        let response = try await request(method: "GET", path: "/api/observe", token: token)
        let outputURL = URL(fileURLWithPath: outputPath)
        try response.data.write(to: outputURL, options: .atomic)
        let frameID = response.http.value(forHTTPHeaderField: "X-Frame-ID") ?? "unknown"
        let frameToken = response.http.value(forHTTPHeaderField: "X-Frame-Token") ?? "missing"
        print("Saved frame \(frameID) to \(outputURL.path)")
        print("Frame token: \(frameToken)")
    }

    private static func perform(_ command: ControlCommand) async throws {
        _ = try command.validated()
        let token = try await loadTokenStartingBrokerIfNeeded()
        _ = try await compatibleStatus(token: token)
        let response = try await request(
            method: "POST",
            path: "/api/actions",
            token: token,
            body: try JSONEncoder().encode(command)
        )
        let receipt = try JSONDecoder().decode(DeviceActionReceipt.self, from: response.data)
        guard receipt.delivered, receipt.verified, !receipt.macFocusChanged else {
            throw CLIError("The device did not return verified, focus-safe action evidence")
        }
        printJSON(response.data)
    }

    private static func actionArguments(_ arguments: [String]) throws -> ActionArguments {
        var operands: [String] = []
        var frameToken: String?
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--frame-token" {
                guard frameToken == nil, index + 1 < arguments.count else {
                    throw CLIError(usage)
                }
                frameToken = arguments[index + 1]
                index += 2
            } else {
                operands.append(arguments[index])
                index += 1
            }
        }
        return ActionArguments(frameToken: frameToken, operands: operands)
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
                throw CLIError("\(productName) is not running and no packaged app could be found")
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
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw CLIError("Invalid API path")
        }
        var request = URLRequest(url: url)
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

    private static func compatibleStatus(token: String) async throws -> PhoneUseStatus {
        let response = try await request(method: "GET", path: "/api/status", token: token)
        return try decodeCompatibleStatus(response.data)
    }

    private static func decodeCompatibleStatus(_ data: Data) throws -> PhoneUseStatus {
        let status = try JSONDecoder().decode(PhoneUseStatus.self, from: data)
        guard status.product == PhoneUseProtocolMetadata.productIdentifier else {
            throw CLIError("The running broker is not \(productName)")
        }
        guard status.protocolVersion == PhoneUseProtocolMetadata.currentVersion else {
            throw CLIError(
                "Protocol mismatch: CLI expects \(PhoneUseProtocolMetadata.currentVersion), "
                    + "broker provides \(status.protocolVersion)"
            )
        }
        let cliVersion = currentVersion()
        if cliVersion != "development",
            status.version != "development",
            status.version != cliVersion
        {
            throw CLIError(
                "Version mismatch: CLI is \(cliVersion), broker is \(status.version)"
            )
        }
        return status
    }

    private static func launchBroker() async throws -> Bool {
        for appURL in candidateAppURLs() where FileManager.default.fileExists(atPath: appURL.path) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            return true
        }
        return false
    }

    private static func candidateAppURLs() -> [URL] {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let workingDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let candidates = [
            PhoneUseProtocolMetadata.enclosingApplication(for: executable),
            URL(fileURLWithPath: "/Applications/Phone Use.app", isDirectory: true),
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: PhoneUseProtocolMetadata.appBundleIdentifier
            ),
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

    private static func tokenFileURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return PhoneUseProtocolMetadata.tokenFile(in: applicationSupportURL)
    }

    private static func loadToken() throws -> String {
        let token = try String(contentsOf: tokenFileURL(), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw CLIError("The local API token is empty") }
        return token
    }

    private static func loadTokenStartingBrokerIfNeeded() async throws -> String {
        if let token = try? loadToken() { return token }
        guard try await launchBroker() else {
            throw CLIError("No local token exists and no packaged \(productName) app was found")
        }
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if let token = try? loadToken() { return token }
        }
        throw CLIError("\(productName) did not create its local token")
    }

    private static func printJSON(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        else {
            print(String(decoding: data, as: UTF8.self))
            return
        }
        print(String(decoding: pretty, as: UTF8.self))
    }

    private static let usage = """
        Usage: \(commandName) <command>

          dashboard
          doctor
          status
          connect | disconnect
          observe <output.jpg>
          tap --frame-token <token> <x 0...1> <y 0...1>
          swipe --frame-token <token> <x> <y> <x2> <y2> [duration-ms]
          type --frame-token <token> <text>
          home | apps | spotlight --frame-token <token>
          version
        """
}

private struct HTTPResult {
    let data: Data
    let http: HTTPURLResponse
}

private struct ActionArguments {
    let frameToken: String?
    let operands: [String]
}

private struct APIError: Decodable { let error: String }
private struct DashboardBootstrapResponse: Decodable { let path: String }

private struct DoctorReport: Encodable {
    let ok: Bool
    let version: String
    let brokerVersion: String
    let protocolVersion: Int
    let transport: String
    let phase: DeviceHubPhase
    let proof: DeviceHubProofState
    let requirements: DeviceHubRequirements
    let installedApp: Bool
    let controlCapabilities: ControlCapabilities
    let macFocusPolicy: String
    let internetRelayAvailable: Bool
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
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private struct CLIExitError: LocalizedError {
    let message: String
    let exitCode: Int32
    var errorDescription: String? { message }
}
