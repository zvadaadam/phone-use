import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public final class InputController: @unchecked Sendable {
    private let output: BridgeOutput
    private let target: WindowTarget

    public init(output: BridgeOutput, target: WindowTarget) {
        self.output = output
        self.target = target
    }

    public func startReadingStdin() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readLoop()
        }
    }

    @discardableResult
    public func handle(data: Data) -> Bool {
        do {
            let command = try JSONDecoder().decode(ControlCommand.self, from: data)
            return try handle(command)
        } catch {
            output.log("Ignored malformed control message: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    public func handle(_ rawCommand: ControlCommand) throws -> Bool {
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
            output.log("Control command deferred because iPhone Mirroring is not connected")
            return false
        }

        switch command.type {
        case "pointer":
            return pointer(command)
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

    private func readLoop() {
        while let line = readLine() {
            guard let data = line.data(using: .utf8) else { continue }
            _ = handle(data: data)
        }
    }

    private func pointer(_ command: ControlCommand) -> Bool {
        guard let x = command.x,
              let y = command.y,
              let phase = command.phase,
              let prepared = prepareTarget()
        else {
            return false
        }
        let eventType: CGEventType
        switch phase {
        case "down": eventType = .leftMouseDown
        case "move": eventType = .leftMouseDragged
        case "up": eventType = .leftMouseUp
        default: return false
        }
        return postPointer(
            x: x,
            y: y,
            eventType: eventType,
            bounds: prepared.bounds
        )
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

        guard postPointer(
            x: x,
            y: y,
            eventType: .leftMouseDown,
            bounds: prepared.bounds
        ) else {
            return false
        }
        Thread.sleep(forTimeInterval: 0.05)
        return postPointer(
            x: x,
            y: y,
            eventType: .leftMouseUp,
            bounds: prepared.bounds
        )
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
        let bounds = prepared.bounds
        let start = absolutePoint(x: startX, y: startY, bounds: bounds)
        let end = absolutePoint(x: endX, y: endY, bounds: bounds)
        let midpoint = CGPoint(
            x: start.x + ((end.x - start.x) / 2),
            y: start.y + ((end.y - start.y) / 2)
        )
        let savedCursor = CGEvent(source: nil)?.location
        defer { restoreCursor(savedCursor) }

        CGWarpMouseCursorPosition(midpoint)
        Thread.sleep(forTimeInterval: 0.1)
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

        guard postScroll(
            deltaX: 0,
            deltaY: 0,
            point: midpoint,
            phase: 128
        ) else {
            return false
        }
        Thread.sleep(forTimeInterval: 0.08)

        for index in 0 ..< steps {
            guard postScroll(
                deltaX: deltaX,
                deltaY: deltaY,
                point: midpoint,
                phase: index == 0 ? 1 : 2
            ) else {
                return false
            }
            Thread.sleep(forTimeInterval: duration / Double(steps))
        }
        return postScroll(
            deltaX: 0,
            deltaY: 0,
            point: midpoint,
            phase: 4
        )
    }

    private func postPointer(
        x: Double,
        y: Double,
        eventType: CGEventType,
        bounds: CGRect
    ) -> Bool {
        let point = absolutePoint(x: x, y: y, bounds: bounds)
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func postScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        point: CGPoint,
        phase: Int64
    ) -> Bool {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY.rounded()),
            wheel2: Int32(deltaX.rounded()),
            wheel3: 0
        ) else {
            return false
        }
        event.location = point
        event.setIntegerValueField(CGEventField(rawValue: 88)!, value: 1)
        event.setIntegerValueField(
            CGEventField(rawValue: 96)!,
            value: Int64(deltaY.rounded())
        )
        event.setIntegerValueField(
            CGEventField(rawValue: 97)!,
            value: Int64(deltaX.rounded())
        )
        event.setIntegerValueField(CGEventField(rawValue: 99)!, value: phase)
        event.post(tap: .cghidEventTap)
        return true
    }

    private func type(_ text: String) -> Bool {
        guard prepareTarget() != nil else { return false }
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
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.01)
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
        guard prepareTarget() != nil else { return false }
        return postKey(keyCode, flags: .maskCommand)
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let modifierDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0x37,
            keyDown: true
        ), let down = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: true
        ), let up = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: false
        ), let modifierUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0x37,
            keyDown: false
        ) else {
            return false
        }

        modifierDown.type = .flagsChanged
        modifierDown.flags = flags
        down.flags = flags
        up.flags = flags
        modifierUp.type = .flagsChanged

        for event in [modifierDown, down, up, modifierUp] {
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
           let application = NSRunningApplication(processIdentifier: snapshot.processID) {
            application.activate()
            Thread.sleep(forTimeInterval: 0.35)
        }
        guard let bounds = target.bounds() else { return nil }
        return PreparedTarget(bounds: bounds)
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
    let bounds: CGRect
}
