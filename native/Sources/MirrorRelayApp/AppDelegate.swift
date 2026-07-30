import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: BrokerState!
    private var coordinator: BridgeCoordinator!
    private var server: LocalHTTPServer!
    private var tokenStore: TokenStore!
    private var statusObserverID: UUID?
    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var permissionsLine: NSMenuItem!
    private var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            tokenStore = try TokenStore()
            state = BrokerState()
            coordinator = BridgeCoordinator(state: state)
            server = LocalHTTPServer(
                coordinator: coordinator,
                state: state,
                tokenStore: tokenStore,
                publicDirectory: Self.publicDirectory()
            )
            installMenu()
            enableLaunchAtLoginForInstalledApp()
            requestMissingPermissions()
            coordinator.start()
            try server.start()
            statusObserverID = state.observeStatus { [weak self] snapshot in
                DispatchQueue.main.async {
                    self?.updateMenu(snapshot)
                }
            }
        } catch {
            if let data = "[Mirror Relay] Startup failed: \(error)\n".data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
            let alert = NSAlert()
            alert.messageText = "Mirror Relay could not start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusObserverID {
            state.removeStatusObserver(statusObserverID)
        }
        server?.stop()
        coordinator?.stop()
    }

    @objc private func openDashboard() {
        guard let url = URL(
            string: "http://127.0.0.1:\(LocalHTTPServer.port)/?token=\(tokenStore.token)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSession() {
        statusLine.title = "Opening iPhone…"
        Task { [weak self] in
            do {
                try await self?.coordinator.ensureSession()
            } catch {
                self?.state.log("Could not open iPhone session: \(error.localizedDescription)")
            }
        }
    }

    @objc private func closeSession() {
        Task { [weak self] in
            guard let self else { return }
            if !(await coordinator.closeSession()) {
                state.log("The iPhone automation session did not close cleanly")
            }
        }
    }

    @objc private func setUpAutomation() {
        statusLine.title = "Preparing WebDriverAgent…"
        Task { [weak self] in
            guard let self else { return }
            do {
                let projectURL = try await coordinator.prepareAutomation()
                _ = await MainActor.run {
                    NSWorkspace.shared.open(projectURL)
                }
                state.log(
                    "In Xcode, select WebDriverAgentRunner → Signing & Capabilities, "
                        + "choose your team, then run it once on the connected iPhone"
                )
            } catch {
                state.log("Could not prepare WebDriverAgent: \(error.localizedDescription)")
            }
        }
    }

    @objc private func requestPermissions() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        state.status(
            phase: "permission",
            message: "Complete the one-time macOS permissions, then relaunch Mirror Relay",
            screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
            accessibilityAuthorized: AXIsProcessTrusted()
        )
    }

    private func requestMissingPermissions() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        if !AXIsProcessTrusted() {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            updateLoginItem()
        } catch {
            state.log("Could not change launch-at-login setting: \(error.localizedDescription)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func installMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(
            systemSymbolName: "iphone.gen3.radiowaves.left.and.right",
            accessibilityDescription: "Mirror Relay"
        ) {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "MR"
        }

        let menu = NSMenu()
        statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        permissionsLine = NSMenuItem(title: "Permissions: checking", action: nil, keyEquivalent: "")
        permissionsLine.isEnabled = false
        menu.addItem(permissionsLine)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Open Dashboard",
            action: #selector(openDashboard),
            keyEquivalent: "o"
        ).target = self
        menu.addItem(
            withTitle: "Open iPhone Session",
            action: #selector(openSession),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Close iPhone Session",
            action: #selector(closeSession),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Set Up WebDriverAgent Fallback…",
            action: #selector(setUpAutomation),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Grant Mirroring Permissions…",
            action: #selector(requestPermissions),
            keyEquivalent: ""
        ).target = self
        loginItem = menu.addItem(
            withTitle: "Launch at Login",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.isEnabled = Bundle.main.bundleURL.pathExtension == "app"
        updateLoginItem()
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Mirror Relay",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self
        statusItem.menu = menu
    }

    private func updateMenu(_ snapshot: BrokerSnapshot) {
        statusLine.title = "\(friendlyPhase(snapshot.phase)) · \(snapshot.fps) fps"
        if snapshot.transport == "webdriveragent" {
            permissionsLine.title = "Transport: WebDriverAgent"
        } else {
            permissionsLine.title = [
                snapshot.screenCaptureAuthorized ? "Screen ✓" : "Screen ✕",
                snapshot.accessibilityAuthorized ? "Control ✓" : "Control ✕"
            ].joined(separator: " · ")
        }
        statusItem.button?.toolTip = "Mirror Relay — \(snapshot.message)"
    }

    private func updateLoginItem() {
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func enableLaunchAtLoginForInstalledApp() {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            return
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            state.log("Launch at Login enabled")
        case .requiresApproval:
            state.log("Launch at Login requires approval in System Settings")
        case .notRegistered, .notFound:
            do {
                try SMAppService.mainApp.register()
                updateLoginItem()
                state.log(
                    "Launch at Login \(SMAppService.mainApp.status == .enabled ? "enabled" : "registered")"
                )
            } catch {
                state.log("Could not enable Launch at Login: \(error.localizedDescription)")
            }
        @unknown default:
            state.log("Launch at Login status is unknown")
        }
    }

    private func friendlyPhase(_ phase: String) -> String {
        switch phase {
        case "streaming": return "Connected"
        case "binding": return "Binding"
        case "permission": return "Needs permission"
        case "waiting": return "Waiting for iPhone"
        case "reconnecting": return "Reconnecting"
        case "starting": return "Starting"
        case "launching": return "Launching WDA"
        case "setup": return "Setup needed"
        default: return phase.capitalized
        }
    }

    private static func publicDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["MIRROR_RELAY_PUBLIC_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent(
            "public",
            isDirectory: true
        ), FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent("public", isDirectory: true)
    }
}
