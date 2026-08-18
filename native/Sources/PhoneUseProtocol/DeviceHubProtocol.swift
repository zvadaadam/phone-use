import Foundation

public enum DeviceHubPhase: String, Codable, Equatable, Sendable {
    case unavailable
    case waitingForDevice
    case connecting
    case streaming
    case stopped
}

public struct DeviceActionReceipt: Codable, Equatable, Sendable {
    public let delivered: Bool
    public let verified: Bool
    public let macFocusChanged: Bool
    public let beforeFrameID: UInt64
    public let afterFrameID: UInt64
    public let message: String

    public init(
        delivered: Bool,
        verified: Bool,
        macFocusChanged: Bool,
        beforeFrameID: UInt64,
        afterFrameID: UInt64,
        message: String
    ) {
        self.delivered = delivered
        self.verified = verified
        self.macFocusChanged = macFocusChanged
        self.beforeFrameID = beforeFrameID
        self.afterFrameID = afterFrameID
        self.message = message
    }
}

public enum DeviceHubProofState: String, Codable, Equatable, Sendable {
    case unimplemented
    case awaitingPhysicalDevice
    case validated
}

public struct DeviceHubRequirements: Codable, Equatable, Sendable {
    public let minimumIOSVersion: String
    public let physicalDeviceRequired: Bool
    public let developerModeRequired: Bool
    public let hostConnection: String

    public init(
        minimumIOSVersion: String,
        physicalDeviceRequired: Bool,
        developerModeRequired: Bool,
        hostConnection: String
    ) {
        self.minimumIOSVersion = minimumIOSVersion
        self.physicalDeviceRequired = physicalDeviceRequired
        self.developerModeRequired = developerModeRequired
        self.hostConnection = hostConnection
    }

    public static let ios27 = DeviceHubRequirements(
        minimumIOSVersion: "27.0",
        physicalDeviceRequired: true,
        developerModeRequired: true,
        hostConnection: "USB or Apple-supported local wireless"
    )
}

public struct DeviceFrameStatus: Codable, Equatable, Sendable {
    public let id: UInt64
    public let width: Int
    public let height: Int
    public let ageMs: Int
    public let fps: Int

    public init(id: UInt64, width: Int, height: Int, ageMs: Int, fps: Int) {
        self.id = id
        self.width = width
        self.height = height
        self.ageMs = ageMs
        self.fps = fps
    }
}

public struct PhoneUseStatus: Codable, Equatable, Sendable {
    public let product: String
    public let version: String
    public let protocolVersion: Int
    public let transport: String
    public let phase: DeviceHubPhase
    public let proof: DeviceHubProofState
    public let message: String
    public let requirements: DeviceHubRequirements
    public let controlCapabilities: ControlCapabilities
    public let frame: DeviceFrameStatus?
    public let macFocusPolicy: String
    public let internetRelayAvailable: Bool
    public let logs: [String]

    public init(
        product: String,
        version: String,
        protocolVersion: Int,
        transport: String,
        phase: DeviceHubPhase,
        proof: DeviceHubProofState,
        message: String,
        requirements: DeviceHubRequirements,
        controlCapabilities: ControlCapabilities,
        frame: DeviceFrameStatus?,
        macFocusPolicy: String,
        internetRelayAvailable: Bool,
        logs: [String]
    ) {
        self.product = product
        self.version = version
        self.protocolVersion = protocolVersion
        self.transport = transport
        self.phase = phase
        self.proof = proof
        self.message = message
        self.requirements = requirements
        self.controlCapabilities = controlCapabilities
        self.frame = frame
        self.macFocusPolicy = macFocusPolicy
        self.internetRelayAvailable = internetRelayAvailable
        self.logs = logs
    }
}
