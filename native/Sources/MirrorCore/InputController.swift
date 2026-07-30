import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public final class InputController: @unchecked Sendable {
    private let output: BridgeOutput
    private let target: WindowTarget
    private let commandLock = NSLock()

    public init(output: BridgeOutput, target: WindowTarget) {
        self.output = output
        self.target = target
    }

    @discardableResult
    public func handle(_ rawCommand: ControlCommand) throws -> Bool {
        commandLock.lock()
        defer { commandLock.unlock() }

        let command = try rawCommand.validated()
        guard AXIsProcessTrusted() else {
            output.status(
                phase: "permission",
                message: "Accessibility permission is required for iPhone control",
                accessibilityAuthorized: false
            )
            return false
        }
        guard target.current() != nil else {
            output.log("Control command rejected because iPhone Mirroring is not connected")
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
            let prepared = prepareTarget()
        else {
            return false
        }
        let savedCursor = CGEvent(source: nil)?.location
        defer { restoreCursor(savedCursor) }

        guard
            postPointer(
                x: x,
                y: y,
                eventType: .leftMouseDown,
                target: prepared
            )
        else {
            return false
        }
        Thread.sleep(forTimeInterval: 0.05)
        guard
            postPointer(
                x: x,
                y: y,
                eventType: .leftMouseUp,
                target: prepared
            )
        else {
            postUnconditionalMouseUp(x: x, y: y, bounds: prepared.bounds)
            return false
        }
        return true
    }

    private func swipe(_ command: ControlCommand) -> Bool {
        guard let startX = command.x,
            let startY = command.y,
            let endX = command.x2,
            let endY = command.y2,
            let prepared = prepareTarget()
        else {
            return false
        }
        let start = absolutePoint(x: startX, y: startY, bounds: prepared.bounds)
        let end = absolutePoint(x: endX, y: endY, bounds: prepared.bounds)
        let midpoint = CGPoint(
            x: start.x + ((end.x - start.x) / 2),
            y: start.y + ((end.y - start.y) / 2)
        )
        let savedCursor = CGEvent(source: nil)?.location
        defer { restoreCursor(savedCursor) }

        guard targetOwns(point: midpoint, prepared: prepared) else {
            return false
        }
        CGWarpMouseCursorPosition(midpoint)
        Thread.sleep(forTimeInterval: 0.1)
        guard targetOwns(point: midpoint, prepared: prepared) else {
            return false
        }
        if let move = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: midpoint,
            mouseButton: .left
        ) {
            move.post(tap: .cghidEventTap)
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
                phase: 128,
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
                    phase: index == 0 ? 1 : 2,
                    target: prepared
                )
            else {
                postScrollEnd(at: midpoint)
                return false
            }
            Thread.sleep(forTimeInterval: duration / Double(steps))
        }
        return postScroll(
            deltaX: 0,
            deltaY: 0,
            point: midpoint,
            phase: 4,
            target: prepared
        )
    }

    private func type(_ text: String) -> Bool {
        guard let prepared = prepareTarget() else { return false }
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
        guard targetStillValid(prepared) else { return false }
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        guard targetStillValid(prepared) else {
            keyUp.post(tap: .cghidEventTap)
            return false
        }
        keyUp.post(tap: .cghidEventTap)
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
        guard let prepared = prepareTarget() else { return false }
        return postKey(keyCode, flags: .maskCommand, target: prepared)
    }

    private func postPointer(
        x: Double,
        y: Double,
        eventType: CGEventType,
        target prepared: PreparedTarget
    ) -> Bool {
        let point = absolutePoint(x: x, y: y, bounds: prepared.bounds)
        guard targetOwns(point: point, prepared: prepared),
            let event = CGEvent(
                mouseEventSource: nil,
                mouseType: eventType,
                mouseCursorPosition: point,
                mouseButton: .left
            )
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
        phase: Int64,
        target prepared: PreparedTarget
    ) -> Bool {
        guard targetOwns(point: point, prepared: prepared),
            let event = scrollEvent(
                deltaX: deltaX,
                deltaY: deltaY,
                point: point,
                phase: phase
            )
        else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func scrollEvent(
        deltaX: CGFloat,
        deltaY: CGFloat,
        point: CGPoint,
        phase: Int64
    ) -> CGEvent? {
        guard let continuous = CGEventField(rawValue: 88),
            let pointDeltaY = CGEventField(rawValue: 96),
            let pointDeltaX = CGEventField(rawValue: 97),
            let scrollPhase = CGEventField(rawValue: 99),
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
        event.setIntegerValueField(continuous, value: 1)
        event.setIntegerValueField(pointDeltaY, value: Int64(deltaY.rounded()))
        event.setIntegerValueField(pointDeltaX, value: Int64(deltaX.rounded()))
        event.setIntegerValueField(scrollPhase, value: phase)
        return event
    }

    private func postScrollEnd(at point: CGPoint) {
        scrollEvent(deltaX: 0, deltaY: 0, point: point, phase: 4)?
            .post(tap: .cghidEventTap)
    }

    private func postUnconditionalMouseUp(x: Double, y: Double, bounds: CGRect) {
        let point = absolutePoint(x: x, y: y, bounds: bounds)
        CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    private func postKey(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags,
        target prepared: PreparedTarget
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
            guard targetStillValid(prepared) else {
                modifierUp.post(tap: .cghidEventTap)
                return false
            }
            event.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.008)
        }
        return true
    }

    private func prepareTarget() -> PreparedTarget? {
        guard let snapshot = target.current() else { return nil }
        let alreadyFrontmost =
            NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.processID
        if !alreadyFrontmost,
            let application = NSRunningApplication(processIdentifier: snapshot.processID)
        {
            application.activate()
            Thread.sleep(forTimeInterval: 0.35)
        }
        guard let bounds = target.bounds(),
            NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.processID
        else {
            return nil
        }
        return PreparedTarget(snapshot: snapshot, bounds: bounds)
    }

    private func targetStillValid(_ prepared: PreparedTarget) -> Bool {
        guard let current = target.current(),
            current.windowID == prepared.snapshot.windowID,
            current.processID == prepared.snapshot.processID,
            NSWorkspace.shared.frontmostApplication?.processIdentifier
                == prepared.snapshot.processID,
            target.bounds() == prepared.bounds
        else {
            return false
        }
        return true
    }

    private func targetOwns(point: CGPoint, prepared: PreparedTarget) -> Bool {
        guard targetStillValid(prepared),
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return false
        }
        for window in windows {
            guard let rawBounds = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(
                    dictionaryRepresentation: rawBounds as CFDictionary
                ),
                bounds.contains(point),
                (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0
            else {
                continue
            }
            let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            let processID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            return windowID == prepared.snapshot.windowID
                && processID == prepared.snapshot.processID
        }
        return false
    }

    private func absolutePoint(x: Double, y: Double, bounds: CGRect) -> CGPoint {
        CGPoint(
            x: bounds.minX + (bounds.width * x),
            y: bounds.minY + (bounds.height * y)
        )
    }

    private func restoreCursor(_ point: CGPoint?) {
        guard let point else { return }
        CGWarpMouseCursorPosition(point)
    }
}

private struct PreparedTarget {
    let snapshot: WindowTarget.Snapshot
    let bounds: CGRect
}
