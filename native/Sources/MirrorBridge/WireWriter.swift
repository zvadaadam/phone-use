import Foundation
import MirrorCore

final class WireWriter: BridgeOutput {
    enum Tag: UInt8 {
        case frame = 1
        case status = 2
    }

    private let output = FileHandle.standardOutput
    private let errorOutput = FileHandle.standardError
    private let lock = NSLock()

    func frame(_ data: Data) {
        write(tag: .frame, payload: data)
    }

    func status(_ status: BridgeStatus) {
        guard let data = try? JSONEncoder().encode(status) else {
            log("Could not encode status payload")
            return
        }
        write(tag: .status, payload: data)
    }

    func log(_ message: String) {
        guard let data = "[mirror-bridge] \(message)\n".data(using: .utf8) else { return }
        errorOutput.write(data)
    }

    private func write(tag: Tag, payload: Data) {
        guard payload.count <= Int(UInt32.max) else {
            log("Dropped oversized payload")
            return
        }

        var length = UInt32(payload.count).bigEndian
        var packet = Data([tag.rawValue])
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        packet.append(payload)

        lock.lock()
        defer { lock.unlock() }
        output.write(packet)
    }
}
