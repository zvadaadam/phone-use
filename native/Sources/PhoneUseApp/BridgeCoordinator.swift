import Foundation
import PhoneUseProtocol

actor BridgeCoordinator {
    let state: BrokerState
    private let transport: any DeviceHubTransporting

    init(
        state: BrokerState,
        transport: any DeviceHubTransporting = IOS27DeviceHubTransport()
    ) {
        self.state = state
        self.transport = transport
    }

    func start() async {
        state.update(await transport.start())
        state.log("Device Hub transport selected; GUI automation is not available")
    }

    func stop() async {
        state.update(await transport.stop())
    }

    func connect() async throws {
        do {
            state.update(try await transport.connect())
        } catch {
            state.log("Device Hub connect failed: \(error.localizedDescription)")
            throw error
        }
    }

    func disconnect() async {
        state.update(await transport.disconnect())
    }

    func observe() async throws -> DeviceObservation {
        try await transport.observe()
    }

    func perform(_ command: ValidatedControlCommand) async throws -> DeviceActionReceipt {
        let receipt = try await transport.perform(command)
        guard receipt.delivered, receipt.verified, !receipt.macFocusChanged else {
            throw DeviceHubTransportError.backendUnvalidated
        }
        return receipt
    }
}
