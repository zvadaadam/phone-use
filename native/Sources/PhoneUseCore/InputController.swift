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
    public func handle(_ rawCommand: ControlCommand) throws -> Bool {
        commandLock.lock()
        defer { commandLock.unlock() }

        let command = try rawCommand.validated()
        guard AXIsProcessTrusted() else {
            logger.log("Control command rejected because Accessibility is not authorized")
            return false
        }
        guard target.current() != nil else {
            logger.log("Control command rejected because iPhone Mirroring is not connected")
            return false
        }

        switch command.type {
        case "tap":
            return tap(command)
        case "swipe":
            return swipe(command)
        case "type":
            guard let text = command.text else { return false }
            return type(text)
        case "shortcut":
            guard let name = command.name else { return false }
            return shortcut(name)
        default:
            return false
        }
    }

    private func tap(_ command: ControlCommand) -> Bool {
        guard let x = command.x,
            let y = command.y,
            let prepared = preparePointerTarget()
        else {
            return false
        }

        guard postPointer(x: x, y: y, phase: .down, target: prepared) else {
            return false
        }
        Thread.sleep(forTimeInterval: 0.05)
        guard postPointer(x: x, y: y, phase: .up, target: prepared) else {
            postUnconditionalMouseUp(x: x, y: y, target: prepared)
            return false
        }
        return true
    }

    private func swipe(_ command: ControlCommand) -> Bool {
        guard let startX = command.x,
            let startY = command.y,
            let endX = command.x2,
            let endY = command.y2,
            let prepared = preparePointerTarget()
        else {
            return false
        }
        let start = absolutePoint(x: startX, y: startY, bounds: prepared.bounds)
        let end = absolutePoint(x: endX, y: endY, bounds: prepared.bounds)
        let midpoint = CGPoint(
            x: start.x + ((end.x - start.x) / 2),
            y: start.y + ((end.y - start.y) / 2)
        )
        guard prepared.bounds.contains(midpoint) else { return false }

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
            return false
        }
        Thread.sleep(forTimeInterval: 0.08)

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
                return false
            }
            Thread.sleep(forTimeInterval: duration / Double(steps))
        }
        return postScroll(
            deltaX: 0,
            deltaY: 0,
            point: midpoint,
            phase: .ended,
            target: prepared
        )
    }

    private func type(_ text: String) -> Bool {
        guard let snapshot = target.current() else { return false }
        var characters = Array(text.utf16)
        guard !characters.isEmpty,
            let keyDown = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: false
            )
        else {
            return false
        }

        characters.withUnsafeMutableBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
            keyUp.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        guard targetStillMatches(snapshot) else { return false }
        keyDown.postToPid(snapshot.processID)
        Thread.sleep(forTimeInterval: 0.01)
        guard targetStillMatches(snapshot) else {
            keyUp.postToPid(snapshot.processID)
            return false
        }
        keyUp.postToPid(snapshot.processID)
        return true
    }

    private func shortcut(_ name: String) -> Bool {
        let keyCode: CGKeyCode
        switch name {
        case "home": keyCode = 18
        case "appSwitcher": keyCode = 19
        case "spotlight": keyCode = 20
        default: return false
        }
        guard let snapshot = target.current() else { return false }
        return postKey(keyCode, flags: .maskCommand, target: snapshot)
    }

    private func postPointer(
        x: Double,
        y: Double,
        phase: TargetedEventFactory.MousePhase,
        target prepared: StablePointerTarget
    ) -> Bool {
        let point = absolutePoint(x: x, y: y, bounds: prepared.bounds)
        guard pointerTargetStillMatches(prepared),
            prepared.bounds.contains(point),
            let event = TargetedEventFactory.leftMouse(
                phase: phase,
                for: prepared.snapshot.windowID,
                at: point,
                within: prepared.bounds
            )
        else {
            return false
        }
        event.postToPid(prepared.snapshot.processID)
        return true
    }

    private func postScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        point: CGPoint,
        phase: TargetedEventFactory.ScrollPhase,
        target prepared: StablePointerTarget
    ) -> Bool {
        guard pointerTargetStillMatches(prepared),
            prepared.bounds.contains(point),
            let event = TargetedEventFactory.scroll(
                deltaX: deltaX,
                deltaY: deltaY,
                phase: phase,
                for: prepared.snapshot.windowID,
                at: point,
                within: prepared.bounds
            )
        else {
            return false
        }
        event.postToPid(prepared.snapshot.processID)
        return true
    }

    private func postScrollEnd(
        at point: CGPoint,
        target prepared: StablePointerTarget
    ) {
        guard
            let event = TargetedEventFactory.scroll(
                deltaX: 0,
                deltaY: 0,
                phase: .ended,
                for: prepared.snapshot.windowID,
                at: point,
                within: prepared.bounds
            )
        else {
            return
        }
        event.postToPid(prepared.snapshot.processID)
    }

    private func postUnconditionalMouseUp(
        x: Double,
        y: Double,
        target prepared: StablePointerTarget
    ) {
        let point = absolutePoint(x: x, y: y, bounds: prepared.bounds)
        guard
            let event = TargetedEventFactory.leftMouse(
                phase: .up,
                for: prepared.snapshot.windowID,
                at: point,
                within: prepared.bounds
            )
        else {
            return
        }
        event.postToPid(prepared.snapshot.processID)
    }

    private func postKey(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags,
        target snapshot: WindowTarget.Snapshot
    ) -> Bool {
        guard
            let modifierDown = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0x37,
                keyDown: true
            ),
            let down = CGEvent(
                keyboardEventSource: nil,
                virtualKey: keyCode,
                keyDown: true
            ),
            let up = CGEvent(
                keyboardEventSource: nil,
                virtualKey: keyCode,
                keyDown: false
            ),
            let modifierUp = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0x37,
                keyDown: false
            )
        else {
            return false
        }

        modifierDown.type = .flagsChanged
        modifierDown.flags = flags
        down.flags = flags
        up.flags = flags
        modifierUp.type = .flagsChanged

        for event in [modifierDown, down, up, modifierUp] {
            guard targetStillMatches(snapshot) else {
                modifierUp.postToPid(snapshot.processID)
                return false
            }
            event.postToPid(snapshot.processID)
            Thread.sleep(forTimeInterval: 0.008)
        }
        return true
    }

    private func preparePointerTarget() -> StablePointerTarget? {
        guard let snapshot = target.current() else { return nil }
        let deadline = Date().addingTimeInterval(3)
        var stability = WindowBoundsStability(requiredConsecutiveSamples: 4)
        repeat {
            guard targetStillMatches(snapshot),
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

    private func targetStillMatches(_ snapshot: WindowTarget.Snapshot) -> Bool {
        target.current() == snapshot
    }

    private func pointerTargetStillMatches(_ prepared: StablePointerTarget) -> Bool {
        targetStillMatches(prepared.snapshot)
            && target.bounds(for: prepared.snapshot) == prepared.bounds
    }

    private func absolutePoint(x: Double, y: Double, bounds: CGRect) -> CGPoint {
        CGPoint(
            x: bounds.minX + (bounds.width * x),
            y: bounds.minY + (bounds.height * y)
        )
    }
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
