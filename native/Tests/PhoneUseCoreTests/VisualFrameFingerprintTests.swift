import CoreGraphics
import Foundation
import XCTest

@testable import PhoneUseCore

final class VisualFrameFingerprintTests: XCTestCase {
    func testTokenUsesStableWireShape() throws {
        let token = try XCTUnwrap(
            VisualFrameFingerprint.token(for: jpeg(fill: 0.25))
        )

        XCTAssertEqual(token.count, 64)
        XCTAssertTrue(token.allSatisfy(\.isHexDigit))
    }

    func testEquivalentFramesTolerateSmallLuminanceDrift() throws {
        let first = try XCTUnwrap(
            VisualFrameFingerprint.token(for: jpeg(fill: 0.25))
        )
        let second = try XCTUnwrap(
            VisualFrameFingerprint.token(for: jpeg(fill: 0.27))
        )

        XCTAssertTrue(VisualFrameFingerprint.isEquivalent(first, second))
        XCTAssertFalse(VisualFrameFingerprint.isMeaningfullyChanged(first, second))
    }

    func testDifferentScreensAreNotEquivalent() throws {
        let dark = try XCTUnwrap(
            VisualFrameFingerprint.token(for: jpeg(fill: 0.05))
        )
        let light = try XCTUnwrap(
            VisualFrameFingerprint.token(for: jpeg(fill: 0.95))
        )

        XCTAssertFalse(VisualFrameFingerprint.isEquivalent(dark, light))
        XCTAssertTrue(VisualFrameFingerprint.isMeaningfullyChanged(dark, light))
    }

    func testEquivalenceAndMeaningfulChangeAreComplements() {
        let baseline = String(repeating: "0", count: 64)
        let equivalent = "c" + String(repeating: "0", count: 63)
        let changed = "d" + String(repeating: "0", count: 63)

        XCTAssertTrue(VisualFrameFingerprint.isEquivalent(baseline, equivalent))
        XCTAssertFalse(
            VisualFrameFingerprint.isMeaningfullyChanged(baseline, equivalent)
        )
        XCTAssertFalse(VisualFrameFingerprint.isEquivalent(baseline, changed))
        XCTAssertTrue(VisualFrameFingerprint.isMeaningfullyChanged(baseline, changed))
    }

    func testRejectsMalformedTokens() {
        XCTAssertNil(
            VisualFrameFingerprint.distance(
                between: "not-a-frame-token",
                and: String(repeating: "0", count: 64)
            )
        )
    }

    private func jpeg(fill: CGFloat) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(
            CGColor(
                colorSpace: colorSpace,
                components: [fill, fill, fill, 1]
            )!
        )
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return JPEGFrameEncoder.encode(context.makeImage()!)!.jpeg
    }
}
