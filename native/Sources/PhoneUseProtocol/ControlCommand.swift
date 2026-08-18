import Foundation

public struct ControlCommand: Codable, Sendable {
    public let type: String
    public let x: Double?
    public let y: Double?
    public let x2: Double?
    public let y2: Double?
    public let durationMs: Int?
    public let text: String?
    public let name: String?
    public let expectedFrameToken: String?

    public init(
        type: String,
        x: Double? = nil,
        y: Double? = nil,
        x2: Double? = nil,
        y2: Double? = nil,
        durationMs: Int? = nil,
        text: String? = nil,
        name: String? = nil,
        expectedFrameToken: String? = nil
    ) {
        self.type = type
        self.x = x
        self.y = y
        self.x2 = x2
        self.y2 = y2
        self.durationMs = durationMs
        self.text = text
        self.name = name
        self.expectedFrameToken = expectedFrameToken
    }

    public func validated() throws -> ValidatedControlCommand {
        let action: ValidatedControlAction
        switch type {
        case "tap":
            let point = try validatedPoint(x: x, y: y)
            action = .tap(x: point.x, y: point.y)
        case "swipe":
            let start = try validatedPoint(x: x, y: y)
            let end = try validatedPoint(x: x2, y: y2)
            if let durationMs, !(100...3_000).contains(durationMs) {
                throw ControlError("Swipe duration must be between 100 and 3000 milliseconds")
            }
            action = .swipe(
                startX: start.x,
                startY: start.y,
                endX: end.x,
                endY: end.y,
                durationMs: durationMs ?? 350
            )
        case "type":
            guard let text, !text.isEmpty else {
                throw ControlError("Text must be non-empty")
            }
            guard text.utf8.count <= 4_096 else {
                throw ControlError("Text is limited to 4096 UTF-8 bytes")
            }
            action = .type(text)
        case "shortcut":
            guard let name, ["home", "appSwitcher", "spotlight"].contains(name) else {
                throw ControlError("Unknown shortcut")
            }
            guard let shortcut = ShortcutName(rawValue: name) else {
                throw ControlError("Unknown shortcut")
            }
            action = .shortcut(shortcut)
        default:
            throw ControlError("Unknown control command")
        }
        guard let expectedFrameToken else {
            throw ControlError(
                "A fresh frame token is required. Observe the phone immediately before acting."
            )
        }
        if expectedFrameToken.count != 64
            || !expectedFrameToken.allSatisfy(\.isHexDigit)
        {
            throw ControlError("Expected frame token must be a 64-character hexadecimal value")
        }
        return ValidatedControlCommand(
            action: action,
            frameLease: FrameLeaseToken(rawValue: expectedFrameToken)
        )
    }

    private func validatedPoint(x: Double?, y: Double?) throws -> (x: Double, y: Double) {
        guard let x, let y,
            x.isFinite, y.isFinite,
            (0...1).contains(x),
            (0...1).contains(y)
        else {
            throw ControlError("Coordinates must be numbers between 0 and 1")
        }
        return (x, y)
    }
}

public struct FrameLeaseToken: RawRepresentable, Equatable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum ShortcutName: String, Equatable, Sendable {
    case home
    case appSwitcher
    case spotlight

}

public enum ValidatedControlAction: Equatable, Sendable {
    case tap(x: Double, y: Double)
    case swipe(
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
        durationMs: Int
    )
    case type(String)
    case shortcut(ShortcutName)
}

public struct ValidatedControlCommand: Equatable, Sendable {
    public let action: ValidatedControlAction
    public let frameLease: FrameLeaseToken

    public init(action: ValidatedControlAction, frameLease: FrameLeaseToken) {
        self.action = action
        self.frameLease = frameLease
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
