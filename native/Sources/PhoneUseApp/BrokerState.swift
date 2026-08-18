import Foundation
import PhoneUseProtocol

final class BrokerState: @unchecked Sendable {
    private let lock = NSLock()
    private var runtime = DeviceHubRuntimeStatus.unavailable
    private var recentLogs: [String] = []
    private var observers: [UUID: @Sendable (PhoneUseStatus) -> Void] = [:]

    func update(_ status: DeviceHubRuntimeStatus) {
        let notification: (PhoneUseStatus, [@Sendable (PhoneUseStatus) -> Void])? = lock.withLock {
            guard runtime != status else { return nil }
            runtime = status
            return (snapshotLocked(), Array(observers.values))
        }
        notify(notification)
    }

    func log(_ message: String) {
        let notification = lock.withLock {
            recentLogs.append(message)
            recentLogs = Array(recentLogs.suffix(100))
            return (snapshotLocked(), Array(observers.values))
        }
        notify(notification)
    }

    func snapshot() -> PhoneUseStatus {
        lock.withLock { snapshotLocked() }
    }

    @discardableResult
    func observeStatus(_ observer: @escaping @Sendable (PhoneUseStatus) -> Void) -> UUID {
        let id = UUID()
        let snapshot = lock.withLock {
            observers[id] = observer
            return snapshotLocked()
        }
        observer(snapshot)
        return id
    }

    func removeStatusObserver(_ id: UUID) {
        lock.withLock { _ = observers.removeValue(forKey: id) }
    }

    private func snapshotLocked() -> PhoneUseStatus {
        PhoneUseStatus(
            product: PhoneUseProtocolMetadata.productIdentifier,
            version: PhoneUseProtocolMetadata.shortVersion(),
            protocolVersion: PhoneUseProtocolMetadata.currentVersion,
            transport: DeviceHubRuntimeStatus.transportIdentifier,
            phase: runtime.phase,
            proof: runtime.proof,
            message: runtime.message,
            requirements: .ios27,
            controlCapabilities: runtime.controlCapabilities,
            frame: runtime.frame,
            macFocusPolicy: "never-change-mac-focus",
            internetRelayAvailable: false,
            logs: Array(recentLogs.suffix(20))
        )
    }

    private func notify(
        _ notification: (PhoneUseStatus, [@Sendable (PhoneUseStatus) -> Void])?
    ) {
        guard let (snapshot, observers) = notification else { return }
        for observer in observers {
            observer(snapshot)
        }
    }
}
