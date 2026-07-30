import Foundation
import MirrorCore

protocol PhoneTransport: AnyObject, Sendable {
    var name: String { get }

    func start()
    func stop()
    func isAvailable() async -> Bool
    func ensureSession(timeout: Duration) async throws
    func send(_ command: ControlCommand) async throws
    func sourceJSON() async throws -> Data
    func closeSession() async -> Bool
    func isRunning() async -> Bool
}
