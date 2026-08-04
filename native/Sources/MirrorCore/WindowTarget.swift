import CoreGraphics
import Foundation

public final class WindowTarget: @unchecked Sendable {
    public struct Snapshot: Equatable, Sendable {
        public let windowID: CGWindowID
        public let processID: pid_t
    }

    private let lock = NSLock()
    private var snapshot: Snapshot?

    public init() {}

    public func update(windowID: CGWindowID, processID: pid_t) {
        lock.lock()
        snapshot = Snapshot(windowID: windowID, processID: processID)
        lock.unlock()
    }

    public func clear() {
        lock.lock()
        snapshot = nil
        lock.unlock()
    }

    public func current() -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    public func bounds(for snapshot: Snapshot) -> CGRect? {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionIncludingWindow, .excludeDesktopElements],
                snapshot.windowID
            ) as? [[String: Any]],
            let rawBounds = windows.first?[kCGWindowBounds as String] as? NSDictionary
        else {
            return nil
        }
        return CGRect(dictionaryRepresentation: rawBounds as CFDictionary)
    }
}
