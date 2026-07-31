import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct WindowCaptureCommand {
    static func arguments(
        windowID: CGWindowID,
        outputPath: String
    ) -> [String] {
        ["-l", String(windowID), "-x", "-o", outputPath]
    }
}

struct CapturedWindowFrame: Sendable {
    let jpeg: Data
    let width: Int
    let height: Int
}

enum JPEGFrameEncoder {
    static func encode(_ image: CGImage) -> CapturedWindowFrame? {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return nil
        }
        let properties = [
            kCGImageDestinationLossyCompressionQuality: 0.78
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return CapturedWindowFrame(
            jpeg: output as Data,
            width: image.width,
            height: image.height
        )
    }
}

struct WindowCaptureCandidate: Sendable {
    let windowID: CGWindowID
    let processID: pid_t
    let bounds: CGRect
    let title: String?
}

enum WindowCaptureSelector {
    static func select(
        from candidates: [WindowCaptureCandidate],
        accessibilityBounds: CGRect?,
        localizedApplicationName: String?
    ) -> WindowCaptureCandidate? {
        if let localizedApplicationName,
            let titled = candidates.first(where: {
                $0.title == localizedApplicationName
            })
        {
            return titled
        }
        if let accessibilityBounds {
            return candidates.min {
                distance($0.bounds, accessibilityBounds)
                    < distance($1.bounds, accessibilityBounds)
            }
        }
        return candidates.max {
            ($0.bounds.width * $0.bounds.height)
                < ($1.bounds.width * $1.bounds.height)
        }
    }

    private static func distance(_ left: CGRect, _ right: CGRect) -> CGFloat {
        abs(left.minX - right.minX)
            + abs(left.minY - right.minY)
            + abs(left.width - right.width)
            + abs(left.height - right.height)
    }
}

final class CommandLineWindowCapture: @unchecked Sendable {
    private let executableURL: URL
    private let timeout: DispatchTimeInterval
    private let scratchRoot: URL
    private let scratchDirectory: URL

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/sbin/screencapture"),
        timeout: DispatchTimeInterval = .seconds(5)
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
        scratchRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mirror Relay Capture", isDirectory: true)
        scratchDirectory = scratchRoot.appendingPathComponent(
            "capture-\(getpid())-\(UUID().uuidString)",
            isDirectory: true
        )
        prepareScratchDirectory()
    }

    deinit {
        try? FileManager.default.removeItem(at: scratchDirectory)
    }

    func capture(windowID: CGWindowID) -> CapturedWindowFrame? {
        let outputURL =
            scratchDirectory
            .appendingPathComponent("frame-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let arguments = WindowCaptureCommand.arguments(
            windowID: windowID,
            outputPath: outputURL.path
        )
        guard run(arguments: arguments) else {
            return nil
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: outputURL.path
        )
        guard let png = try? Data(contentsOf: outputURL) else {
            return nil
        }
        return Self.jpegFrame(from: png)
    }

    private func prepareScratchDirectory() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: scratchRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scratchRoot.path
        )
        removeStaleScratchDirectories(fileManager: fileManager)
        try? fileManager.createDirectory(
            at: scratchDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scratchDirectory.path
        )
    }

    private func removeStaleScratchDirectories(fileManager: FileManager) {
        guard
            let directories = try? fileManager.contentsOfDirectory(
                at: scratchRoot,
                includingPropertiesForKeys: nil
            )
        else {
            return
        }
        for directory in directories {
            let parts = directory.lastPathComponent.split(separator: "-", maxSplits: 2)
            guard parts.count == 3,
                parts[0] == "capture",
                let processID = Int32(parts[1])
            else {
                continue
            }
            errno = 0
            if kill(processID, 0) == -1, errno == ESRCH {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    private func run(arguments: [String]) -> Bool {
        let process = Process()
        let completion = DispatchSemaphore(value: 0)
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            return false
        }

        guard completion.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            _ = completion.wait(timeout: .now() + .milliseconds(500))
            return false
        }
        return process.terminationStatus == 0
    }

    private static func jpegFrame(from png: Data) -> CapturedWindowFrame? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return JPEGFrameEncoder.encode(image)
    }
}

public final class MirrorCapture: @unchecked Sendable {
    private let bundleIdentifier = "com.apple.ScreenContinuity"
    private let output: BridgeOutput
    private let target: WindowTarget
    private let fallbackBackend: CommandLineWindowCapture
    private let streamingBackend: ScreenCaptureKitWindowCapture
    private let stateLock = NSLock()
    private let framePublicationLock = NSLock()
    private var activeWindowID: CGWindowID?
    private var lastStatusKey: String?
    private var streamGeneration: UInt64 = 0
    private var streamingFrameGeneration: UInt64 = 0
    private var streamingWindowID: CGWindowID?
    private var streamingGeometry: ScreenCaptureGeometry?
    private var streamingStartedAt: Date?
    private var lastStreamingFrameAt: Date?
    private var nextStreamingRetryAt = Date.distantPast
    private var usingFallbackHeartbeat = false

    public init(output: BridgeOutput, target: WindowTarget) {
        self.output = output
        self.target = target
        fallbackBackend = CommandLineWindowCapture()
        streamingBackend = ScreenCaptureKitWindowCapture()
    }

    public func run() async {
        publishStatus(
            phase: "starting",
            message: "Looking for iPhone Mirroring"
        )
        output.captureMode(.unavailable)

        while !Task.isCancelled {
            guard CGPreflightScreenCaptureAccess() else {
                await stopStreamingBackend()
                target.clear()
                setActiveWindowID(nil)
                output.captureMode(.unavailable)
                output.clearFrame()
                publishStatus(
                    phase: "permission",
                    message: "Allow Screen Recording for Mirror Relay, then relaunch the app"
                )
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            guard let window = findMirroringWindow() else {
                await stopStreamingBackend()
                target.clear()
                setActiveWindowID(nil)
                output.captureMode(.unavailable)
                output.clearFrame()
                publishStatus(
                    phase: "waiting",
                    message: "Open iPhone Mirroring to begin"
                )
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            if currentActiveWindowID() != window.windowID {
                await stopStreamingBackend()
                setActiveWindowID(window.windowID)
                nextStreamingRetryAt = .distantPast
                target.update(windowID: window.windowID, processID: window.processID)
                output.log(
                    "Found iPhone Mirroring window \(window.windowID)"
                )
            } else {
                target.update(windowID: window.windowID, processID: window.processID)
            }

            let expectedGeometry = ScreenCaptureGeometry.forWindowFrame(window.bounds)
            if CapturePolicy.shouldRestartStream(
                streamingWindowID: streamingWindowID,
                candidateWindowID: window.windowID,
                currentGeometry: streamingGeometry,
                expectedGeometry: expectedGeometry
            ) {
                output.log(
                    "iPhone Mirroring resized to \(expectedGeometry.width)x"
                        + "\(expectedGeometry.height); restarting its capture stream"
                )
                await stopStreamingBackend()
                nextStreamingRetryAt = .distantPast
            }

            if case let .failed(message) = streamingBackend.state() {
                output.log("ScreenCaptureKit stream stopped: \(message)")
                await stopStreamingBackend()
                nextStreamingRetryAt = Date().addingTimeInterval(
                    CapturePolicy.streamRetryInterval
                )
            }

            if CapturePolicy.shouldAttemptStream(
                streamingWindowID: streamingWindowID,
                candidateWindowID: window.windowID,
                retryAt: nextStreamingRetryAt,
                now: Date()
            ) {
                do {
                    try await startStreamingBackend(for: window)
                    try? await Task.sleep(
                        for: .milliseconds(CapturePolicy.pollIntervalMilliseconds)
                    )
                    continue
                } catch {
                    output.log(
                        "ScreenCaptureKit unavailable; using screenshot fallback: "
                            + error.localizedDescription
                    )
                    await stopStreamingBackend()
                    nextStreamingRetryAt = Date().addingTimeInterval(
                        CapturePolicy.streamRetryInterval
                    )
                }
            }

            var heartbeatFrameGeneration: UInt64?
            let streamIsRunning: Bool
            if case .running = streamingBackend.state() {
                streamIsRunning = true
            } else {
                streamIsRunning = false
            }
            let streamFrameIsFresh = streamingFrameIsFresh(
                maxAge: CapturePolicy.idleFallbackInterval
            )
            if streamingWindowID == window.windowID,
                streamIsRunning,
                streamFrameIsFresh
            {
                usingFallbackHeartbeat = false
                try? await Task.sleep(
                    for: .milliseconds(CapturePolicy.pollIntervalMilliseconds)
                )
                continue
            }
            if CapturePolicy.shouldUseHeartbeat(
                streamingWindowID: streamingWindowID,
                candidateWindowID: window.windowID,
                streamIsRunning: streamIsRunning,
                frameIsFresh: streamFrameIsFresh
            ) {
                if !usingFallbackHeartbeat {
                    output.log(
                        "ScreenCaptureKit is idle; using exact-window heartbeat frames"
                    )
                    usingFallbackHeartbeat = true
                }
                heartbeatFrameGeneration = currentStreamingFrameGeneration()
            }

            let frame = await captureFrame(windowID: window.windowID)
            if let heartbeatFrameGeneration {
                let didPublish = publishHeartbeatFallback(
                    frame,
                    expectedFrameGeneration: heartbeatFrameGeneration,
                    window: window
                )
                if didPublish {
                    if frame == nil {
                        try? await Task.sleep(for: .seconds(1))
                    } else {
                        try? await Task.sleep(
                            for: .milliseconds(CapturePolicy.pollIntervalMilliseconds)
                        )
                    }
                }
                continue
            }

            guard let frame else {
                output.captureMode(.unavailable)
                output.clearFrame()
                publishStatus(
                    phase: "reconnecting",
                    message: "Mirroring is visible but its next frame could not be captured"
                )
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            publishStatus(
                phase: "streaming",
                message: "iPhone Mirroring frames are available",
                width: frame.width,
                height: frame.height,
                windowTitle: window.title
            )
            output.captureMode(.screenshotFallback)
            output.frame(frame.jpeg)
            try? await Task.sleep(
                for: .milliseconds(CapturePolicy.pollIntervalMilliseconds)
            )
        }

        await stopStreamingBackend()
        target.clear()
        setActiveWindowID(nil)
        output.clearFrame()
    }

    private func captureFrame(
        windowID: CGWindowID
    ) async -> CapturedWindowFrame? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [fallbackBackend] in
                continuation.resume(
                    returning: fallbackBackend.capture(windowID: windowID)
                )
            }
        }
    }

    private func startStreamingBackend(
        for window: WindowCaptureCandidate
    ) async throws {
        let generation = beginStreamingGeneration()
        do {
            let geometry = try await streamingBackend.start(
                windowID: window.windowID
            ) { [weak self] frame in
                self?.receiveStreamingFrame(
                    frame,
                    windowID: window.windowID,
                    windowTitle: window.title,
                    streamGeneration: generation
                )
            }
            streamingWindowID = window.windowID
            streamingGeometry = geometry
        } catch {
            invalidateStreamingGeneration()
            throw error
        }
        output.log(
            "Streaming iPhone Mirroring window \(window.windowID) "
                + "with public ScreenCaptureKit"
        )
    }

    private func stopStreamingBackend() async {
        streamingWindowID = nil
        streamingGeometry = nil
        usingFallbackHeartbeat = false
        invalidateStreamingGeneration()
        output.captureMode(.unavailable)
        await streamingBackend.stop()
    }

    private func receiveStreamingFrame(
        _ frame: CapturedWindowFrame,
        windowID: CGWindowID,
        windowTitle: String?,
        streamGeneration: UInt64
    ) {
        framePublicationLock.lock()
        defer { framePublicationLock.unlock() }
        let isActive = stateLock.withLock {
            guard activeWindowID == windowID,
                self.streamGeneration == streamGeneration
            else {
                return false
            }
            streamingFrameGeneration &+= 1
            lastStreamingFrameAt = Date()
            return true
        }
        guard isActive else { return }
        output.captureMode(.screenCaptureKit)
        publishStatus(
            phase: "streaming",
            message: "iPhone Mirroring frames are available",
            width: frame.width,
            height: frame.height,
            windowTitle: windowTitle
        )
        output.frame(frame.jpeg)
    }

    private func beginStreamingGeneration() -> UInt64 {
        framePublicationLock.withLock {
            stateLock.withLock {
                streamGeneration &+= 1
                streamingFrameGeneration &+= 1
                streamingStartedAt = Date()
                lastStreamingFrameAt = nil
                return streamGeneration
            }
        }
    }

    private func invalidateStreamingGeneration() {
        framePublicationLock.withLock {
            stateLock.withLock {
                streamGeneration &+= 1
                streamingFrameGeneration &+= 1
                streamingStartedAt = nil
                lastStreamingFrameAt = nil
            }
        }
    }

    private func currentStreamingFrameGeneration() -> UInt64 {
        stateLock.withLock { streamingFrameGeneration }
    }

    private func publishHeartbeatFallback(
        _ frame: CapturedWindowFrame?,
        expectedFrameGeneration: UInt64,
        window: WindowCaptureCandidate
    ) -> Bool {
        framePublicationLock.lock()
        defer { framePublicationLock.unlock() }
        let isCurrent = stateLock.withLock {
            activeWindowID == window.windowID
                && streamingFrameGeneration == expectedFrameGeneration
        }
        guard isCurrent else { return false }

        guard let frame else {
            output.captureMode(.unavailable)
            output.clearFrame()
            publishStatus(
                phase: "reconnecting",
                message: "Mirroring is visible but its next frame could not be captured"
            )
            return true
        }
        publishStatus(
            phase: "streaming",
            message: "iPhone Mirroring frames are available",
            width: frame.width,
            height: frame.height,
            windowTitle: window.title
        )
        output.captureMode(.screenshotFallback)
        output.frame(frame.jpeg)
        return true
    }

    private func streamingFrameIsFresh(maxAge: TimeInterval) -> Bool {
        stateLock.withLock {
            guard let reference = lastStreamingFrameAt ?? streamingStartedAt else {
                return false
            }
            return Date().timeIntervalSince(reference) <= maxAge
        }
    }

    private func currentActiveWindowID() -> CGWindowID? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeWindowID
    }

    private func setActiveWindowID(_ windowID: CGWindowID?) {
        stateLock.lock()
        activeWindowID = windowID
        stateLock.unlock()
    }

    private func findMirroringWindow() -> WindowCaptureCandidate? {
        guard
            let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).first
        else {
            return nil
        }
        let processID = application.processIdentifier
        guard
            let rawWindows = CGWindowListCopyWindowInfo(
                [.optionAll, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return nil
        }

        let candidates = rawWindows.compactMap { raw -> WindowCaptureCandidate? in
            guard (raw[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID,
                (raw[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                let windowID = (raw[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let rawBounds = raw[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(
                    dictionaryRepresentation: rawBounds as CFDictionary
                ),
                bounds.width > 100,
                bounds.height > 100
            else {
                return nil
            }
            return WindowCaptureCandidate(
                windowID: windowID,
                processID: processID,
                bounds: bounds,
                title: raw[kCGWindowName as String] as? String
            )
        }
        return WindowCaptureSelector.select(
            from: candidates,
            accessibilityBounds: accessibilityWindowBounds(processID: processID),
            localizedApplicationName: application.localizedName
        )
    }

    private func accessibilityWindowBounds(processID: pid_t) -> CGRect? {
        let application = AXUIElementCreateApplication(processID)
        guard
            let window = accessibilityElement(
                of: application,
                attribute: kAXMainWindowAttribute
            )
                ?? accessibilityElement(
                    of: application,
                    attribute: kAXFocusedWindowAttribute
                ),
            let position = accessibilityPoint(
                of: window,
                attribute: kAXPositionAttribute
            ),
            let size = accessibilitySize(
                of: window,
                attribute: kAXSizeAttribute
            )
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func accessibilityElement(
        of element: AXUIElement,
        attribute: String
    ) -> AXUIElement? {
        var rawValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &rawValue
            ) == .success,
            let rawValue,
            CFGetTypeID(rawValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(rawValue, to: AXUIElement.self)
    }

    private func accessibilityPoint(
        of element: AXUIElement,
        attribute: String
    ) -> CGPoint? {
        guard let value = accessibilityValue(of: element, attribute: attribute) else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetType(value) == .cgPoint,
            AXValueGetValue(value, .cgPoint, &point)
        else {
            return nil
        }
        return point
    }

    private func accessibilitySize(
        of element: AXUIElement,
        attribute: String
    ) -> CGSize? {
        guard let value = accessibilityValue(of: element, attribute: attribute) else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetType(value) == .cgSize,
            AXValueGetValue(value, .cgSize, &size)
        else {
            return nil
        }
        return size
    }

    private func accessibilityValue(
        of element: AXUIElement,
        attribute: String
    ) -> AXValue? {
        var rawValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &rawValue
            ) == .success,
            let rawValue,
            CFGetTypeID(rawValue) == AXValueGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(rawValue, to: AXValue.self)
    }

    private func publishStatus(
        phase: String,
        message: String,
        width: Int? = nil,
        height: Int? = nil,
        windowTitle: String? = nil
    ) {
        let key = "\(phase)|\(message)|\(width ?? 0)|\(height ?? 0)"
        stateLock.lock()
        guard key != lastStatusKey else {
            stateLock.unlock()
            return
        }
        lastStatusKey = key
        stateLock.unlock()
        output.status(
            phase: phase,
            message: message,
            width: width,
            height: height,
            windowTitle: windowTitle,
            screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
            accessibilityAuthorized: AXIsProcessTrusted()
        )
    }
}
