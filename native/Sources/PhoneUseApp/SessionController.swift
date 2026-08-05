import AppKit
import ApplicationServices
import Foundation
import PhoneUseCore

final class SessionController: @unchecked Sendable {
    static let mirroringBundleIdentifier = "com.apple.ScreenContinuity"

    private let target: WindowTarget

    init(target: WindowTarget) {
        self.target = target
    }

    enum State: Equatable, Sendable {
        case candidateLive
        case paused
        case indeterminate
        case noWindow
        case notRunning
    }

    struct Inspection {
        let state: State
        let reconnectAction: AXUIElement?
    }

    func open() async throws {
        guard runningApplications().isEmpty else { return }
        guard
            let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: Self.mirroringBundleIdentifier
            )
        else {
            throw SessionError("iPhone Mirroring is not installed")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @discardableResult
    func requestClose() -> Bool {
        let applications = runningApplications()
        guard !applications.isEmpty else { return true }
        return applications.map { $0.terminate() }.allSatisfy { $0 }
    }

    func close(timeout: Duration = .seconds(5)) async -> Bool {
        guard requestClose() else { return false }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if SessionTerminationPolicy.isComplete(
                runningProcessIDs: runningApplications().map(\.processIdentifier)
            ) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return SessionTerminationPolicy.isComplete(
            runningProcessIDs: runningApplications().map(\.processIdentifier)
        )
    }

    func inspect() -> Inspection {
        guard AXIsProcessTrusted() else {
            return Inspection(state: .indeterminate, reconnectAction: nil)
        }
        let applications = runningApplications()
        guard !applications.isEmpty else {
            return Inspection(state: .notRunning, reconnectAction: nil)
        }
        guard let targetSnapshot = target.current(),
            let application = applications.first(where: {
                $0.processIdentifier == targetSnapshot.processID
            }),
            let targetBounds = target.bounds(for: targetSnapshot)
        else {
            return Inspection(state: .noWindow, reconnectAction: nil)
        }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let windows = candidateWindows(of: applicationElement)
        let candidateBounds = windows.map { bounds(of: $0) }
        guard let index = AccessibilityWindowSelector.matchingIndex(
            targetBounds: targetBounds,
            candidateBounds: candidateBounds
        ) else {
            return Inspection(state: .noWindow, reconnectAction: nil)
        }
        let window = windows[index]

        // A failed root read is not evidence of a connected session. Empty
        // children, however, is the normal opaque live Mirroring surface.
        guard case .value(let rootChildren) = readChildren(of: window) else {
            return Inspection(state: .indeterminate, reconnectAction: nil)
        }
        let snapshot = snapshot(
            of: window,
            children: rootChildren,
            childrenReadFailed: false,
            depth: 0,
            maximumDepth: 8,
            ancestorsAreUsable: true
        )
        let classification = MirroringSessionEvidence.classify(
            root: snapshot.evidence,
            hadReadFailure: snapshot.hadReadFailure
        )
        switch classification {
        case .candidateLive:
            return Inspection(
                state: .candidateLive,
                reconnectAction: snapshot.reconnectAction
            )
        case .paused:
            return Inspection(
                state: .paused,
                reconnectAction: snapshot.reconnectAction
            )
        case .indeterminate:
            return Inspection(state: .indeterminate, reconnectAction: nil)
        }
    }

    @discardableResult
    func performReconnectAction(from inspection: Inspection) -> Bool {
        guard let action = inspection.reconnectAction else { return false }
        return AXUIElementPerformAction(action, kAXPressAction as CFString) == .success
    }

    private func runningApplications() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.mirroringBundleIdentifier
        )
    }

    private func candidateWindows(of application: AXUIElement) -> [AXUIElement] {
        var candidates: [AXUIElement] = []
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = element(of: application, attribute: attribute),
                !candidates.contains(where: { CFEqual($0, window) })
            {
                candidates.append(window)
            }
        }
        for window in values(of: application, attribute: kAXWindowsAttribute) ?? []
        where !candidates.contains(where: { CFEqual($0, window) }) {
            candidates.append(window)
        }
        return candidates
    }

    private func bounds(of element: AXUIElement) -> CGRect? {
        guard let position = point(of: element, attribute: kAXPositionAttribute),
            let size = size(of: element, attribute: kAXSizeAttribute)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func point(of element: AXUIElement, attribute: String) -> CGPoint? {
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

    private func size(of element: AXUIElement, attribute: String) -> CGSize? {
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

    private struct EvidenceSnapshot {
        let evidence: MirroringSessionEvidence.Element
        let reconnectAction: AXUIElement?
        let hadReadFailure: Bool
    }

    private enum ChildrenRead {
        case value([AXUIElement])
        case failed
    }

    private func snapshot(
        of element: AXUIElement,
        children: [AXUIElement],
        childrenReadFailed: Bool,
        depth: Int,
        maximumDepth: Int,
        ancestorsAreUsable: Bool
    ) -> EvidenceSnapshot {
        let isEnabled = booleanValue(
            of: element,
            attribute: kAXEnabledAttribute,
            defaultValue: true
        )
        let isHidden = booleanValue(
            of: element,
            attribute: kAXHiddenAttribute,
            defaultValue: false
        )
        let isUsable = ancestorsAreUsable && isEnabled && !isHidden
        let descendants: [EvidenceSnapshot]
        if depth + 1 < maximumDepth {
            descendants = children.map { child -> EvidenceSnapshot in
                switch readChildren(of: child) {
                case .value(let childElements):
                    return snapshot(
                        of: child,
                        children: childElements,
                        childrenReadFailed: false,
                        depth: depth + 1,
                        maximumDepth: maximumDepth,
                        ancestorsAreUsable: isUsable
                    )
                case .failed:
                    return snapshot(
                        of: child,
                        children: [],
                        childrenReadFailed: true,
                        depth: depth + 1,
                        maximumDepth: maximumDepth,
                        ancestorsAreUsable: isUsable
                    )
                }
            }
        } else {
            descendants = []
        }
        let evidence = MirroringSessionEvidence.Element(
            identifier: value(of: element, attribute: kAXIdentifierAttribute),
            role: value(of: element, attribute: kAXRoleAttribute),
            title: value(of: element, attribute: kAXTitleAttribute),
            description: value(of: element, attribute: kAXDescriptionAttribute),
            isEnabled: isEnabled,
            isHidden: isHidden,
            children: descendants.map(\.evidence)
        )
        let reconnectAction =
            isUsable
                && MirroringSessionEvidence.isReconnectAction(evidence)
            ? element : nil
        return EvidenceSnapshot(
            evidence: evidence,
            reconnectAction: reconnectAction
                ?? descendants.lazy.compactMap(\.reconnectAction).first,
            hadReadFailure: childrenReadFailed
                || descendants.contains(where: \.hadReadFailure)
        )
    }

    private func readChildren(of element: AXUIElement) -> ChildrenRead {
        var rawValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &rawValue
        )
        switch error {
        case .success:
            guard let children = rawValue as? [AXUIElement] else {
                return .failed
            }
            return .value(children)
        case .attributeUnsupported, .noValue:
            return .value([])
        default:
            return .failed
        }
    }

    private func element(of element: AXUIElement, attribute: String) -> AXUIElement? {
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

    private func value(of element: AXUIElement, attribute: String) -> String? {
        var rawValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &rawValue
            ) == .success
        else {
            return nil
        }
        return rawValue as? String
    }

    private func booleanValue(
        of element: AXUIElement,
        attribute: String,
        defaultValue: Bool
    ) -> Bool {
        var rawValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &rawValue
            ) == .success,
            let number = rawValue as? NSNumber
        else {
            return defaultValue
        }
        return number.boolValue
    }

    private func values(of element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var rawValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &rawValue
            ) == .success
        else {
            return nil
        }
        return rawValue as? [AXUIElement]
    }
}

enum AccessibilityWindowSelector {
    static func matchingIndex(
        targetBounds: CGRect,
        candidateBounds: [CGRect?],
        maximumDistance: CGFloat = 2
    ) -> Int? {
        candidateBounds.enumerated()
            .compactMap { index, bounds -> (index: Int, distance: CGFloat)? in
                guard let bounds else { return nil }
                return (index, distance(targetBounds, bounds))
            }
            .min(by: { $0.distance < $1.distance })
            .flatMap { $0.distance <= maximumDistance ? $0.index : nil }
    }

    private static func distance(_ left: CGRect, _ right: CGRect) -> CGFloat {
        abs(left.minX - right.minX)
            + abs(left.minY - right.minY)
            + abs(left.width - right.width)
            + abs(left.height - right.height)
    }
}

enum SessionTerminationPolicy {
    static func isComplete(runningProcessIDs: [pid_t]) -> Bool {
        runningProcessIDs.isEmpty
    }
}

struct SessionError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
