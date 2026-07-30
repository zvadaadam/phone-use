import AppKit
import ApplicationServices
import Foundation

final class SessionController: @unchecked Sendable {
    static let mirroringBundleIdentifier = "com.apple.ScreenContinuity"

    enum ConnectionState: Sendable {
        case connected
        case paused
        case noWindow
        case notRunning
    }

    func open() async throws {
        if runningApplication() == nil {
            guard let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: Self.mirroringBundleIdentifier
            ) else {
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
        attemptConnect()
    }

    @discardableResult
    func close() -> Bool {
        guard let application = runningApplication() else { return true }
        return application.terminate()
    }

    func isRunning() -> Bool {
        runningApplication() != nil
    }

    private func runningApplication() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.mirroringBundleIdentifier
        ).first
    }

    func attemptConnect() {
        guard AXIsProcessTrusted(),
              let application = runningApplication()
        else {
            return
        }
        application.activate()
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let window = element(
            of: applicationElement,
            attribute: kAXFocusedWindowAttribute
        ) ?? element(
            of: applicationElement,
            attribute: kAXMainWindowAttribute
        ) ?? values(
            of: applicationElement,
            attribute: kAXWindowsAttribute
        )?.first else {
            return
        }
        let actions = Set(["connect", "resume", "try again", "ok"])
        if let button = findButton(named: actions, in: window, depth: 0) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    func connectionState() -> ConnectionState {
        guard let application = runningApplication() else {
            return .notRunning
        }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let window = element(
            of: applicationElement,
            attribute: kAXFocusedWindowAttribute
        ) ?? element(
            of: applicationElement,
            attribute: kAXMainWindowAttribute
        ) else {
            return .noWindow
        }
        guard let hostingView = values(
            of: window,
            attribute: kAXChildrenAttribute
        )?.first else {
            return .noWindow
        }
        let overlayChildren = values(
            of: hostingView,
            attribute: kAXChildrenAttribute
        ) ?? []
        return overlayChildren.isEmpty ? .connected : .paused
    }

    private func findButton(
        named names: Set<String>,
        in element: AXUIElement,
        depth: Int
    ) -> AXUIElement? {
        guard depth < 8 else { return nil }
        if value(of: element, attribute: kAXRoleAttribute) == kAXButtonRole as String {
            for attribute in [kAXTitleAttribute, kAXDescriptionAttribute] {
                if let label = value(of: element, attribute: attribute)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased(),
                   names.contains(label) {
                    return element
                }
            }
        }
        guard let children = values(of: element, attribute: kAXChildrenAttribute) else {
            return nil
        }
        for child in children {
            if let found = findButton(named: names, in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private func element(of element: AXUIElement, attribute: String) -> AXUIElement? {
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

    private func value(of element: AXUIElement, attribute: String) -> String? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &rawValue
        ) == .success else {
            return nil
        }
        return rawValue as? String
    }

    private func values(of element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &rawValue
        ) == .success else {
            return nil
        }
        return rawValue as? [AXUIElement]
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
