import CryptoKit
import Foundation
import PhoneUseCore
import PhoneUseProtocol

struct BrokerSnapshot: Codable, Sendable {
    let product: String
    let version: String
    let protocolVersion: Int
    let transport: String
    let phase: BrokerPhase
    let message: String
    let fps: Int
    let width: Int?
    let height: Int?
    let frameID: UInt64
    let frameAgeMs: Int?
    let captureMode: CaptureMode
    let screenCaptureAuthorized: Bool
    let accessibilityAuthorized: Bool
    let logs: [String]
}

struct FrameMarker: Sendable {
    let id: UInt64
    let token: String
}

final class BrokerState: CaptureOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var activeTransport = "starting"
    private var activeCaptureMode = CaptureMode.unavailable
    private var captureStatus = CaptureStatus(
        phase: .starting,
        message: "Looking for iPhone Mirroring"
    )
    private var sessionState = MirroringSessionState.starting
    private var permissions = BrokerPermissions(
        screenCaptureAuthorized: false,
        accessibilityAuthorized: false
    )
    private var lastCaptureFrameAt: Date?
    private var currentFrame: Data?
    private var currentFrameCapturedAt: Date?
    private var currentFrameID: UInt64 = 0
    private var currentFrameToken = ""
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
        let frameObservers: [@Sendable (Data, UInt64) -> Void]
        let statusObservers: [@Sendable (BrokerSnapshot) -> Void]
        let snapshot: BrokerSnapshot
        let frameID: UInt64
        lock.lock()
        lastCaptureFrameAt = Date()
        guard sessionState == .connected else {
            lock.unlock()
            return
        }
        let wasStreaming = effectiveStatusLocked().phase == .streaming
        currentFrame = data
        currentFrameCapturedAt = lastCaptureFrameAt
        currentFrameID &+= 1
        currentFrameToken =
            VisualFrameFingerprint.token(for: data)
            ?? SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        frameID = currentFrameID
        framesThisSecond += 1
        snapshot = snapshotLocked()
        frameObservers =
            snapshot.phase == .streaming
            ? Array(self.frameObservers.values) : []
        statusObservers = wasStreaming ? [] : Array(self.statusObservers.values)
        lock.unlock()
        for observer in frameObservers {
            observer(data, frameID)
        }
        for observer in statusObservers {
            observer(snapshot)
        }
    }

    func clearFrame() {
        lock.lock()
        lastCaptureFrameAt = nil
        clearPublishedFrameLocked()
        let snapshot = snapshotLocked()
        let observers = Array(statusObservers.values)
        lock.unlock()
        notify(observers, snapshot: snapshot)
    }

    func captureMode(_ mode: CaptureMode) {
        lock.lock()
        guard activeCaptureMode != mode else {
            lock.unlock()
            return
        }
        activeCaptureMode = mode
        let snapshot = snapshotLocked()
        let observers = Array(statusObservers.values)
        lock.unlock()
        notify(observers, snapshot: snapshot)
    }

    func status(_ status: CaptureStatus) {
        lock.lock()
        guard captureStatus != status else {
            lock.unlock()
            return
        }
        captureStatus = status
        if status.phase != .streaming {
            clearPublishedFrameLocked()
        }
        let snapshot = snapshotLocked()
        let observers = Array(statusObservers.values)
        lock.unlock()
        notify(observers, snapshot: snapshot)
    }

    func updateSession(_ session: MirroringSessionState) {
        lock.lock()
        guard sessionState != session else {
            lock.unlock()
            return
        }
        sessionState = session
        clearPublishedFrameLocked()
        let snapshot = snapshotLocked()
        let observers = Array(statusObservers.values)
        lock.unlock()
        notify(observers, snapshot: snapshot)
    }

    func updatePermissions(_ newPermissions: BrokerPermissions) {
        lock.lock()
        guard permissions != newPermissions else {
            lock.unlock()
            return
        }
        permissions = newPermissions
        if !newPermissions.screenCaptureAuthorized
            || !newPermissions.accessibilityAuthorized
        {
            clearPublishedFrameLocked()
        }
        let snapshot = snapshotLocked()
        let observers = Array(statusObservers.values)
        lock.unlock()
        notify(observers, snapshot: snapshot)
    }

    func captureIsReady(
        maxAge: TimeInterval = CapturePolicy.frameFreshnessInterval
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return captureStatus.phase == .streaming
            && lastCaptureFrameAt.map { Date().timeIntervalSince($0) <= maxAge } == true
    }

    func setTransport(_ transport: String) {
        lock.lock()
        guard activeTransport != transport else {
            lock.unlock()
            return
        }
        activeTransport = transport
        let snapshot = snapshotLocked()
        let observers = Array(statusObservers.values)
        lock.unlock()
        notify(observers, snapshot: snapshot)
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
        notify(observers, snapshot: snapshot)
    }

    func snapshot() -> BrokerSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshotLocked()
    }

    func latestFrame(
        maxAge: TimeInterval = CapturePolicy.frameFreshnessInterval
    ) -> (data: Data, id: UInt64, token: String)? {
        lock.lock()
        defer { lock.unlock() }
        guard effectiveStatusLocked().phase == .streaming,
            let currentFrame,
            let currentFrameCapturedAt,
            Date().timeIntervalSince(currentFrameCapturedAt) <= maxAge
        else {
            return nil
        }
        return (currentFrame, currentFrameID, currentFrameToken)
    }

    func frameMarker() -> FrameMarker {
        lock.lock()
        defer { lock.unlock() }
        return FrameMarker(id: currentFrameID, token: currentFrameToken)
    }

    @discardableResult
    func observeFrames(_ observer: @escaping @Sendable (Data, UInt64) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        frameObservers[id] = observer
        let existing: (Data, UInt64)?
        if effectiveStatusLocked().phase == .streaming,
            let currentFrame,
            let currentFrameCapturedAt,
            Date().timeIntervalSince(currentFrameCapturedAt)
                <= CapturePolicy.frameFreshnessInterval
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
        let isStreaming = effectiveStatusLocked().phase == .streaming
        currentFPS = isStreaming ? framesThisSecond : 0
        framesThisSecond = 0
        let snapshot = snapshotLocked()
        let observers = Array(statusObservers.values)
        lock.unlock()
        notify(observers, snapshot: snapshot)
    }

    private func clearPublishedFrameLocked() {
        currentFrame = nil
        currentFrameCapturedAt = nil
        currentFrameToken = ""
        framesThisSecond = 0
        currentFPS = 0
    }

    private func snapshotLocked() -> BrokerSnapshot {
        let status = effectiveStatusLocked()
        let isStreaming = status.phase == .streaming
        return BrokerSnapshot(
            product: PhoneUseProtocolMetadata.productIdentifier,
            version: PhoneUseProtocolMetadata.shortVersion(),
            protocolVersion: PhoneUseProtocolMetadata.currentVersion,
            transport: activeTransport,
            phase: status.phase,
            message: status.message,
            fps: isStreaming ? currentFPS : 0,
            width: status.width,
            height: status.height,
            frameID: currentFrameID,
            frameAgeMs: isStreaming
                ? currentFrameCapturedAt.map {
                    max(0, Int(Date().timeIntervalSince($0) * 1_000))
                } : nil,
            captureMode: activeCaptureMode,
            screenCaptureAuthorized: permissions.screenCaptureAuthorized,
            accessibilityAuthorized: permissions.accessibilityAuthorized,
            logs: Array(recentLogs.suffix(20))
        )
    }

    private func effectiveStatusLocked() -> CaptureStatus {
        let hasFreshPublishedFrame =
            currentFrame != nil
            && currentFrameCapturedAt.map {
                Date().timeIntervalSince($0) <= CapturePolicy.frameFreshnessInterval
            } == true
        return BrokerStatusReducer.reduce(
            session: sessionState,
            capture: captureStatus,
            permissions: permissions,
            hasFreshPublishedFrame: hasFreshPublishedFrame
        )
    }

    private func notify(
        _ observers: [@Sendable (BrokerSnapshot) -> Void],
        snapshot: BrokerSnapshot
    ) {
        for observer in observers {
            observer(snapshot)
        }
    }
}
