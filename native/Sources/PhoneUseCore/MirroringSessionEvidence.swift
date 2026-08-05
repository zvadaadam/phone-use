import Foundation

public enum MirroringSessionEvidence {
    public struct Element: Sendable, Equatable {
        public let identifier: String?
        public let role: String?
        public let title: String?
        public let description: String?
        public let isEnabled: Bool
        public let isHidden: Bool
        public let children: [Element]

        public init(
            identifier: String? = nil,
            role: String? = nil,
            title: String? = nil,
            description: String? = nil,
            isEnabled: Bool = true,
            isHidden: Bool = false,
            children: [Element] = []
        ) {
            self.identifier = identifier
            self.role = role
            self.title = title
            self.description = description
            self.isEnabled = isEnabled
            self.isHidden = isHidden
            self.children = children
        }
    }

    public enum Classification: Sendable, Equatable {
        case candidateLive
        case paused
        case indeterminate
    }

    private static let connectedControlIdentifiers: Set<String> = [
        "app.grid.3x3",
        "iphone.app.switcher"
    ]
    private static let reconnectButtonLabels: Set<String> = [
        "connect",
        "resume",
        "try again"
    ]
    private static let pausedStatusFragments = [
        "connecting to iphone",
        "connection paused",
        "iphone in use",
        "iphone not found",
        "unable to connect"
    ]

    public static func classify(
        root: Element,
        maximumDepth: Int = 8,
        hadReadFailure: Bool = false
    ) -> Classification {
        guard !hadReadFailure else { return .indeterminate }
        let evidence = collectEvidence(
            from: root,
            depth: 0,
            maximumDepth: maximumDepth,
            ancestorsAreUsable: true
        )
        if evidence.hasPausedAction || evidence.hasPausedStatus {
            return .paused
        }
        if evidence.hasConnectedControl || !evidence.hasMeaningfulDescendant {
            return .candidateLive
        }
        return .indeterminate
    }

    private struct Evidence {
        var hasConnectedControl = false
        var hasPausedAction = false
        var hasPausedStatus = false
        var hasMeaningfulDescendant = false

        mutating func merge(_ other: Evidence) {
            hasConnectedControl = hasConnectedControl || other.hasConnectedControl
            hasPausedAction = hasPausedAction || other.hasPausedAction
            hasPausedStatus = hasPausedStatus || other.hasPausedStatus
            hasMeaningfulDescendant =
                hasMeaningfulDescendant
                || other.hasMeaningfulDescendant
        }
    }

    private static func collectEvidence(
        from element: Element,
        depth: Int,
        maximumDepth: Int,
        ancestorsAreUsable: Bool
    ) -> Evidence {
        guard depth < maximumDepth else {
            return Evidence(hasMeaningfulDescendant: true)
        }
        let isUsable = ancestorsAreUsable && element.isEnabled && !element.isHidden
        var evidence = Evidence(
            hasConnectedControl: isUsable
                && element.identifier.map(connectedControlIdentifiers.contains) == true,
            hasPausedAction: isUsable && isReconnectAction(element),
            hasPausedStatus: isUsable && isPausedStatus(element),
            hasMeaningfulDescendant: depth > 0 && isUsable && isMeaningful(element)
        )
        for child in element.children {
            evidence.merge(
                collectEvidence(
                    from: child,
                    depth: depth + 1,
                    maximumDepth: maximumDepth,
                    ancestorsAreUsable: isUsable
                )
            )
        }
        return evidence
    }

    public static func isReconnectAction(_ element: Element) -> Bool {
        guard element.role == "AXButton", element.isEnabled, !element.isHidden else {
            return false
        }
        return [element.title, element.description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains(where: reconnectButtonLabels.contains)
    }

    private static func isPausedStatus(_ element: Element) -> Bool {
        guard element.role == "AXStaticText" else { return false }
        return [element.title, element.description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains { value in
                pausedStatusFragments.contains { value.contains($0) }
            }
    }

    private static func isMeaningful(_ element: Element) -> Bool {
        if element.role == "AXButton" || element.role == "AXStaticText" {
            return true
        }
        return [element.identifier, element.title, element.description]
            .contains { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
    }
}

public struct MirroringSessionReadiness: Sendable {
    public let requiredConsecutiveSamples: Int
    private var consecutiveSamples = 0
    private var hasConfirmedLiveSession = false

    public init(requiredConsecutiveSamples: Int = 5) {
        precondition(requiredConsecutiveSamples > 0)
        self.requiredConsecutiveSamples = requiredConsecutiveSamples
    }

    public mutating func observe(
        _ classification: MirroringSessionEvidence.Classification,
        captureIsReady: Bool
    ) -> Bool {
        switch classification {
        case .candidateLive where captureIsReady:
            consecutiveSamples += 1
            if consecutiveSamples >= requiredConsecutiveSamples {
                hasConfirmedLiveSession = true
            }
            return hasConfirmedLiveSession
        case .indeterminate where captureIsReady:
            consecutiveSamples = 0
            return hasConfirmedLiveSession
        default:
            reset()
            return false
        }
    }

    public mutating func reset() {
        consecutiveSamples = 0
        hasConfirmedLiveSession = false
    }
}
