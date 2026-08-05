import CoreGraphics
import Testing

@testable import PhoneUseCore

struct HIDEventFactoryTests {
    @Test func normalizedCoordinatesStartAtTheVisibleTopLeft() {
        let bounds = CGRect(x: 2_061, y: 152, width: 354, height: 781)

        #expect(
            HIDEventFactory.screenPoint(
                normalizedX: 0.25,
                normalizedY: 0.75,
                within: bounds
            ) == CGPoint(x: 2_149.5, y: 737.75)
        )
    }

    @Test func buildsGlobalMouseEventAtTheRequestedScreenPoint() throws {
        let point = CGPoint(x: 1_250, y: 300)
        let event = try #require(HIDEventFactory.mouse(phase: .down, at: point))

        #expect(event.type == .leftMouseDown)
        #expect(event.location == point)
        #expect(event.getIntegerValueField(.mouseEventButtonNumber) == 0)
    }

    @Test func buildsContinuousScrollAtTheRequestedScreenPoint() throws {
        let point = CGPoint(x: 150, y: 250)
        let event = try #require(
            HIDEventFactory.scroll(
                deltaX: 5,
                deltaY: 10,
                phase: .changed,
                at: point
            )
        )

        #expect(event.location == point)
        #expect(event.getIntegerValueField(CGEventField(rawValue: 88)!) == 1)
        #expect(event.getIntegerValueField(CGEventField(rawValue: 96)!) == 10)
        #expect(event.getIntegerValueField(CGEventField(rawValue: 97)!) == 5)
        #expect(event.getIntegerValueField(CGEventField(rawValue: 99)!) == 2)
    }
}
