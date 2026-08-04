import Foundation
import XCTest

@testable import PhoneUseProtocol

final class PhoneUseProtocolMetadataTests: XCTestCase {
    func testPublishesTheRebrandedRuntimeIdentity() {
        XCTAssertEqual(PhoneUseProtocolMetadata.displayName, "Phone Use")
        XCTAssertEqual(PhoneUseProtocolMetadata.commandName, "phone-use")
        XCTAssertEqual(PhoneUseProtocolMetadata.productIdentifier, "phone-use")
        XCTAssertEqual(PhoneUseProtocolMetadata.applicationSupportDirectoryName, "Phone Use")
        XCTAssertEqual(
            PhoneUseProtocolMetadata.legacyApplicationSupportDirectoryName,
            "Mirror Relay"
        )
        XCTAssertEqual(PhoneUseProtocolMetadata.appBundleIdentifier, "com.adamzvada.mirrorrelay")
    }

    func testFindsApplicationContainingPackagedHelper() {
        let helper = URL(
            fileURLWithPath: "/Applications/Phone Use.app/Contents/Helpers/phone-use"
        )

        XCTAssertEqual(
            PhoneUseProtocolMetadata.enclosingApplication(for: helper)?.path,
            "/Applications/Phone Use.app"
        )
    }

    func testFindsApplicationThroughResolvedHelperSymlink() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let helper = temporaryDirectory.appendingPathComponent(
            "Phone Use.app/Contents/Helpers/phone-use"
        )
        let link = temporaryDirectory.appendingPathComponent("phone-use")
        try FileManager.default.createDirectory(
            at: helper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: helper.path, contents: Data()))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: helper)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        XCTAssertEqual(
            PhoneUseProtocolMetadata.enclosingApplication(for: link)?.path,
            temporaryDirectory.appendingPathComponent("Phone Use.app").path
        )
    }

    func testRejectsExecutableOutsideApplicationBundle() {
        let executable = URL(fileURLWithPath: "/usr/local/bin/phone-use")

        XCTAssertNil(PhoneUseProtocolMetadata.enclosingApplication(for: executable))
    }
}
