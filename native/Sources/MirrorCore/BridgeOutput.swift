import Foundation

public struct BridgeStatus: Codable, Sendable {
    public let phase: String
    public let message: String
    public let width: Int?
    public let height: Int?
    public let windowTitle: String?
    public let screenCaptureAuthorized: Bool?
    public let accessibilityAuthorized: Bool?

    public init(
        phase: String,
        message: String,
        width: Int? = nil,
        height: Int? = nil,
        windowTitle: String? = nil,
        screenCaptureAuthorized: Bool? = nil,
        accessibilityAuthorized: Bool? = nil
    ) {
        self.phase = phase
        self.message = message
        self.width = width
        self.height = height
        self.windowTitle = windowTitle
        self.screenCaptureAuthorized = screenCaptureAuthorized
        self.accessibilityAuthorized = accessibilityAuthorized
    }
}

public protocol BridgeOutput: AnyObject {
    func frame(_ data: Data)
    func clearFrame()
    func status(_ status: BridgeStatus)
    func log(_ message: String)
}

extension BridgeOutput {
    public func status(
        phase: String,
        message: String,
        width: Int? = nil,
        height: Int? = nil,
        windowTitle: String? = nil,
        screenCaptureAuthorized: Bool? = nil,
        accessibilityAuthorized: Bool? = nil
    ) {
        status(
            BridgeStatus(
                phase: phase,
                message: message,
                width: width,
                height: height,
                windowTitle: windowTitle,
                screenCaptureAuthorized: screenCaptureAuthorized,
                accessibilityAuthorized: accessibilityAuthorized
            )
        )
    }
}
