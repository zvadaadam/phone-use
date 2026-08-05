public struct InputDelivery: Equatable, Sendable {
    public let completed: Bool
    public let eventPosted: Bool
    public let focusPreserved: Bool

    public init(
        completed: Bool,
        eventPosted: Bool,
        focusPreserved: Bool
    ) {
        self.completed = completed
        self.eventPosted = eventPosted
        self.focusPreserved = focusPreserved
    }

    public static let rejected = InputDelivery(
        completed: false,
        eventPosted: false,
        focusPreserved: true
    )
}
