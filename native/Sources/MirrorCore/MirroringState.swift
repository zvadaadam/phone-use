import Foundation

public struct RelayPermissions: Equatable, Sendable {
    public let screenCaptureAuthorized: Bool
    public let accessibilityAuthorized: Bool

    public init(
        screenCaptureAuthorized: Bool,
        accessibilityAuthorized: Bool
    ) {
        self.screenCaptureAuthorized = screenCaptureAuthorized
        self.accessibilityAuthorized = accessibilityAuthorized
    }
}

public enum MirroringSessionState: Equatable, Sendable {
    case starting
    case waitingForApplication
    case waitingForPhone
    case confirming
    case connected
}

public enum RelayStatusReducer {
    public static func reduce(
        session: MirroringSessionState,
        capture: CaptureStatus,
        permissions: RelayPermissions,
        hasFreshPublishedFrame: Bool
    ) -> CaptureStatus {
        if !permissions.screenCaptureAuthorized {
            return status(
                phase: .permission,
                message: "Screen Recording permission is required",
                capture: capture
            )
        }
        if !permissions.accessibilityAuthorized {
            return status(
                phase: .permission,
                message: "Accessibility permission is required for iPhone control",
                capture: capture
            )
        }

        switch session {
        case .starting:
            return status(
                phase: .starting,
                message: "Mirror Relay is starting",
                capture: capture
            )
        case .waitingForApplication:
            return status(
                phase: .waiting,
                message: "Open iPhone Mirroring to begin",
                capture: capture
            )
        case .waitingForPhone:
            return status(
                phase: .waiting,
                message: "Keep the iPhone powered on, nearby, and locked so Mirroring can connect",
                capture: capture
            )
        case .confirming:
            return status(
                phase: .reconnecting,
                message: "Confirming the iPhone Mirroring session",
                capture: capture
            )
        case .connected where !hasFreshPublishedFrame:
            return status(
                phase: .reconnecting,
                message: "Waiting for the first connected iPhone frame",
                capture: capture
            )
        case .connected:
            return status(
                phase: capture.phase,
                message: capture.message,
                capture: capture
            )
        }
    }

    private static func status(
        phase: RelayPhase,
        message: String,
        capture: CaptureStatus
    ) -> CaptureStatus {
        CaptureStatus(
            phase: phase,
            message: message,
            width: capture.width,
            height: capture.height,
            windowTitle: capture.windowTitle
        )
    }
}
