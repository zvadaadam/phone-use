import Foundation
import XCTest
@testable import MirrorCore

final class WebDriverAgentClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    func testOpensSessionAndMapsNormalizedTapToScreenPoints() async throws {
        var requests: [URLRequest] = []
        MockURLProtocol.handler = { request in
            requests.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/session"):
                return Self.json(["value": ["sessionId": "session-1"]])
            case ("POST", "/session/session-1/appium/settings"):
                return Self.json(["value": NSNull()])
            case ("GET", "/wda/screen"):
                return Self.json([
                    "value": [
                        "screenSize": ["width": 390, "height": 844],
                        "scale": 3
                    ]
                ])
            case ("POST", "/session/session-1/wda/tap"):
                return Self.json(["value": NSNull()])
            default:
                return Self.json(["value": ["message": "unexpected"]], status: 500)
            }
        }

        let client = WebDriverAgentClient(
            baseURL: URL(string: "http://127.0.0.1:8100")!,
            urlSession: session
        )
        let screen = try await client.openSession()
        try await client.perform(ControlCommand(type: "tap", x: 0.5, y: 0.25))

        XCTAssertEqual(screen, WebDriverAgentScreen(width: 390, height: 844, scale: 3))
        let tap = try XCTUnwrap(requests.last)
        let body = try XCTUnwrap(tap.httpBody)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Double]
        )
        XCTAssertEqual(payload["x"], 195)
        XCTAssertEqual(payload["y"], 211)
    }

    func testDecodesScreenshotAndAccessibilitySource() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/screenshot":
                return Self.json(["value": jpeg.base64EncodedString()])
            case "/source":
                XCTAssertEqual(request.url?.query, "format=json")
                return Self.json([
                    "value": [
                        "type": "XCUIElementTypeApplication",
                        "children": []
                    ]
                ])
            default:
                return Self.json(["value": ["message": "unexpected"]], status: 500)
            }
        }

        let client = WebDriverAgentClient(
            baseURL: URL(string: "http://127.0.0.1:8100")!,
            urlSession: session
        )
        let screenshot = try await client.screenshotJPEG()
        XCTAssertEqual(screenshot, jpeg)
        let source = try await client.sourceJSON()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: source) as? [String: Any]
        )
        XCTAssertEqual(object["type"] as? String, "XCUIElementTypeApplication")
    }

    func testReportsWebDriverAgentErrorPayload() async {
        MockURLProtocol.handler = { _ in
            Self.json(
                ["value": ["error": "invalid session id", "message": "Session expired"]],
                status: 404
            )
        }
        let client = WebDriverAgentClient(
            baseURL: URL(string: "http://127.0.0.1:8100")!,
            urlSession: session
        )

        do {
            _ = try await client.screenshotJPEG()
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Session expired"))
        }
    }

    private static func json(
        _ object: Any,
        status: Int = 200
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8100")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, try! JSONSerialization.data(withJSONObject: object))
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            var capturedRequest = request
            if capturedRequest.httpBody == nil,
               let stream = capturedRequest.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var body = Data()
                var buffer = [UInt8](repeating: 0, count: 4_096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    body.append(buffer, count: count)
                }
                capturedRequest.httpBody = body
            }
            let (response, data) = try Self.handler!(capturedRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
