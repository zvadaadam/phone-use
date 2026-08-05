import CoreGraphics
import Foundation
import ImageIO

/// A compact, visually tolerant fingerprint for an observed phone frame.
///
/// The token contains one four-bit luminance sample for each cell in an 8x8
/// grid. This keeps the existing 64-character wire shape while allowing the
/// bridge to distinguish a real screen transition from JPEG noise, a blinking
/// caret, or a thumbnail finishing its fade-in.
public enum VisualFrameFingerprint {
    public static let tokenLength = 64
    public static let maximumEquivalentDistance = 12

    public static func token(for encodedImage: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(encodedImage as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        var samples = [UInt8](repeating: 0, count: tokenLength)
        let rendered = samples.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                let context = CGContext(
                    data: baseAddress,
                    width: 8,
                    height: 8,
                    bitsPerComponent: 8,
                    bytesPerRow: 8,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        guard rendered else { return nil }

        return samples.map { String(format: "%x", $0 >> 4) }.joined()
    }

    public static func distance(between left: String, and right: String) -> Int? {
        guard left.count == tokenLength,
            right.count == tokenLength
        else {
            return nil
        }

        var total = 0
        for (leftCharacter, rightCharacter) in zip(left, right) {
            guard let leftValue = leftCharacter.hexDigitValue,
                let rightValue = rightCharacter.hexDigitValue
            else {
                return nil
            }
            total += abs(leftValue - rightValue)
        }
        return total
    }

    public static func isEquivalent(_ left: String, _ right: String) -> Bool {
        guard let distance = distance(between: left, and: right) else {
            return left == right
        }
        return distance <= maximumEquivalentDistance
    }

    public static func isMeaningfullyChanged(_ left: String, _ right: String) -> Bool {
        guard let distance = distance(between: left, and: right) else {
            return left != right
        }
        return distance > maximumEquivalentDistance
    }
}
