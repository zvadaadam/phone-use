import Foundation
import MirrorCore

struct BrokerSnapshot: Codable, Sendable {
    let transport: String
    let phase: String
    let message: String
    let fps: Int
    let width: Int?
    let height: Int?
    let frameID: UInt64
    let frameAgeMs: Int?
    let screenCaptureAuthorized: Bool
    let accessibilityAuthorized: Bool
    let logs: [String]
}

struct FrameMarker: Sendable {
    let id: UInt64
    let contentHash: Int
}

final class BrokerState: BridgeOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var activeTransport = "starting"
    private var bridgeStatus = BridgeStatus(
        phase: "starting",
        message: "Mirror Relay is starting"
    )
    private var currentFrame: Data?
    private var currentFrameCapturedAt: Date?
    private var currentFrameID: UInt64 = 0
    private var currentFrameHash = 0
    private var framesThisSecond = 0
    private var currentFPS = 0
    private var recentLogs: [String] = []
    private var frameObservers: [UUID: @Sendable (Data, UInt64) -> Void] = [:]
    private var statusObservers: [UUID: @Sendable (BrokerSnapshot) -> Void] = [:]
    private let fpsTimer: DispatchSourceTimer

    init() {
        fpsTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        fpsTimer.schedule(deadline: .now() + 1, repeating: 1)
        fpsTimer.setEventHandler { [weak self] in
            self?.rollFPS()
        }
        fpsTimer.resume()
    }

    deinit {
        fpsTimer.cancel()
    }

    func frame(_ data: Data) {
        let observers: [@Sendable (Data, UInt64) -> Void]
        let frameID: UInt64
        lock.lock()
        currentFrame = data
        currentFrameCapturedAt = Date()
        currentFrameID &+= 1
        currentFrameHash = data.hashValue
        frameID = currentFrameID
        framesThisSecond += 1
        observers = Array(frameObservers.values)
        lock.unlock()
        for observer in observers {
            observer(data, frameID)
        }
    }

    func clearFrame() {
        lock.lock()
        currentFrame = nil
        currentFrameCapturedAt = nil
        currentFrameHash = 0
        framesThisSecond = 0
        currentFPS = 0
        let snapshot = snapshotLocked()
        let observers = Array(statusObservers.values)
        lock.unlock()
        for observer in observers {
            observer(snapshot)
        }
    }

    func status(_ status: BridgeStatus) {
        lock.lock()
        bridgeStatus = status
        let snapshot = snapshotLocked()
        let observers = Array(statusObservers.values)
        lock.unlock()
        for observer in observers {
            observer(snapshot)
        }
    }

    func setTransport(_ transport: String) {
        lock.lock()
        activeTransport = transport
        let snapshot = snapshotLocked()
        let observers = Array(statusObservers.values)
        lock.unlock()
        for observer in observers {
            observer(snapshot)
        }
    }

    func log(_ message: String) {
        lock.lock()
        recentLogs.append(message)
        if recentLogs.count > 100 {
            recentLogs.removeFirst(recentLogs.count - 100)
        }
        let snapshot = snapshotLocked()
        let observers = Array(statusObservers.values)
        lock.unlock()
        for observer in observers {
            observer(snapshot)
        }
    }

    func snapshot() -> BrokerSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshotLocked()
    }

    func latestFrame(maxAge: TimeInterval = 3) -> (data: Data, id: UInt64)? {
        lock.lock()
        defer { lock.unlock() }
        guard bridgeStatus.phase == "streaming",
            let currentFrame,
            let currentFrameCapturedAt,
            Date().timeIntervalSince(currentFrameCapturedAt) <= maxAge
        else {
            return nil
        }
        return (currentFrame, currentFrameID)
    }

    func frameMarker() -> FrameMarker {
        lock.lock()
        defer { lock.unlock() }
        return FrameMarker(id: currentFrameID, contentHash: currentFrameHash)
    }

    @discardableResult
    func observeFrames(_ observer: @escaping @Sendable (Data, UInt64) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        frameObservers[id] = observer
        let existing: (Data, UInt64)?
        if bridgeStatus.phase == "streaming",
            let currentFrame,
            let currentFrameCapturedAt,
            Date().timeIntervalSince(currentFrameCapturedAt) <= 3
        {
            existing = (currentFrame, currentFrameID)
        } else {
            existing = nil
        }
        lock.unlock()
        if let existing {
            observer(existing.0, existing.1)
        }
        return id
    }

    func removeFrameObserver(_ id: UUID) {
        lock.lock()
        frameObservers.removeValue(forKey: id)
        lock.unlock()
    }

    @discardableResult
    func observeStatus(_ observer: @escaping @Sendable (BrokerSnapshot) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        statusObservers[id] = observer
        let current = snapshotLocked()
        lock.unlock()
        observer(current)
        return id
    }

    func removeStatusObserver(_ id: UUID) {
        lock.lock()
        statusObservers.removeValue(forKey: id)
        lock.unlock()
    }

    private func rollFPS() {
        lock.lock()
        currentFPS = framesThisSecond
        framesThisSecond = 0
        let snapshot = snapshotLocked()
        let observers = Array(statusObservers.values)
        lock.unlock()
        for observer in observers {
            observer(snapshot)
        }
    }

    private func snapshotLocked() -> BrokerSnapshot {
        BrokerSnapshot(
            transport: activeTransport,
            phase: bridgeStatus.phase,
            message: bridgeStatus.message,
            fps: currentFPS,
            width: bridgeStatus.width,
            height: bridgeStatus.height,
            frameID: currentFrameID,
            frameAgeMs: currentFrameCapturedAt.map {
                max(0, Int(Date().timeIntervalSince($0) * 1_000))
            },
            screenCaptureAuthorized: bridgeStatus.screenCaptureAuthorized ?? false,
            accessibilityAuthorized: bridgeStatus.accessibilityAuthorized ?? false,
            logs: Array(recentLogs.suffix(20))
        )
    }
}
