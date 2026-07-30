import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct WebDriverAgentScreen: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let scale: Double

    public init(width: Double, height: Double, scale: Double) {
        self.width = width
        self.height = height
        self.scale = scale
    }
}

public actor WebDriverAgentClient {
    public let baseURL: URL

    private let urlSession: URLSession
    private var sessionID: String?
    private var cachedScreen: WebDriverAgentScreen?

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:8100")!,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    public func isReady() async -> Bool {
        do {
            let value = try await request(method: "GET", path: "/status")
            return (value as? [String: Any])?["ready"] as? Bool == true
        } catch {
            return false
        }
    }

    @discardableResult
    public func openSession() async throws -> WebDriverAgentScreen {
        if sessionID == nil {
            let value = try await request(
                method: "POST",
                path: "/session",
                body: [
                    "capabilities": [
                        "alwaysMatch": [
                            "shouldWaitForQuiescence": false,
                            "waitForIdleTimeout": 0
                        ]
                    ]
                ]
            )
            guard let payload = value as? [String: Any],
                  let newSessionID = payload["sessionId"] as? String,
                  !newSessionID.isEmpty
            else {
                throw WebDriverAgentError("WebDriverAgent did not return a session identifier")
            }
            sessionID = newSessionID

            _ = try await request(
                method: "POST",
                path: sessionPath("/appium/settings"),
                body: ["settings": ["screenshotQuality": 2]]
            )
        }
        return try await screen()
    }

    public func closeSession() async throws {
        guard let sessionID else { return }
        defer {
            self.sessionID = nil
            cachedScreen = nil
        }
        _ = try await request(method: "DELETE", path: "/session/\(sessionID)")
    }

    public func screen() async throws -> WebDriverAgentScreen {
        if let cachedScreen {
            return cachedScreen
        }
        let value = try await request(method: "GET", path: "/wda/screen")
        guard let payload = value as? [String: Any],
              let size = payload["screenSize"] as? [String: Any],
              let width = Self.number(size["width"]),
              let height = Self.number(size["height"]),
              let scale = Self.number(payload["scale"]),
              width > 0,
              height > 0,
              scale > 0
        else {
            throw WebDriverAgentError("WebDriverAgent returned invalid screen dimensions")
        }
        let screen = WebDriverAgentScreen(width: width, height: height, scale: scale)
        cachedScreen = screen
        return screen
    }

    public func screenshotJPEG() async throws -> Data {
        let value = try await request(method: "GET", path: "/screenshot")
        guard let encoded = value as? String,
              let image = Data(base64Encoded: encoded)
        else {
            throw WebDriverAgentError("WebDriverAgent returned an invalid screenshot")
        }
        return try Self.convertToJPEG(image)
    }

    public func sourceJSON() async throws -> Data {
        let value = try await request(
            method: "GET",
            path: "/source",
            query: [URLQueryItem(name: "format", value: "json")]
        )
        guard JSONSerialization.isValidJSONObject(value) else {
            throw WebDriverAgentError("WebDriverAgent returned an invalid accessibility tree")
        }
        return try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    public func perform(_ rawCommand: ControlCommand) async throws {
        let command = try rawCommand.validated()
        switch command.type {
        case "tap":
            try await tap(x: command.x!, y: command.y!)
        case "swipe":
            try await drag(
                fromX: command.x!,
                fromY: command.y!,
                toX: command.x2!,
                toY: command.y2!,
                duration: Double(command.durationMs ?? 350) / 1_000
            )
        case "type":
            _ = try await request(
                method: "POST",
                path: sessionPath("/wda/keys"),
                body: ["value": [command.text!]]
            )
        case "shortcut":
            try await shortcut(command.name!)
        case "pointer":
            throw WebDriverAgentError(
                "Pointer phases must be combined into a tap or drag before sending to WebDriverAgent"
            )
        default:
            throw WebDriverAgentError("Unsupported WebDriverAgent command")
        }
    }

    public func tap(x: Double, y: Double) async throws {
        let point = try await absolutePoint(x: x, y: y)
        _ = try await request(
            method: "POST",
            path: sessionPath("/wda/tap"),
            body: ["x": point.x, "y": point.y]
        )
    }

    public func drag(
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double,
        duration: Double
    ) async throws {
        let start = try await absolutePoint(x: fromX, y: fromY)
        let end = try await absolutePoint(x: toX, y: toY)
        _ = try await request(
            method: "POST",
            path: sessionPath("/wda/dragfromtoforduration"),
            body: [
                "fromX": start.x,
                "fromY": start.y,
                "toX": end.x,
                "toY": end.y,
                "duration": min(max(duration, 0.1), 3)
            ]
        )
    }

    private func shortcut(_ name: String) async throws {
        switch name {
        case "home":
            _ = try await request(method: "POST", path: "/wda/homescreen", body: [:])
        case "appSwitcher":
            try await drag(
                fromX: 0.5,
                fromY: 0.99,
                toX: 0.5,
                toY: 0.52,
                duration: 0.7
            )
        case "spotlight":
            _ = try await request(method: "POST", path: "/wda/homescreen", body: [:])
            try await drag(
                fromX: 0.5,
                fromY: 0.22,
                toX: 0.5,
                toY: 0.68,
                duration: 0.35
            )
        default:
            throw WebDriverAgentError("Unsupported WebDriverAgent shortcut")
        }
    }

    private func absolutePoint(x: Double, y: Double) async throws -> CGPoint {
        let screen = try await screen()
        return CGPoint(x: screen.width * x, y: screen.height * y)
    }

    private func sessionPath(_ suffix: String) throws -> String {
        guard let sessionID else {
            throw WebDriverAgentError("No WebDriverAgent session is active")
        }
        return "/session/\(sessionID)\(suffix)"
    }

    private func request(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) async throws -> Any {
        var url = baseURL
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        if !query.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = query
            guard let queryURL = components?.url else {
                throw WebDriverAgentError("Could not construct a WebDriverAgent URL")
            }
            url = queryURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw WebDriverAgentError(
                "Could not reach WebDriverAgent at \(baseURL.absoluteString): \(error.localizedDescription)"
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw WebDriverAgentError("WebDriverAgent returned a non-HTTP response")
        }
        let object = try? JSONSerialization.jsonObject(with: data)
        let envelope = object as? [String: Any]
        let value = envelope?["value"] ?? NSNull()

        if !(200 ..< 300).contains(http.statusCode) {
            let detail = (value as? [String: Any])?["message"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "unknown error"
            throw WebDriverAgentError("WebDriverAgent HTTP \(http.statusCode): \(detail)")
        }
        if let failure = value as? [String: Any],
           failure["error"] is String {
            let detail = failure["message"] as? String ?? "unknown error"
            throw WebDriverAgentError("WebDriverAgent command failed: \(detail)")
        }
        return value
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return value as? Double
    }

    private static func convertToJPEG(_ data: Data) throws -> Data {
        if data.starts(with: [0xFF, 0xD8]) {
            return data
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw WebDriverAgentError("WebDriverAgent screenshot is not a supported image")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw WebDriverAgentError("Could not create a JPEG screenshot")
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw WebDriverAgentError("Could not encode the WebDriverAgent screenshot")
        }
        return output as Data
    }
}

public struct WebDriverAgentError: LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
