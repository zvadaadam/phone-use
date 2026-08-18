import Foundation
import XCTest

@testable import PhoneUseApp
@testable import PhoneUseProtocol

final class DeviceHubTransportTests: XCTestCase {
    func testProductionTransportFailsClosedUntilPhysicalProofExists() async {
        let transport = IOS27DeviceHubTransport()

        let status = await transport.start()
        XCTAssertEqual(status.phase, .unavailable)
        XCTAssertEqual(status.proof, .unimplemented)
        XCTAssertEqual(status.controlCapabilities, .none)

        do {
            _ = try await transport.observe()
            XCTFail("Observation must not succeed before the backend is validated")
        } catch {
            XCTAssertEqual(error as? DeviceHubTransportError, .backendUnvalidated)
        }
    }

    func testCoordinatorPublishesOnlyDeviceHubRuntime() async {
        let state = BrokerState()
        let coordinator = BridgeCoordinator(state: state)

        await coordinator.start()

        let status = state.snapshot()
        XCTAssertEqual(status.transport, "ios27-device-hub")
        XCTAssertEqual(status.phase, .unavailable)
        XCTAssertEqual(status.proof, .unimplemented)
        XCTAssertFalse(status.internetRelayAvailable)
        XCTAssertEqual(status.macFocusPolicy, "never-change-mac-focus")
    }
}
