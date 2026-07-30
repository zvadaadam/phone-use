import XCTest

@testable import MirrorCore

final class AsyncMutexTests: XCTestCase {
    func testSerializesConcurrentOperations() async throws {
        let mutex = AsyncMutex()
        let recorder = Recorder()

        async let first: Void = mutex.withLock {
            await recorder.append("first-start")
            try await Task.sleep(for: .milliseconds(40))
            await recorder.append("first-end")
        }
        try await Task.sleep(for: .milliseconds(5))
        async let second: Void = mutex.withLock {
            await recorder.append("second-start")
            await recorder.append("second-end")
        }

        _ = try await (first, second)
        let values = await recorder.values
        XCTAssertEqual(
            values,
            ["first-start", "first-end", "second-start", "second-end"]
        )
    }
}

private actor Recorder {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}
