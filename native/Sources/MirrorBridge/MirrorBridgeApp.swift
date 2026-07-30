import ApplicationServices
import CoreGraphics
import Foundation
import MirrorCore

@main
struct MirrorBridgeApp {
    static func main() async {
        if CommandLine.arguments.contains("--request-permissions") {
            requestPermissions()
            return
        }

        let writer = WireWriter()
        let target = WindowTarget()
        let capture = MirrorCapture(output: writer, target: target)
        let input = InputController(output: writer, target: target)
        input.startReadingStdin()
        await capture.run()
    }

    private static func requestPermissions() {
        let screenCaptureAuthorized = CGPreflightScreenCaptureAccess()
            || CGRequestScreenCaptureAccess()

        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        let accessibilityAuthorized = AXIsProcessTrustedWithOptions(options)

        print("Screen Recording: \(screenCaptureAuthorized ? "authorized" : "requested")")
        print("Accessibility: \(accessibilityAuthorized ? "authorized" : "requested")")
        print("Restart Mirror Relay after granting permissions.")
    }
}
