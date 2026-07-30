import AppKit
import Foundation
import MirrorCore

@main
struct MirrorRelayCLI {
    private static let baseURL: URL = {
        let port = UInt16(ProcessInfo.processInfo.environment["MIRROR_RELAY_PORT"] ?? "")
            ?? 8_747
        return URL(string: "http://127.0.0.1:\(port)")!
    }()

    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("mirror-relayctl: \(error.localizedDescription)\n".utf8))
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

        let token = try await loadTokenStartingBrokerIfNeeded()
        switch command {
        case "status":
            try await printResponse(method: "GET", path: "/api/status", token: token)
        case "open":
            try await printResponse(method: "POST", path: "/api/session/open", token: token)
        case "close":
            try await printResponse(method: "POST", path: "/api/session/close", token: token)
        case "observe":
            guard arguments.count == 2 else {
                throw CLIError("Usage: mirror-relayctl observe <output.jpg>")
            }
            let response = try await request(method: "GET", path: "/api/observe", token: token)
            try response.data.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
            let frameID = response.http.value(forHTTPHeaderField: "X-Frame-ID") ?? "unknown"
            print("Saved frame \(frameID) to \(arguments[1])")
        case "source":
            guard arguments.count <= 2 else {
                throw CLIError("Usage: mirror-relayctl source [output.json]")
            }
            let response = try await request(method: "GET", path: "/api/source", token: token)
            if arguments.count == 2 {
                try response.data.write(
                    to: URL(fileURLWithPath: arguments[1]),
                    options: .atomic
                )
                print("Saved accessibility source to \(arguments[1])")
            } else if let object = try? JSONSerialization.jsonObject(with: response.data),
                      let pretty = try? JSONSerialization.data(
                        withJSONObject: object,
                        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                      ) {
                print(String(decoding: pretty, as: UTF8.self))
            } else {
                print(String(decoding: response.data, as: UTF8.self))
            }
        case "tap":
            guard arguments.count == 3,
                  let x = Double(arguments[1]),
                  let y = Double(arguments[2])
            else {
                throw CLIError("Usage: mirror-relayctl tap <x 0...1> <y 0...1>")
            }
            try await act(ControlCommand(type: "tap", x: x, y: y), token: token)
        case "swipe":
            guard (5 ... 6).contains(arguments.count),
                  let x = Double(arguments[1]),
                  let y = Double(arguments[2]),
                  let x2 = Double(arguments[3]),
                  let y2 = Double(arguments[4]),
                  arguments.count == 5 || Int(arguments[5]) != nil
            else {
                throw CLIError(
                    "Usage: mirror-relayctl swipe <x> <y> <x2> <y2> [duration-ms]"
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
                throw CLIError("Usage: mirror-relayctl type <text>")
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
           ) {
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
                    "Mirror Relay is not running and no packaged app could be found"
                )
            }
            for _ in 0 ..< 30 {
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
            throw CLIError("Mirror Relay did not start its local API")
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
            throw CLIError("Mirror Relay returned a non-HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(APIError.self, from: data).error)
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
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let containingApp = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workingDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        return [
            URL(fileURLWithPath: "/Applications/Mirror Relay.app", isDirectory: true),
            containingApp,
            workingDirectory.appendingPathComponent("dist/Mirror Relay.app", isDirectory: true)
        ]
    }

    private static func loadToken() throws -> String {
        let tokenURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        .appendingPathComponent("Mirror Relay", isDirectory: true)
        .appendingPathComponent("token", isDirectory: false)
        guard let token = try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            throw CLIError("No local token exists. Launch Mirror Relay once first.")
        }
        return token
    }

    private static func loadTokenStartingBrokerIfNeeded() async throws -> String {
        if let token = try? loadToken() {
            return token
        }
        guard try await launchBroker() else {
            throw CLIError("No local token exists and no packaged Mirror Relay app could be found")
        }
        for _ in 0 ..< 30 {
            try? await Task.sleep(for: .milliseconds(100))
            if let token = try? loadToken() {
                return token
            }
        }
        throw CLIError("Mirror Relay did not create its local token")
    }

    private static let usage = """
    Usage: mirror-relayctl <command>

      status
      open | close
      observe <output.jpg>
      source [output.json]
      tap <x 0...1> <y 0...1>
      swipe <x> <y> <x2> <y2> [duration-ms]
      type <text>
      home | apps | spotlight
    """
}

private struct HTTPResult {
    let data: Data
    let http: HTTPURLResponse
}

private struct APIError: Decodable {
    let error: String
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
