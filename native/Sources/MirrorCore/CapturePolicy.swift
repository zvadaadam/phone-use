import CoreGraphics
import Foundation

public enum CapturePolicy {
    public static let sourceFramesPerSecond: Int32 = 30
    public static let outputFramesPerSecond: Double = 15
    public static let streamRetryInterval: TimeInterval = 5
    public static let idleFallbackInterval: TimeInterval = 2
    public static let frameFreshnessInterval: TimeInterval = 3
    public static let pollIntervalMilliseconds: Int64 = 250

    static func shouldRestartStream(
        streamingWindowID: CGWindowID?,
        candidateWindowID: CGWindowID,
        currentGeometry: ScreenCaptureGeometry?,
        expectedGeometry: ScreenCaptureGeometry
    ) -> Bool {
        streamingWindowID == candidateWindowID
            && currentGeometry != expectedGeometry
    }

    static func shouldAttemptStream(
        streamingWindowID: CGWindowID?,
        candidateWindowID: CGWindowID,
        retryAt: Date,
        now: Date
    ) -> Bool {
        streamingWindowID != candidateWindowID && now >= retryAt
    }

    static func shouldUseHeartbeat(
        streamingWindowID: CGWindowID?,
        candidateWindowID: CGWindowID,
        streamIsRunning: Bool,
        frameIsFresh: Bool
    ) -> Bool {
        streamingWindowID == candidateWindowID
            && streamIsRunning
            && !frameIsFresh
    }
}
