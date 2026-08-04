import Foundation
import XCTest

@testable import PhoneUseApp

final class TokenStoreMigrationTests: XCTestCase {
    func testMigratesTheLegacyTokenWithoutRotatingIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let legacyDirectory = root.appendingPathComponent("Mirror Relay", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent("Phone Use", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let expectedToken = String(repeating: "a", count: 64)
        let legacyTokenURL = legacyDirectory.appendingPathComponent("token")
        try expectedToken.write(to: legacyTokenURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: legacyTokenURL.path
        )

        let store = try TokenStore(
            baseURL: destinationDirectory,
            legacyBaseURL: legacyDirectory
        )

        XCTAssertEqual(store.token, expectedToken)
        XCTAssertEqual(
            try String(contentsOf: store.fileURL, encoding: .utf8),
            expectedToken
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
