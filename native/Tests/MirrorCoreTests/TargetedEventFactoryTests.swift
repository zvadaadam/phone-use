import CoreGraphics
import Testing

@testable import MirrorCore

struct TargetedEventFactoryTests {
    @Test func convertsGlobalPointToWindowCoordinates() {
        let bounds = CGRect(x: 2_061, y: 152, width: 354, height: 781)

        #expect(
            TargetedEventFactory.windowLocation(
                for: CGPoint(x: 2_238, y: 788.5),
                within: bounds
            ) == CGPoint(x: 177, y: 144.5)
        )
    }

    @Test func buildsMouseEventForOneWindow() throws {
        let event = try #require(
            TargetedEventFactory.leftMouse(
                phase: .down,
                for: 42,
                at: CGPoint(x: 1_250, y: 300),
                within: CGRect(x: 1_000, y: 100, width: 500, height: 700)
            )
        )

        #expect(event.type == .leftMouseDown)
        #expect(event.getIntegerValueField(CGEventField(rawValue: 91)!) == 42)
        #expect(event.getIntegerValueField(CGEventField(rawValue: 92)!) == 42)
        #expect(event.getIntegerValueField(.mouseEventButtonNumber) == 0)
        #expect(event.getIntegerValueField(.mouseEventSubtype) == 3)
    }

    @Test func buildsProcessTargetedContinuousScroll() throws {
        let event = try #require(
            TargetedEventFactory.scroll(
                deltaX: 5,
                deltaY: 10,
                phase: .changed,
                for: 99,
                at: CGPoint(x: 150, y: 250),
                within: CGRect(x: 100, y: 200, width: 300, height: 600)
            )
        )

        #expect(event.getIntegerValueField(CGEventField(rawValue: 51)!) == 99)
        #expect(event.getIntegerValueField(CGEventField(rawValue: 88)!) == 1)
        #expect(event.getIntegerValueField(CGEventField(rawValue: 96)!) == 10)
        #expect(event.getIntegerValueField(CGEventField(rawValue: 97)!) == 5)
        #expect(event.getIntegerValueField(CGEventField(rawValue: 99)!) == 2)
    }
}
