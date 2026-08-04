import AppKit
import CoreGraphics

@_silgen_name("CGEventSetWindowLocation")
private func cgEventSetWindowLocation(
    _ event: CGEvent,
    _ location: CGPoint
)

/// Builds process-targeted input without activating or raising the destination
/// window. These WindowServer fields are private and intentionally isolated in
/// this one boundary.
enum TargetedEventFactory {
    enum MousePhase {
        case down
        case up

        var eventType: NSEvent.EventType {
            switch self {
            case .down: .leftMouseDown
            case .up: .leftMouseUp
            }
        }
    }

    enum ScrollPhase: Int64 {
        case mayBegin = 128
        case began = 1
        case changed = 2
        case ended = 4
    }

    private static let scrollWindowTarget = CGEventField(rawValue: 51)!
    private static let continuousScroll = CGEventField(rawValue: 88)!
    private static let windowUnderPointer = CGEventField(rawValue: 91)!
    private static let windowThatCanHandlePointer = CGEventField(rawValue: 92)!
    private static let pointDeltaY = CGEventField(rawValue: 96)!
    private static let pointDeltaX = CGEventField(rawValue: 97)!
    private static let scrollPhase = CGEventField(rawValue: 99)!

    /// Starting with `NSEvent` is significant. A directly-created mouse
    /// `CGEvent` can have the same visible fields and still be discarded for a
    /// background window or a window on another Space.
    static func leftMouse(
        phase: MousePhase,
        for windowID: CGWindowID,
        at globalPoint: CGPoint,
        within windowBounds: CGRect
    ) -> CGEvent? {
        guard
            let event = NSEvent.mouseEvent(
                with: phase.eventType,
                location: globalPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: Int(windowID),
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )?.cgEvent
        else {
            return nil
        }
        event.flags = []
        event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        event.setIntegerValueField(.mouseEventSubtype, value: 3)
        configure(
            event,
            for: windowID,
            at: globalPoint,
            within: windowBounds
        )
        return event
    }

    static func scroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        phase: ScrollPhase,
        for windowID: CGWindowID,
        at globalPoint: CGPoint,
        within windowBounds: CGRect
    ) -> CGEvent? {
        guard
            let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(deltaY.rounded()),
                wheel2: Int32(deltaX.rounded()),
                wheel3: 0
            )
        else {
            return nil
        }
        event.setIntegerValueField(continuousScroll, value: 1)
        event.setIntegerValueField(pointDeltaY, value: Int64(deltaY.rounded()))
        event.setIntegerValueField(pointDeltaX, value: Int64(deltaX.rounded()))
        event.setIntegerValueField(scrollPhase, value: phase.rawValue)
        event.setIntegerValueField(scrollWindowTarget, value: Int64(windowID))
        configure(
            event,
            for: windowID,
            at: globalPoint,
            within: windowBounds
        )
        return event
    }

    static func windowLocation(
        for globalPoint: CGPoint,
        within windowBounds: CGRect
    ) -> CGPoint {
        let topLeftLocal = CGPoint(
            x: globalPoint.x - windowBounds.minX,
            y: globalPoint.y - windowBounds.minY
        )
        return CGPoint(
            x: topLeftLocal.x,
            y: windowBounds.height - topLeftLocal.y
        )
    }

    private static func configure(
        _ event: CGEvent,
        for windowID: CGWindowID,
        at globalPoint: CGPoint,
        within windowBounds: CGRect
    ) {
        event.location = globalPoint
        event.setIntegerValueField(windowUnderPointer, value: Int64(windowID))
        event.setIntegerValueField(
            windowThatCanHandlePointer,
            value: Int64(windowID)
        )
        cgEventSetWindowLocation(
            event,
            windowLocation(for: globalPoint, within: windowBounds)
        )
    }
}
