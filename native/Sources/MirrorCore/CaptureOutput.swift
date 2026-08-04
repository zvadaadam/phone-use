import Foundation

public enum CaptureMode: String, Codable, Sendable {
    case unavailable
    case screenCaptureKit
    case screenshotFallback
}

public enum RelayPhase: String, Codable, Sendable {
    case starting
    case waiting
    case permission
    case reconnecting
    case streaming
}

public struct CaptureStatus: Equatable, Sendable {
    public let phase: RelayPhase
    public let message: String
    public let width: Int?
    public let height: Int?
    public let windowTitle: String?

    public init(
        phase: RelayPhase,
        message: String,
        width: Int? = nil,
        height: Int? = nil,
        windowTitle: String? = nil
    ) {
        self.phase = phase
        self.message = message
        self.width = width
        self.height = height
        self.windowTitle = windowTitle
    }
}

public protocol RelayLogger: AnyObject {
    func log(_ message: String)
}

public protocol CaptureOutput: RelayLogger {
    func frame(_ data: Data)
    func clearFrame()
    func captureMode(_ mode: CaptureMode)
    func status(_ status: CaptureStatus)
}

extension CaptureOutput {
    public func status(
        phase: RelayPhase,
        message: String,
        width: Int? = nil,
        height: Int? = nil,
        windowTitle: String? = nil
    ) {
        status(
            CaptureStatus(
                phase: phase,
                message: message,
                width: width,
                height: height,
                windowTitle: windowTitle
            )
        )
    }
}
