import Foundation
import XCTest
@testable import MirrorCore

final class WebDriverAgentLauncherTests: XCTestCase {
    func testExtractsServerURLAcrossXcodeLogNoise() {
        let output = """
        Test Suite started
        ServerURLHere->http://10.0.0.42:8100<-ServerURLHere
        WebDriverAgent is ready
        """
        XCTAssertEqual(
            WebDriverAgentLauncher.serverURL(in: output)?.absoluteString,
            "http://10.0.0.42:8100"
        )
    }

    func testSelectsIPhoneFromCoreDeviceJSON() throws {
        let data = Data(
            """
            {
              "result": {
                "devices": [
                  {
                    "identifier": "mac-id",
                    "hardwareProperties": {"platform": "macOS"}
                  },
                  {
                    "identifier": "coredevice-id",
                    "connectionProperties": {"pairingState": "paired"},
                    "hardwareProperties": {
                      "platform": "iOS",
                      "productType": "iPhone18,1",
                      "udid": "00008150-iphone-udid"
                    }
                  }
                ]
              }
            }
            """.utf8
        )
        XCTAssertEqual(
            try WebDriverAgentLauncher.firstIPhoneIdentifier(in: data),
            "00008150-iphone-udid"
        )
    }

    func testRejectsVisibleButUnpairedIPhone() {
        let data = Data(
            """
            {
              "result": {
                "devices": [
                  {
                    "identifier": "coredevice-id",
                    "connectionProperties": {"pairingState": "unpaired"},
                    "hardwareProperties": {
                      "platform": "iOS",
                      "udid": "00008150-iphone-udid"
                    }
                  }
                ]
              }
            }
            """.utf8
        )
        XCTAssertThrowsError(
            try WebDriverAgentLauncher.firstIPhoneIdentifier(in: data)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("not paired"))
        }
    }

    func testRejectsIPhoneWithoutHardwareUDID() {
        let data = Data(
            """
            {
              "result": {
                "devices": [
                  {
                    "identifier": "coredevice-id",
                    "hardwareProperties": {"platform": "iOS"}
                  }
                ]
              }
            }
            """.utf8
        )
        XCTAssertThrowsError(
            try WebDriverAgentLauncher.firstIPhoneIdentifier(in: data)
        )
    }

    func testRejectsCoreDeviceListWithoutIPhone() {
        let data = Data(
            #"{"result":{"devices":[{"identifier":"mac-id","hardwareProperties":{"platform":"macOS"}}]}}"#
                .utf8
        )
        XCTAssertThrowsError(
            try WebDriverAgentLauncher.firstIPhoneIdentifier(in: data)
        )
    }

    func testXcodebuildUsesExistingSigningWithoutProvisioningMutationFlags() {
        let arguments = WebDriverAgentLauncher.xcodebuildArguments(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            projectURL: URL(fileURLWithPath: "/tmp/WebDriverAgent.xcodeproj"),
            deviceIdentifier: "iphone-id",
            derivedDataURL: URL(fileURLWithPath: "/tmp/WDA DerivedData")
        )
        XCTAssertEqual(arguments.first, "xcodebuild")
        XCTAssertTrue(arguments.contains("id=iphone-id"))
        XCTAssertTrue(arguments.contains("WebDriverAgentRunner"))
        XCTAssertTrue(arguments.contains("test"))
        XCTAssertFalse(arguments.contains("-allowProvisioningUpdates"))
        XCTAssertFalse(arguments.contains("-allowProvisioningDeviceRegistration"))
    }

    func testSummarizesActionableXcodeDiagnostics() {
        let output = """
        Build settings from command line:
        note: Using destination
        error: Signing for "WebDriverAgentRunner" requires a development team.
        ** TEST FAILED **
        """
        XCTAssertEqual(
            WebDriverAgentLauncher.diagnosticSummary(in: output),
            #"error: Signing for "WebDriverAgentRunner" requires a development team."#
        )
    }
}
