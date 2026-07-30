import Foundation

public struct ControlCommand: Codable, Sendable {
    public let type: String
    public let phase: String?
    public let x: Double?
    public let y: Double?
    public let x2: Double?
    public let y2: Double?
    public let durationMs: Int?
    public let text: String?
    public let name: String?

    public init(
        type: String,
        phase: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        x2: Double? = nil,
        y2: Double? = nil,
        durationMs: Int? = nil,
        text: String? = nil,
        name: String? = nil
    ) {
        self.type = type
        self.phase = phase
        self.x = x
        self.y = y
        self.x2 = x2
        self.y2 = y2
        self.durationMs = durationMs
        self.text = text
        self.name = name
    }

    public func validated() throws -> ControlCommand {
        switch type {
        case "pointer":
            guard let phase, ["down", "move", "up"].contains(phase) else {
                throw ControlError("Pointer phase must be down, move, or up")
            }
            try validatePoint(x: x, y: y)
        case "tap":
            try validatePoint(x: x, y: y)
        case "swipe":
            try validatePoint(x: x, y: y)
            try validatePoint(x: x2, y: y2)
            if let durationMs, !(100 ... 3_000).contains(durationMs) {
                throw ControlError("Swipe duration must be between 100 and 3000 milliseconds")
            }
        case "type":
            guard let text, !text.isEmpty else {
                throw ControlError("Text must be non-empty")
            }
            guard text.utf8.count <= 4_096 else {
                throw ControlError("Text is limited to 4096 UTF-8 bytes")
            }
        case "shortcut":
            guard let name, ["home", "appSwitcher", "spotlight"].contains(name) else {
                throw ControlError("Unknown shortcut")
            }
        default:
            throw ControlError("Unknown control command")
        }
        return self
    }

    private func validatePoint(x: Double?, y: Double?) throws {
        guard let x, let y,
              x.isFinite, y.isFinite,
              (0 ... 1).contains(x),
              (0 ... 1).contains(y)
        else {
            throw ControlError("Coordinates must be numbers between 0 and 1")
        }
    }
}

public struct ControlError: LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
