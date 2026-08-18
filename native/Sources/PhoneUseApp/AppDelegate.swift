import AppKit
import Foundation
import PhoneUseProtocol
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let productName = PhoneUseProtocolMetadata.displayName

    private var state: BrokerState!
    private var coordinator: BridgeCoordinator!
    private var server: LocalHTTPServer!
    private var tokenStore: TokenStore!
    private var statusObserverID: UUID?
    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var runtimeLine: NSMenuItem!
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
            try server.start()
            let coordinator = coordinator!
            Task { await coordinator.start() }
            statusObserverID = state.observeStatus { [weak self] snapshot in
                Task { @MainActor [weak self] in self?.updateMenu(snapshot) }
            }
        } catch {
            FileHandle.standardError.write(
                Data("[\(Self.productName)] Startup failed: \(error)\n".utf8)
            )
            let alert = NSAlert()
            alert.messageText = "\(Self.productName) could not start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusObserverID { state.removeStatusObserver(statusObserverID) }
        server?.stop()
        if let coordinator { Task { await coordinator.stop() } }
    }

    @objc private func openDashboard() {
        guard let bootstrap = try? tokenStore.issueDashboardBootstrap(),
            let url = URL(
                string: "http://127.0.0.1:\(LocalHTTPServer.port)"
                    + "/auth/dashboard?bootstrap=\(bootstrap)"
            )
        else {
            state.log("Could not create a secure dashboard session")
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func connectDevice() {
        Task { [weak self] in
            do {
                try await self?.coordinator.connect()
            } catch {
                self?.state.log("Could not connect Device Hub: \(error.localizedDescription)")
            }
        }
    }

    @objc private func disconnectDevice() {
        Task { [weak self] in await self?.coordinator.disconnect() }
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
            accessibilityDescription: Self.productName
        ) {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "PU"
        }

        let menu = NSMenu()
        statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        runtimeLine = NSMenuItem(title: "iOS 27 Device Hub", action: nil, keyEquivalent: "")
        runtimeLine.isEnabled = false
        menu.addItem(runtimeLine)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Open Dashboard",
            action: #selector(openDashboard),
            keyEquivalent: "o"
        ).target = self
        menu.addItem(
            withTitle: "Connect Device",
            action: #selector(connectDevice),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Disconnect Device",
            action: #selector(disconnectDevice),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
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
            withTitle: "Quit \(Self.productName)",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self
        statusItem.menu = menu
    }

    private func updateMenu(_ status: PhoneUseStatus) {
        statusLine.title = friendlyPhase(status.phase)
        runtimeLine.title = "iOS \(status.requirements.minimumIOSVersion)+ · \(status.proof.rawValue)"
        statusItem.button?.toolTip = "\(Self.productName) — \(status.message)"
    }

    private func updateLoginItem() {
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func enableLaunchAtLoginForInstalledApp() {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }
        switch SMAppService.mainApp.status {
        case .enabled:
            state.log("Launch at Login enabled")
        case .requiresApproval:
            state.log("Launch at Login requires approval in System Settings")
        case .notRegistered, .notFound:
            do {
                try SMAppService.mainApp.register()
                updateLoginItem()
                state.log("Launch at Login registered")
            } catch {
                state.log("Could not enable Launch at Login: \(error.localizedDescription)")
            }
        @unknown default:
            state.log("Launch at Login status is unknown")
        }
    }

    private func friendlyPhase(_ phase: DeviceHubPhase) -> String {
        switch phase {
        case .unavailable: "Device Hub unavailable"
        case .waitingForDevice: "Waiting for iPhone"
        case .connecting: "Connecting"
        case .streaming: "Connected"
        case .stopped: "Stopped"
        }
    }

    private static func publicDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["PHONE_USE_PUBLIC_DIR"] {
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
