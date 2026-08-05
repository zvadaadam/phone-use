import CoreGraphics

struct PhysicalKeyStroke {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

enum PhysicalKeyMap {
    static func stroke(for character: Character) -> PhysicalKeyStroke? {
        if let keyCode = lowercaseLetters[character] {
            return PhysicalKeyStroke(keyCode: keyCode, flags: [])
        }
        let lowercased = Character(String(character).lowercased())
        if character.isUppercase, let keyCode = lowercaseLetters[lowercased] {
            return PhysicalKeyStroke(keyCode: keyCode, flags: .maskShift)
        }
        if let keyCode = digits[character] {
            return PhysicalKeyStroke(keyCode: keyCode, flags: [])
        }
        if let stroke = punctuation[character] {
            return stroke
        }
        return nil
    }

    private static let lowercaseLetters: [Character: CGKeyCode] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04,
        "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
        "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F,
        "y": 0x10, "t": 0x11, "o": 0x1F, "u": 0x20, "i": 0x22,
        "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D,
        "m": 0x2E
    ]

    private static let digits: [Character: CGKeyCode] = [
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
        "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D
    ]

    private static let punctuation: [Character: PhysicalKeyStroke] = [
        " ": PhysicalKeyStroke(keyCode: 0x31, flags: []),
        "-": PhysicalKeyStroke(keyCode: 0x1B, flags: []),
        "_": PhysicalKeyStroke(keyCode: 0x1B, flags: .maskShift),
        ".": PhysicalKeyStroke(keyCode: 0x2F, flags: []),
        ",": PhysicalKeyStroke(keyCode: 0x2B, flags: []),
        "/": PhysicalKeyStroke(keyCode: 0x2C, flags: []),
        "?": PhysicalKeyStroke(keyCode: 0x2C, flags: .maskShift),
        "@": PhysicalKeyStroke(keyCode: 0x13, flags: .maskShift),
        "\n": PhysicalKeyStroke(keyCode: 0x24, flags: [])
    ]
}
