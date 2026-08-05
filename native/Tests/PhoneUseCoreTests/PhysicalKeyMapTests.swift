import CoreGraphics
import Testing

@testable import PhoneUseCore

struct PhysicalKeyMapTests {
    @Test func mapsSearchTextToPhysicalKeys() throws {
        let text = "Stress Test"
        let strokes = try text.map { character in
            try #require(PhysicalKeyMap.stroke(for: character))
        }

        #expect(strokes.count == text.count)
        #expect(strokes[0].keyCode == 0x01)
        #expect(strokes[0].flags == .maskShift)
        #expect(strokes[1].keyCode == 0x11)
        #expect(strokes[1].flags.isEmpty)
    }

    @Test func rejectsCharactersWithoutAnHonestPhysicalMapping() {
        #expect(PhysicalKeyMap.stroke(for: "🙂") == nil)
    }
}
