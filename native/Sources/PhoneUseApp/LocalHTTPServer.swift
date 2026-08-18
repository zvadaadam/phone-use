import Foundation
import Network
import PhoneUseProtocol

final class LocalHTTPServer: @unchecked Sendable {
    static let port: UInt16 = {
        guard let raw = ProcessInfo.processInfo.environment["PHONE_USE_PORT"],
            let value = UInt16(raw), value > 0
        else { return 8_747 }
        return value
    }()

    private let coordinator: BridgeCoordinator
    private let state: BrokerState
    private let tokenStore: TokenStore
    private let publicDirectory: URL
    private let queue = DispatchQueue(label: "phone-use.http", qos: .userInitiated)
    private var listener: NWListener?
    private var clients: [UUID: HTTPClient] = [:]

    init(
        coordinator: BridgeCoordinator,
        state: BrokerState,
        tokenStore: TokenStore,
        publicDirectory: URL
    ) {
        self.coordinator = coordinator
        self.state = state
        self.tokenStore = tokenStore
        self.publicDirectory = publicDirectory
    }

    func start() throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: Self.port)!
        )
        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] listenerState in
            switch listenerState {
            case .ready:
                self?.state.log("Agent API listening on 127.0.0.1:\(Self.port)")
            case .failed(let error):
                self?.state.log("Agent API failed: \(error)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            let activeClients = Array(clients.values)
            clients.removeAll()
            for client in activeClients {
                client.cancel()
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        let client = HTTPClient(
            connection: connection,
            requestHandler: { [weak self] request, client in
                self?.handle(request, from: client)
            },
            closeHandler: { [weak self] id in
                self?.clients.removeValue(forKey: id)
            }
        )
        clients[client.id] = client
        client.start(on: queue)
    }

    private func handle(_ request: HTTPRequest, from client: HTTPClient) {
        guard request.headers["host"] == "127.0.0.1:\(Self.port)" else {
            client.sendJSON(status: 403, value: ErrorResponse(error: "Host not allowed"))
            return
        }

        if request.method == "GET", request.path == "/auth/dashboard" {
            exchangeDashboardBootstrap(request, client: client)
            return
        }
        if let origin = request.headers["origin"],
            origin != "http://127.0.0.1:\(Self.port)"
        {
            client.sendJSON(status: 403, value: ErrorResponse(error: "Origin not allowed"))
            return
        }
        guard authorized(request) else {
            client.sendJSON(status: 401, value: ErrorResponse(error: "Unauthorized"))
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/health"):
            let status = state.snapshot()
            client.sendJSON(
                status: 200,
                value: HealthResponse(
                    ok: true,
                    version: status.version,
                    protocolVersion: status.protocolVersion,
                    transport: status.transport,
                    phase: status.phase,
                    proof: status.proof,
                    controlCapabilities: status.controlCapabilities
                )
            )
        case ("POST", "/api/dashboard/bootstrap"):
            issueDashboardBootstrap(to: client)
        case ("GET", "/api/status"):
            client.sendJSON(status: 200, value: state.snapshot())
        case ("GET", "/api/observe"):
            Task { [weak self, weak client] in
                guard let self, let client else { return }
                do {
                    let frame = try await coordinator.observe()
                    client.send(
                        status: 200,
                        headers: [
                            "Content-Type": "image/jpeg",
                            "X-Frame-ID": String(frame.id),
                            "X-Frame-Token": frame.frameToken,
                            "X-Frame-Width": String(frame.width),
                            "X-Frame-Height": String(frame.height),
                            "Cache-Control": "no-store"
                        ],
                        body: frame.jpeg
                    )
                } catch {
                    client.sendJSON(
                        status: 503,
                        value: ErrorResponse(error: error.localizedDescription)
                    )
                }
            }
        case ("POST", "/api/device/connect"):
            Task { [weak self, weak client] in
                guard let self, let client else { return }
                do {
                    try await coordinator.connect()
                    client.sendJSON(status: 200, value: state.snapshot())
                } catch {
                    client.sendJSON(
                        status: 409,
                        value: ErrorResponse(error: error.localizedDescription)
                    )
                }
            }
        case ("POST", "/api/device/disconnect"):
            Task { [weak self, weak client] in
                guard let self, let client else { return }
                await coordinator.disconnect()
                client.sendJSON(status: 200, value: state.snapshot())
            }
        case ("POST", "/api/actions"):
            performAction(request, client: client)
        default:
            if request.method == "GET" || request.method == "HEAD" {
                serveStatic(request, to: client)
            } else {
                client.sendJSON(status: 405, value: ErrorResponse(error: "Method not allowed"))
            }
        }
    }

    private func exchangeDashboardBootstrap(_ request: HTTPRequest, client: HTTPClient) {
        guard let bootstrap = request.query["bootstrap"] else {
            client.sendJSON(
                status: 401,
                value: ErrorResponse(error: "Invalid or expired dashboard link")
            )
            return
        }
        do {
            guard let session = try tokenStore.exchangeDashboardBootstrap(bootstrap) else {
                client.sendJSON(
                    status: 401,
                    value: ErrorResponse(error: "Invalid or expired dashboard link")
                )
                return
            }
            client.redirect(
                to: "/",
                cookie: "PhoneUseSession=\(session); HttpOnly; SameSite=Strict; "
                    + "Path=/; Max-Age=\(Int(TokenStore.dashboardSessionLifetime))"
            )
        } catch {
            client.sendJSON(status: 500, value: ErrorResponse(error: error.localizedDescription))
        }
    }

    private func issueDashboardBootstrap(to client: HTTPClient) {
        do {
            let bootstrap = try tokenStore.issueDashboardBootstrap()
            client.sendJSON(
                status: 200,
                value: DashboardBootstrapResponse(
                    path: "/auth/dashboard?bootstrap=\(bootstrap)"
                )
            )
        } catch {
            client.sendJSON(status: 500, value: ErrorResponse(error: error.localizedDescription))
        }
    }

    private func performAction(_ request: HTTPRequest, client: HTTPClient) {
        do {
            let command = try JSONDecoder().decode(ControlCommand.self, from: request.body)
            let validated = try command.validated()
            Task { [weak self, weak client] in
                guard let self, let client else { return }
                do {
                    client.sendJSON(status: 200, value: try await coordinator.perform(validated))
                } catch {
                    client.sendJSON(
                        status: 409,
                        value: ErrorResponse(error: error.localizedDescription)
                    )
                }
            }
        } catch {
            client.sendJSON(status: 400, value: ErrorResponse(error: error.localizedDescription))
        }
    }

    private func authorized(_ request: HTTPRequest) -> Bool {
        if request.headers["authorization"] == "Bearer \(tokenStore.token)" { return true }
        guard let cookie = request.headers["cookie"],
            let session = cookie.split(separator: ";")
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { $0.hasPrefix("PhoneUseSession=") })?
                .dropFirst("PhoneUseSession=".count)
        else { return false }
        return tokenStore.dashboardSessionIsValid(String(session))
    }

    private func serveStatic(_ request: HTTPRequest, to client: HTTPClient) {
        let requested =
            request.path == "/"
            ? "index.html"
            : String(request.path.drop(while: { $0 == "/" }))
        guard !requested.contains(".."), !requested.contains("\0") else {
            client.sendJSON(status: 400, value: ErrorResponse(error: "Invalid path"))
            return
        }
        let fileURL = publicDirectory.appendingPathComponent(requested)
        guard let data = try? Data(contentsOf: fileURL) else {
            client.sendJSON(status: 404, value: ErrorResponse(error: "Not found"))
            return
        }
        let mime =
            switch fileURL.pathExtension.lowercased() {
            case "html": "text/html; charset=utf-8"
            case "css": "text/css; charset=utf-8"
            case "js": "text/javascript; charset=utf-8"
            case "svg": "image/svg+xml"
            default: "application/octet-stream"
            }
        client.send(
            status: 200,
            headers: [
                "Content-Type": mime,
                "Cache-Control": "no-store",
                "Content-Security-Policy":
                    "default-src 'self'; img-src 'self' blob:; style-src 'self'; "
                    + "script-src 'self'; connect-src 'self'",
                "Referrer-Policy": "no-referrer",
                "X-Content-Type-Options": "nosniff",
                "X-Frame-Options": "DENY"
            ],
            body: request.method == "HEAD" ? Data() : data
        )
    }
}

private final class HTTPClient: @unchecked Sendable {
    let id = UUID()
    private let connection: NWConnection
    private let requestHandler: @Sendable (HTTPRequest, HTTPClient) -> Void
    private let closeHandler: @Sendable (UUID) -> Void
    private let lock = NSLock()
    private var buffer = Data()
    private var handled = false
    private var closed = false

    init(
        connection: NWConnection,
        requestHandler: @escaping @Sendable (HTTPRequest, HTTPClient) -> Void,
        closeHandler: @escaping @Sendable (UUID) -> Void
    ) {
        self.connection = connection
        self.requestHandler = requestHandler
        self.closeHandler = closeHandler
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.finish() }
            if case .cancelled = state { self?.finish() }
        }
        connection.start(queue: queue)
        receive()
    }

    func cancel() {
        connection.cancel()
        finish()
    }

    func sendJSON<T: Encodable>(status: Int, value: T) {
        do {
            send(
                status: status,
                headers: [
                    "Content-Type": "application/json; charset=utf-8",
                    "Cache-Control": "no-store"
                ],
                body: try JSONEncoder().encode(value)
            )
        } catch {
            send(
                status: 500,
                headers: ["Content-Type": "application/json; charset=utf-8"],
                body: Data(#"{"error":"Could not encode response"}"#.utf8)
            )
        }
    }

    func redirect(to location: String, cookie: String) {
        send(
            status: 303,
            headers: [
                "Location": location,
                "Set-Cookie": cookie,
                "Cache-Control": "no-store",
                "Referrer-Policy": "no-referrer"
            ],
            body: Data()
        )
    }

    func send(status: Int, headers: [String: String], body: Data) {
        var allHeaders = headers
        allHeaders["Content-Length"] = String(body.count)
        allHeaders["Connection"] = "close"
        var response = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        for (name, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
            response += "\(name): \(value)\r\n"
        }
        response += "\r\n"
        var packet = Data(response.utf8)
        packet.append(body)
        connection.send(
            content: packet,
            completion: .contentProcessed { [weak self] _ in
                self?.connection.cancel()
                self?.finish()
            })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
            [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { buffer.append(data) }
            if buffer.count > 1_048_576 {
                sendJSON(status: 413, value: ErrorResponse(error: "Request too large"))
            } else if !handled, let request = HTTPRequest.parse(buffer) {
                handled = true
                requestHandler(request, self)
            } else if complete || error != nil {
                finish()
            } else {
                receive()
            }
        }
    }

    private func finish() {
        let shouldClose = lock.withLock {
            guard !closed else { return false }
            closed = true
            return true
        }
        if shouldClose { closeHandler(id) }
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 303: "See Other"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 413: "Content Too Large"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        default: "Response"
        }
    }
}

private struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)),
            let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let delimiter = line.firstIndex(of: ":") else { continue }
            headers[line[..<delimiter].lowercased()] = line[line.index(after: delimiter)...]
                .trimmingCharacters(in: .whitespaces)
        }
        guard let contentLength = Int(headers["content-length"] ?? "0"),
            (0...1_048_576).contains(contentLength),
            data.count >= headerRange.upperBound + contentLength
        else { return nil }
        let body = Data(data[headerRange.upperBound..<headerRange.upperBound + contentLength])
        guard let components = URLComponents(string: parts[1]) else { return nil }
        let query = (components.queryItems ?? []).reduce(into: [String: String]()) {
            values, item in
            if let value = item.value {
                values[item.name] = value
            }
        }
        return HTTPRequest(
            method: parts[0].uppercased(),
            path: components.path.isEmpty ? "/" : components.path,
            query: query,
            headers: headers,
            body: body
        )
    }
}

private struct ErrorResponse: Codable { let error: String }

private struct HealthResponse: Codable {
    let ok: Bool
    let version: String
    let protocolVersion: Int
    let transport: String
    let phase: DeviceHubPhase
    let proof: DeviceHubProofState
    let controlCapabilities: ControlCapabilities
}

private struct DashboardBootstrapResponse: Codable { let path: String }
