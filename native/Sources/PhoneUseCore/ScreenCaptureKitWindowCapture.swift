import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import ScreenCaptureKit

final class FrameRateGate {
    private let minimumInterval: CFTimeInterval
    private var lastAcceptedAt: CFTimeInterval?

    init(framesPerSecond: Double) {
        minimumInterval = 1 / max(1, framesPerSecond)
    }

    func shouldAccept(at timestamp: CFTimeInterval) -> Bool {
        guard let lastAcceptedAt else {
            self.lastAcceptedAt = timestamp
            return true
        }
        guard timestamp - lastAcceptedAt >= minimumInterval else {
            return false
        }
        self.lastAcceptedAt = timestamp
        return true
    }

    func reset() {
        lastAcceptedAt = nil
    }
}

struct ScreenCaptureGeometry: Equatable, Sendable {
    let width: Int
    let height: Int

    static func pixels(for pointSize: CGSize, scale: CGFloat) -> Self {
        Self(
            width: max(1, Int((pointSize.width * scale).rounded())),
            height: max(1, Int((pointSize.height * scale).rounded()))
        )
    }

    static func forWindowFrame(_ frame: CGRect) -> Self {
        let mainDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        let appKitFrame = CGRect(
            x: frame.minX,
            y: mainDisplayHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
        let scale = NSScreen.screens.max(by: {
            intersectionArea(appKitFrame, $0.frame)
                < intersectionArea(appKitFrame, $1.frame)
        })?.backingScaleFactor ?? 2
        return pixels(for: frame.size, scale: scale)
    }

    private static func intersectionArea(_ left: CGRect, _ right: CGRect) -> CGFloat {
        let intersection = left.intersection(right)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

enum ScreenCaptureStreamState {
    case stopped
    case starting
    case running
    case failed(String)
}

final class ScreenCaptureKitWindowCapture: NSObject, @unchecked Sendable {
    typealias FrameHandler = @Sendable (CapturedWindowFrame) -> Void

    private let lock = NSLock()
    private let sampleQueue = DispatchQueue(
        label: "dev.phone-use.screen-capture",
        qos: .userInteractive
    )
    private let imageContext = CIContext(
        options: [.cacheIntermediates: false]
    )
    private let frameRateGate = FrameRateGate(
        framesPerSecond: CapturePolicy.outputFramesPerSecond
    )
    private var stream: SCStream?
    private var frameHandler: FrameHandler?
    private var streamState = ScreenCaptureStreamState.stopped

    func start(
        windowID: CGWindowID,
        frameHandler: @escaping FrameHandler
    ) async throws -> ScreenCaptureGeometry {
        await stop()

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let window = content.windows.first(where: {
            $0.windowID == windowID
        }) else {
            throw ScreenCaptureError.windowUnavailable
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let geometry = ScreenCaptureGeometry.pixels(
            for: window.frame.size,
            scale: CGFloat(filter.pointPixelScale)
        )
        let configuration = SCStreamConfiguration()
        configuration.width = geometry.width
        configuration.height = geometry.height
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CapturePolicy.sourceFramesPerSecond
        )
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.colorSpaceName = CGColorSpace.sRGB

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        try stream.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: sampleQueue
        )

        lock.withLock {
            self.stream = stream
            self.frameHandler = frameHandler
            streamState = .starting
            frameRateGate.reset()
        }

        do {
            try await stream.startCapture()
            let terminalError = lock.withLock { () -> ScreenCaptureError? in
                guard self.stream === stream else {
                    return .stoppedDuringStart
                }
                switch streamState {
                case .starting:
                    streamState = .running
                    return nil
                case let .failed(message):
                    return .streamFailed(message)
                case .stopped:
                    return .stoppedDuringStart
                case .running:
                    return nil
                }
            }
            if let terminalError {
                try? stream.removeStreamOutput(self, type: .screen)
                try? await stream.stopCapture()
                clear(stream: stream)
                throw terminalError
            }
            return geometry
        } catch {
            clear(stream: stream)
            throw error
        }
    }

    func stop() async {
        let stream = lock.withLock {
            let current = self.stream
            self.stream = nil
            frameHandler = nil
            streamState = .stopped
            frameRateGate.reset()
            return current
        }

        guard let stream else { return }
        try? stream.removeStreamOutput(self, type: .screen)
        try? await stream.stopCapture()
    }

    func state() -> ScreenCaptureStreamState {
        lock.lock()
        defer { lock.unlock() }
        return streamState
    }

    private func clear(stream: SCStream) {
        lock.lock()
        if self.stream === stream {
            self.stream = nil
            frameHandler = nil
            streamState = .stopped
            frameRateGate.reset()
        }
        lock.unlock()
    }

    private func encodeFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let statusRawValue = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: statusRawValue) == .complete,
            sampleBuffer.isValid,
            let pixelBuffer = sampleBuffer.imageBuffer
        else {
            return
        }

        let handler: FrameHandler?
        lock.lock()
        guard case .running = streamState,
            frameRateGate.shouldAccept(at: CACurrentMediaTime())
        else {
            lock.unlock()
            return
        }
        handler = frameHandler
        lock.unlock()

        guard let handler,
            let frame = jpegFrame(from: pixelBuffer)
        else {
            return
        }
        handler(frame)
    }

    private func jpegFrame(from pixelBuffer: CVPixelBuffer) -> CapturedWindowFrame? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let bounds = image.extent.integral
        guard !bounds.isEmpty,
            let cgImage = imageContext.createCGImage(image, from: bounds)
        else {
            return nil
        }

        return JPEGFrameEncoder.encode(cgImage)
    }
}

extension ScreenCaptureKitWindowCapture: SCStreamOutput, SCStreamDelegate {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen else { return }
        encodeFrame(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        guard self.stream === stream else {
            lock.unlock()
            return
        }
        streamState = .failed(error.localizedDescription)
        frameHandler = nil
        lock.unlock()
    }
}

private enum ScreenCaptureError: LocalizedError {
    case windowUnavailable
    case stoppedDuringStart
    case streamFailed(String)

    var errorDescription: String? {
        switch self {
        case .windowUnavailable:
            "The iPhone Mirroring window disappeared before capture started"
        case .stoppedDuringStart:
            "ScreenCaptureKit stopped while its stream was starting"
        case let .streamFailed(message):
            "ScreenCaptureKit stopped while starting: \(message)"
        }
    }
}
