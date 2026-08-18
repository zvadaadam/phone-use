import Foundation
import XCTest

@testable import PhoneUseProtocol

final class DeviceHubProtocolTests: XCTestCase {
    func testIOS27RequirementsAreExplicit() {
        XCTAssertEqual(DeviceHubRequirements.ios27.minimumIOSVersion, "27.0")
        XCTAssertTrue(DeviceHubRequirements.ios27.physicalDeviceRequired)
        XCTAssertTrue(DeviceHubRequirements.ios27.developerModeRequired)
    }

    func testStatusRoundTripsWithoutInventingCapabilities() throws {
        let status = PhoneUseStatus(
            product: "phone-use",
            version: "development",
            protocolVersion: 4,
            transport: "ios27-device-hub",
            phase: .unavailable,
            proof: .unimplemented,
            message: "Not validated",
            requirements: .ios27,
            controlCapabilities: .none,
            frame: nil,
            macFocusPolicy: "never-change-mac-focus",
            internetRelayAvailable: false,
            logs: []
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                PhoneUseStatus.self,
                from: JSONEncoder().encode(status)
            ),
            status
        )
    }

    func testActionReceiptIsTheCanonicalWireContract() throws {
        let receipt = DeviceActionReceipt(
            delivered: true,
            verified: true,
            macFocusChanged: false,
            beforeFrameID: 41,
            afterFrameID: 42,
            message: "Verified"
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                DeviceActionReceipt.self,
                from: JSONEncoder().encode(receipt)
            ),
            receipt
        )
    }
}
