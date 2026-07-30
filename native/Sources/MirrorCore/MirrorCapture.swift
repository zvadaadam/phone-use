import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WindowCaptureMode: Sendable {
    case window
    case region
}

struct WindowCaptureCommand {
    static func arguments(
        mode: WindowCaptureMode,
        windowID: CGWindowID,
        bounds: CGRect,
        outputPath: String
    ) -> [String] {
        switch mode {
        case .window:
            return ["-l", String(windowID), "-x", "-o", outputPath]
        case .region:
            let region = [
                Int(bounds.minX.rounded()),
                Int(bounds.minY.rounded()),
                max(Int(bounds.width.rounded()), 1),
                max(Int(bounds.height.rounded()), 1)
            ].map(String.init).joined(separator: ",")
            return ["-R", region, "-x", "-o", outputPath]
        }
    }
}

struct CapturedWindowFrame: Sendable {
    let jpeg: Data
    let width: Int
    let height: Int
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
           }) {
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

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/sbin/screencapture"),
        timeout: DispatchTimeInterval = .seconds(5)
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    func capture(windowID: CGWindowID, bounds: CGRect) -> CapturedWindowFrame? {
        for mode in [WindowCaptureMode.window, .region] {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("mirror-relay-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: outputURL) }

            let arguments = WindowCaptureCommand.arguments(
                mode: mode,
                windowID: windowID,
                bounds: bounds,
                outputPath: outputURL.path
            )
            guard run(arguments: arguments),
                  let png = try? Data(contentsOf: outputURL),
                  let frame = Self.jpegFrame(from: png)
            else {
                continue
            }
            return frame
        }
        return nil
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

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
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

public final class MirrorCapture: @unchecked Sendable {
    private let bundleIdentifier = "com.apple.ScreenContinuity"
    private let output: BridgeOutput
    private let target: WindowTarget
    private let backend: CommandLineWindowCapture
    private var activeWindowID: CGWindowID?
    private var frameNumber = 0
    private var lastStatusKey: String?

    public init(output: BridgeOutput, target: WindowTarget) {
        self.output = output
        self.target = target
        backend = CommandLineWindowCapture()
    }

    public func run() async {
        publishStatus(
            phase: "starting",
            message: "Looking for iPhone Mirroring"
        )

        while !Task.isCancelled {
            guard CGPreflightScreenCaptureAccess() else {
                target.clear()
                activeWindowID = nil
                publishStatus(
                    phase: "permission",
                    message: "Allow Screen Recording for Mirror Relay, then relaunch the app"
                )
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            guard let window = findMirroringWindow() else {
                target.clear()
                activeWindowID = nil
                frameNumber = 0
                publishStatus(
                    phase: "waiting",
                    message: "Open iPhone Mirroring to begin"
                )
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            if activeWindowID != window.windowID {
                activeWindowID = window.windowID
                frameNumber = 0
                target.update(windowID: window.windowID, processID: window.processID)
                activate(processID: window.processID)
                output.log(
                    "Capturing iPhone Mirroring window \(window.windowID) "
                        + "with the macOS screenshot service"
                )
            } else {
                target.update(windowID: window.windowID, processID: window.processID)
            }

            guard let frame = await captureFrame(
                windowID: window.windowID,
                bounds: window.bounds
            ) else {
                publishStatus(
                    phase: "reconnecting",
                    message: "Mirroring is visible but its next frame could not be captured"
                )
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            frameNumber += 1
            if frameNumber == 1 {
                publishStatus(
                    phase: "streaming",
                    message: "iPhone Mirroring frames are available",
                    width: frame.width,
                    height: frame.height,
                    windowTitle: window.title
                )
            }
            output.frame(frame.jpeg)
            try? await Task.sleep(for: .milliseconds(250))
        }

        target.clear()
        activeWindowID = nil
    }

    public func stop() async {
        target.clear()
        activeWindowID = nil
    }

    private func captureFrame(
        windowID: CGWindowID,
        bounds: CGRect
    ) async -> CapturedWindowFrame? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [backend] in
                continuation.resume(
                    returning: backend.capture(windowID: windowID, bounds: bounds)
                )
            }
        }
    }

    private func findMirroringWindow() -> WindowCaptureCandidate? {
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first else {
            return nil
        }
        let processID = application.processIdentifier
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
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
        guard let window = accessibilityElement(
            of: application,
            attribute: kAXMainWindowAttribute
        ) ?? accessibilityElement(
            of: application,
            attribute: kAXFocusedWindowAttribute
        ), let position = accessibilityPoint(
            of: window,
            attribute: kAXPositionAttribute
        ), let size = accessibilitySize(
            of: window,
            attribute: kAXSizeAttribute
        ) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func accessibilityElement(
        of element: AXUIElement,
        attribute: String
    ) -> AXUIElement? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
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
        guard AXUIElementCopyAttributeValue(
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

    private func activate(processID: pid_t) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != processID,
              let application = NSRunningApplication(processIdentifier: processID)
        else {
            return
        }
        application.activate()
        Thread.sleep(forTimeInterval: 0.3)
    }

    private func publishStatus(
        phase: String,
        message: String,
        width: Int? = nil,
        height: Int? = nil,
        windowTitle: String? = nil
    ) {
        let key = "\(phase)|\(message)|\(width ?? 0)|\(height ?? 0)"
        guard key != lastStatusKey else { return }
        lastStatusKey = key
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
