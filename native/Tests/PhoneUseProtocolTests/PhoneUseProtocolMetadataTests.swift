import Foundation
import XCTest

@testable import PhoneUseProtocol

final class PhoneUseProtocolMetadataTests: XCTestCase {
    func testPublishesCurrentRuntimeIdentity() {
        XCTAssertEqual(PhoneUseProtocolMetadata.displayName, "Phone Use")
        XCTAssertEqual(PhoneUseProtocolMetadata.commandName, "phone-use")
        XCTAssertEqual(PhoneUseProtocolMetadata.productIdentifier, "phone-use")
        XCTAssertEqual(PhoneUseProtocolMetadata.currentVersion, 4)
        XCTAssertEqual(PhoneUseProtocolMetadata.appBundleIdentifier, "com.adamzvada.phoneuse")
    }

    func testBuildsCanonicalTokenPath() {
        let root = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        XCTAssertEqual(
            PhoneUseProtocolMetadata.tokenFile(in: root).path,
            "/tmp/Application Support/Phone Use/token"
        )
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

    func testRejectsExecutableOutsideApplicationBundle() {
        XCTAssertNil(
            PhoneUseProtocolMetadata.enclosingApplication(
                for: URL(fileURLWithPath: "/usr/local/bin/phone-use")
            )
        )
    }
}
