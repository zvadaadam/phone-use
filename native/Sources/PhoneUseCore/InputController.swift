import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import PhoneUseProtocol

public final class InputController: @unchecked Sendable {
    private let logger: BrokerLogger
    private let target: WindowTarget
    private let commandLock = NSLock()

    public init(logger: BrokerLogger, target: WindowTarget) {
        self.logger = logger
        self.target = target
    }

    @discardableResult
    public func handle(_ rawCommand: ControlCommand) throws -> InputDelivery {
        commandLock.lock()
        defer { commandLock.unlock() }

        let command = try rawCommand.validated()
        guard AXIsProcessTrusted() else {
            logger.log("Control command rejected because Accessibility is not authorized")
            return .rejected
        }
        guard target.current() != nil else {
            logger.log("Control command rejected because iPhone Mirroring is not connected")
            return .rejected
        }

        switch command.type {
        case "tap":
            return tap(command)
        case "swipe":
            return swipe(command)
        case "type":
            guard let text = command.text else { return .rejected }
            return type(text)
        case "shortcut":
            guard let name = command.name else { return .rejected }
            return shortcut(name)
        default:
            return .rejected
        }
    }

    private func tap(_ command: ControlCommand) -> InputDelivery {
        guard let x = command.x,
            let y = command.y,
            let initialTarget = target.current(),
            let preparedBeforeFocus = preparePointerTarget(
                processID: initialTarget.processID
            )
        else {
            return .rejected
        }
        return withUnchangedFocus(on: initialTarget.processID) {
            guard
                let prepared = refreshPointerTarget(
                    preparedBeforeFocus,
                    processID: initialTarget.processID
                )
            else {
                return .rejected
            }
            guard postPointer(x: x, y: y, phase: .down, target: prepared) else {
                return .rejected
            }
            Thread.sleep(forTimeInterval: 0.035)
            guard postPointer(x: x, y: y, phase: .up, target: prepared) else {
                postUnconditionalMouseUp(x: x, y: y, target: prepared)
                return InputAttempt(eventPosted: true, completed: false)
            }
            return .completed
        }
    }

    private func swipe(_ command: ControlCommand) -> InputDelivery {
        guard let startX = command.x,
            let startY = command.y,
            let endX = command.x2,
            let endY = command.y2,
            let initialTarget = target.current(),
            let preparedBeforeFocus = preparePointerTarget(
                processID: initialTarget.processID
            )
        else {
            return .rejected
        }
        return withUnchangedFocus(on: initialTarget.processID) {
            guard
                let prepared = refreshPointerTarget(
                    preparedBeforeFocus,
                    processID: initialTarget.processID
                )
            else {
                return .rejected
            }
            let start = absolutePoint(x: startX, y: startY, bounds: prepared.bounds)
            let end = absolutePoint(x: endX, y: endY, bounds: prepared.bounds)
            let midpoint = CGPoint(
                x: start.x + ((end.x - start.x) / 2),
                y: start.y + ((end.y - start.y) / 2)
            )
            guard prepared.bounds.contains(midpoint) else { return .rejected }
            CGWarpMouseCursorPosition(midpoint)
            if let move = HIDEventFactory.mouseMoved(at: midpoint) {
                move.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.025)
            }

            let duration = Double(command.durationMs ?? 350) / 1_000
            let steps = max(Int(duration * 60), 10)
            let deltaX = (end.x - start.x) / CGFloat(steps)
            let deltaY = (end.y - start.y) / CGFloat(steps)

            guard
                postScroll(
                    deltaX: 0,
                    deltaY: 0,
                    point: midpoint,
                    phase: .mayBegin,
                    target: prepared
                )
            else {
                return .rejected
            }
            Thread.sleep(forTimeInterval: 0.05)

            for index in 0..<steps {
                guard
                    postScroll(
                        deltaX: deltaX,
                        deltaY: deltaY,
                        point: midpoint,
                        phase: index == 0 ? .began : .changed,
                        target: prepared
                    )
                else {
                    postScrollEnd(at: midpoint, target: prepared)
                    return InputAttempt(eventPosted: true, completed: false)
                }
                Thread.sleep(forTimeInterval: duration / Double(steps))
            }
            let ended = postScroll(
                deltaX: 0,
                deltaY: 0,
                point: midpoint,
                phase: .ended,
                target: prepared
            )
            return InputAttempt(eventPosted: true, completed: ended)
        }
    }

    private func type(_ text: String) -> InputDelivery {
        let strokes = text.map(PhysicalKeyMap.stroke)
        guard !strokes.isEmpty,
            strokes.allSatisfy({ $0 != nil }),
            let snapshot = target.current()
        else {
            logger.log("Text command contains a character without a physical key mapping")
            return .rejected
        }
        return withUnchangedFocus(on: snapshot.processID) {
            var posted = false
            for stroke in strokes.compactMap({ $0 }) {
                let attempt = postKey(
                    stroke.keyCode,
                    flags: stroke.flags,
                    processID: snapshot.processID
                )
                posted = posted || attempt.eventPosted
                guard attempt.completed else {
                    return InputAttempt(eventPosted: posted, completed: false)
                }
                Thread.sleep(forTimeInterval: 0.008)
            }
            return InputAttempt(eventPosted: posted, completed: true)
        }
    }

    private func shortcut(_ name: String) -> InputDelivery {
        let keyCode: CGKeyCode
        switch name {
        case "home": keyCode = 18
        case "appSwitcher": keyCode = 19
        case "spotlight": keyCode = 20
        default: return .rejected
        }
        guard let snapshot = target.current() else { return .rejected }
        return withUnchangedFocus(on: snapshot.processID) {
            postKey(keyCode, flags: .maskCommand, processID: snapshot.processID)
        }
    }

    private func postPointer(
        x: Double,
        y: Double,
        phase: HIDEventFactory.MousePhase,
        target prepared: StablePointerTarget
    ) -> Bool {
        let point = absolutePoint(x: x, y: y, bounds: prepared.bounds)
        guard pointerTargetStillMatches(prepared),
            prepared.bounds.contains(point),
            let event = HIDEventFactory.mouse(phase: phase, at: point)
        else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func postScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        point: CGPoint,
        phase: HIDEventFactory.ScrollPhase,
        target prepared: StablePointerTarget
    ) -> Bool {
        guard pointerTargetStillMatches(prepared),
            prepared.bounds.contains(point),
            let event = HIDEventFactory.scroll(
                deltaX: deltaX,
                deltaY: deltaY,
                phase: phase,
                at: point
            )
        else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func postScrollEnd(
        at point: CGPoint,
        target prepared: StablePointerTarget
    ) {
        guard
            let event = HIDEventFactory.scroll(
                deltaX: 0,
                deltaY: 0,
                phase: .ended,
                at: point
            )
        else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    private func postUnconditionalMouseUp(
        x: Double,
        y: Double,
        target prepared: StablePointerTarget
    ) {
        let point = absolutePoint(x: x, y: y, bounds: prepared.bounds)
        guard
            let event = HIDEventFactory.mouse(phase: .up, at: point)
        else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    private func postKey(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags,
        processID: pid_t
    ) -> InputAttempt {
        guard
            let down = CGEvent(
                keyboardEventSource: nil,
                virtualKey: keyCode,
                keyDown: true
            ),
            let up = CGEvent(
                keyboardEventSource: nil,
                virtualKey: keyCode,
                keyDown: false
            )
        else {
            return .rejected
        }
        down.flags = flags
        up.flags = flags

        var events: [CGEvent] = []
        if !flags.isEmpty {
            guard let modifierKeyCode = modifierKeyCode(for: flags),
                let modifierDown = CGEvent(
                    keyboardEventSource: nil,
                    virtualKey: modifierKeyCode,
                    keyDown: true
                ),
                let modifierUp = CGEvent(
                    keyboardEventSource: nil,
                    virtualKey: modifierKeyCode,
                    keyDown: false
                )
            else {
                return .rejected
            }
            modifierDown.type = .flagsChanged
            modifierDown.flags = flags
            modifierUp.type = .flagsChanged
            events.append(modifierDown)
            events.append(down)
            events.append(up)
            events.append(modifierUp)
        } else {
            events = [down, up]
        }

        var posted = false
        for event in events {
            guard targetProcessIsFrontmost(processID) else {
                return InputAttempt(eventPosted: posted, completed: false)
            }
            event.post(tap: .cghidEventTap)
            posted = true
            Thread.sleep(forTimeInterval: 0.008)
        }
        return InputAttempt(eventPosted: posted, completed: true)
    }

    private func modifierKeyCode(for flags: CGEventFlags) -> CGKeyCode? {
        if flags == .maskShift { return 0x38 }
        if flags == .maskCommand { return 0x37 }
        if flags == .maskAlternate { return 0x3A }
        if flags == .maskControl { return 0x3B }
        return nil
    }

    private func preparePointerTarget(
        processID: pid_t,
        requiredConsecutiveSamples: Int = 4
    ) -> StablePointerTarget? {
        guard let snapshot = target.current(), snapshot.processID == processID else {
            return nil
        }
        let deadline = Date().addingTimeInterval(3)
        var stability = WindowBoundsStability(
            requiredConsecutiveSamples: requiredConsecutiveSamples
        )
        repeat {
            guard target.current() == snapshot,
                let bounds = target.bounds(for: snapshot)
            else {
                logger.log("Control command lost its iPhone Mirroring target")
                return nil
            }
            if stability.observe(bounds) {
                return StablePointerTarget(snapshot: snapshot, bounds: bounds)
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline

        logger.log("Control command could not prepare stable iPhone Mirroring bounds")
        return nil
    }

    private func refreshPointerTarget(
        _ previous: StablePointerTarget,
        processID: pid_t
    ) -> StablePointerTarget? {
        if target.bounds(for: previous.snapshot) == previous.bounds {
            return previous
        }
        return preparePointerTarget(
            processID: processID,
            requiredConsecutiveSamples: 2
        )
    }

    private func pointerTargetStillMatches(_ prepared: StablePointerTarget) -> Bool {
        targetProcessIsFrontmost(prepared.snapshot.processID)
            && target.bounds(for: prepared.snapshot) == prepared.bounds
    }

    private func targetProcessIsFrontmost(_ processID: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
    }

    private func withUnchangedFocus(
        on processID: pid_t,
        operation: () -> InputAttempt
    ) -> InputDelivery {
        let foregroundBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard foregroundBefore == processID else {
            logger.log(
                "Control command refused because iPhone Mirroring is not already frontmost"
            )
            return .rejected
        }
        let attempt = operation()
        let focusChanged =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
            != foregroundBefore
        if focusChanged {
            logger.log("Mac focus changed while a control command was in flight")
        }
        return InputDelivery(
            completed: attempt.completed,
            eventPosted: attempt.eventPosted,
            focusPreserved: !focusChanged
        )
    }

    private func absolutePoint(x: Double, y: Double, bounds: CGRect) -> CGPoint {
        HIDEventFactory.screenPoint(
            normalizedX: x,
            normalizedY: y,
            within: bounds
        )
    }
}

private struct InputAttempt {
    let eventPosted: Bool
    let completed: Bool

    static let rejected = InputAttempt(eventPosted: false, completed: false)
    static let completed = InputAttempt(eventPosted: true, completed: true)
}

private struct StablePointerTarget {
    let snapshot: WindowTarget.Snapshot
    let bounds: CGRect
}

struct WindowBoundsStability {
    let requiredConsecutiveSamples: Int
    private var previousBounds: CGRect?
    private var consecutiveSamples = 0

    init(requiredConsecutiveSamples: Int) {
        precondition(requiredConsecutiveSamples > 0)
        self.requiredConsecutiveSamples = requiredConsecutiveSamples
    }

    mutating func observe(_ bounds: CGRect) -> Bool {
        if bounds == previousBounds {
            consecutiveSamples += 1
        } else {
            previousBounds = bounds
            consecutiveSamples = 1
        }
        return consecutiveSamples >= requiredConsecutiveSamples
    }
}
