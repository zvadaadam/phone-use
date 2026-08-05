import CoreGraphics

enum HIDEventFactory {
    enum MousePhase {
        case down
        case up

        var eventType: CGEventType {
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

    private static let continuousScroll = CGEventField(rawValue: 88)!
    private static let pointDeltaY = CGEventField(rawValue: 96)!
    private static let pointDeltaX = CGEventField(rawValue: 97)!
    private static let scrollPhase = CGEventField(rawValue: 99)!

    static func screenPoint(
        normalizedX: Double,
        normalizedY: Double,
        within bounds: CGRect
    ) -> CGPoint {
        CGPoint(
            x: bounds.minX + (bounds.width * normalizedX),
            y: bounds.minY + (bounds.height * normalizedY)
        )
    }

    static func mouse(phase: MousePhase, at point: CGPoint) -> CGEvent? {
        CGEvent(
            mouseEventSource: nil,
            mouseType: phase.eventType,
            mouseCursorPosition: point,
            mouseButton: .left
        )
    }

    static func mouseMoved(at point: CGPoint) -> CGEvent? {
        CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
    }

    static func scroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        phase: ScrollPhase,
        at point: CGPoint
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
        event.location = point
        event.setIntegerValueField(continuousScroll, value: 1)
        event.setIntegerValueField(pointDeltaY, value: Int64(deltaY.rounded()))
        event.setIntegerValueField(pointDeltaX, value: Int64(deltaX.rounded()))
        event.setIntegerValueField(scrollPhase, value: phase.rawValue)
        return event
    }
}
