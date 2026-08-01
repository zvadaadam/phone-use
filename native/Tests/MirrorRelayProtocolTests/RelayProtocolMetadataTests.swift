import Foundation
import XCTest

@testable import MirrorRelayProtocol

final class RelayProtocolMetadataTests: XCTestCase {
    func testFindsApplicationContainingPackagedHelper() {
        let helper = URL(
            fileURLWithPath: "/Applications/Mirror Relay.app/Contents/Helpers/mirror-relay"
        )

        XCTAssertEqual(
            RelayProtocolMetadata.enclosingApplication(for: helper)?.path,
            "/Applications/Mirror Relay.app"
        )
    }

    func testFindsApplicationThroughResolvedHelperSymlink() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let helper = temporaryDirectory.appendingPathComponent(
            "Mirror Relay.app/Contents/Helpers/mirror-relay"
        )
        let link = temporaryDirectory.appendingPathComponent("mirror-relay")
        try FileManager.default.createDirectory(
            at: helper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: helper.path, contents: Data()))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: helper)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        XCTAssertEqual(
            RelayProtocolMetadata.enclosingApplication(for: link)?.path,
            temporaryDirectory.appendingPathComponent("Mirror Relay.app").path
        )
    }

    func testRejectsExecutableOutsideApplicationBundle() {
        let executable = URL(fileURLWithPath: "/usr/local/bin/mirror-relay")

        XCTAssertNil(RelayProtocolMetadata.enclosingApplication(for: executable))
    }
}
