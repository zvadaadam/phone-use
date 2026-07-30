import Darwin
import Foundation
import Security

final class TokenStore: @unchecked Sendable {
    private static let bootstrapLifetime: TimeInterval = 60
    static let dashboardSessionLifetime: TimeInterval = 8 * 60 * 60

    let token: String
    let fileURL: URL

    private let lock = NSLock()
    private var bootstraps: [String: Date] = [:]
    private var dashboardSessions: [String: Date] = [:]

    init(baseURL: URL? = nil) throws {
        let fileManager = FileManager.default
        let directory =
            try baseURL
            ?? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Mirror Relay", isDirectory: true)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Self.validateOwnedItem(
            at: directory,
            expectedType: .typeDirectory,
            fileManager: fileManager
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        fileURL = directory.appendingPathComponent("token", isDirectory: false)
        if fileManager.fileExists(atPath: fileURL.path) {
            try Self.validateOwnedItem(
                at: fileURL,
                expectedType: .typeRegular,
                fileManager: fileManager
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        }

        if let existing = try? String(contentsOf: fileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            Self.isValidToken(existing)
        {
            token = existing
            return
        }

        token = try Self.randomToken()
        try token.write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    func issueDashboardBootstrap() throws -> String {
        let value = try Self.randomToken()
        lock.lock()
        defer { lock.unlock() }
        pruneExpired(now: Date())
        bootstraps[value] = Date().addingTimeInterval(Self.bootstrapLifetime)
        return value
    }

    func exchangeDashboardBootstrap(_ value: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        pruneExpired(now: now)
        guard let expiry = bootstraps.removeValue(forKey: value),
            expiry > now
        else {
            return nil
        }
        let session = try Self.randomToken()
        dashboardSessions[session] = now.addingTimeInterval(Self.dashboardSessionLifetime)
        return session
    }

    func dashboardSessionIsValid(_ value: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        pruneExpired(now: now)
        return dashboardSessions[value].map { $0 > now } ?? false
    }

    private func pruneExpired(now: Date) {
        bootstraps = bootstraps.filter { $0.value > now }
        dashboardSessions = dashboardSessions.filter { $0.value > now }
    }

    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw TokenError("Could not create a secure local API token")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func isValidToken(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    private static func validateOwnedItem(
        at url: URL,
        expectedType: FileAttributeType,
        fileManager: FileManager
    ) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == expectedType else {
            throw TokenError("Security-sensitive path is not a regular \(expectedType.rawValue)")
        }
        let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
        guard owner == getuid() else {
            throw TokenError("Security-sensitive path is not owned by the current user")
        }
    }
}

struct TokenError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
