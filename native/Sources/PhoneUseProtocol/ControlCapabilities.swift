public struct ControlCapabilities: Codable, Equatable, Sendable {
    public let pointer: Bool
    public let keyboard: Bool
    public let shortcuts: Bool

    public init(pointer: Bool, keyboard: Bool, shortcuts: Bool) {
        self.pointer = pointer
        self.keyboard = keyboard
        self.shortcuts = shortcuts
    }

    public static let none = ControlCapabilities(
        pointer: false,
        keyboard: false,
        shortcuts: false
    )

    public func supports(_ action: ValidatedControlAction) -> Bool {
        switch action {
        case .tap, .swipe:
            pointer
        case .type:
            keyboard
        case .shortcut:
            shortcuts
        }
    }
}
