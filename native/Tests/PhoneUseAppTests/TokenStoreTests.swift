import Foundation
import XCTest

@testable import PhoneUseApp

final class TokenStoreTests: XCTestCase {
    func testCreatesAndReusesARestrictedToken() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try TokenStore(baseURL: directory)
        let second = try TokenStore(baseURL: directory)
        let attributes = try FileManager.default.attributesOfItem(atPath: first.fileURL.path)

        XCTAssertEqual(first.token.count, 64)
        XCTAssertEqual(second.token, first.token)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testDashboardBootstrapIsOneShot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TokenStore(baseURL: directory)
        let bootstrap = try store.issueDashboardBootstrap()

        let session = try XCTUnwrap(store.exchangeDashboardBootstrap(bootstrap))
        XCTAssertNil(try store.exchangeDashboardBootstrap(bootstrap))
        XCTAssertTrue(store.dashboardSessionIsValid(session))
    }
}
