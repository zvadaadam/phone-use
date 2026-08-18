import Foundation
import PhoneUseProtocol

struct DeviceHubRuntimeStatus: Equatable, Sendable {
    static let transportIdentifier = "ios27-device-hub"

    let phase: DeviceHubPhase
    let proof: DeviceHubProofState
    let message: String
    let controlCapabilities: ControlCapabilities
    let frame: DeviceFrameStatus?

    static let unavailable = DeviceHubRuntimeStatus(
        phase: .unavailable,
        proof: .unimplemented,
        message: "The Device Hub backend still requires implementation and physical iOS 27 validation",
        controlCapabilities: .none,
        frame: nil
    )
}

struct DeviceObservation: Sendable {
    let jpeg: Data
    let id: UInt64
    let frameToken: String
    let width: Int
    let height: Int
}

protocol DeviceHubTransporting: Sendable {
    func start() async -> DeviceHubRuntimeStatus
    func stop() async -> DeviceHubRuntimeStatus
    func connect() async throws -> DeviceHubRuntimeStatus
    func disconnect() async -> DeviceHubRuntimeStatus
    func observe() async throws -> DeviceObservation
    func perform(_ command: ValidatedControlCommand) async throws -> DeviceActionReceipt
}

actor IOS27DeviceHubTransport: DeviceHubTransporting {
    private var runtime = DeviceHubRuntimeStatus.unavailable

    func start() -> DeviceHubRuntimeStatus {
        runtime = .unavailable
        return runtime
    }

    func stop() -> DeviceHubRuntimeStatus {
        runtime = DeviceHubRuntimeStatus(
            phase: .stopped,
            proof: runtime.proof,
            message: "Device Hub transport stopped",
            controlCapabilities: .none,
            frame: nil
        )
        return runtime
    }

    func connect() throws -> DeviceHubRuntimeStatus {
        throw DeviceHubTransportError.backendUnvalidated
    }

    func disconnect() -> DeviceHubRuntimeStatus {
        runtime = .unavailable
        return runtime
    }

    func observe() throws -> DeviceObservation {
        throw DeviceHubTransportError.backendUnvalidated
    }

    func perform(_ command: ValidatedControlCommand) throws -> DeviceActionReceipt {
        throw DeviceHubTransportError.backendUnvalidated
    }
}

enum DeviceHubTransportError: LocalizedError, Equatable, Sendable {
    case backendUnvalidated

    var errorDescription: String? {
        switch self {
        case .backendUnvalidated:
            "Device Hub control is unavailable until a physical iOS 27 frame-and-HID test passes"
        }
    }
}
