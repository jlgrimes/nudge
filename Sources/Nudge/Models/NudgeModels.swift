import Foundation

enum NudgePriority: String, Codable, CaseIterable, Sendable {
    case urgent
    case actionable
    case informational
}

enum NudgeStatus: String, Codable, Sendable {
    case pending
    case active
    case deferred
    case completed
    case dismissed
    case expired
}

enum NudgeInvocation: Hashable, Sendable {
    case temporal
    case contextual(ContextKind)
}

enum TriggerSource: String, Codable, Sendable {
    case inferred
    case explicit
}

enum ContextKind: String, Codable, CaseIterable, Sendable {
    case messaging
    case onlineShopping
    case calendar
    case browser
    case productivity

    var label: String {
        switch self {
        case .messaging: "Messaging"
        case .onlineShopping: "Shopping online"
        case .calendar: "Calendar"
        case .browser: "Browser"
        case .productivity: "Working"
        }
    }

    var symbol: String {
        switch self {
        case .messaging: "message.fill"
        case .onlineShopping: "cart.fill"
        case .calendar: "calendar"
        case .browser: "safari.fill"
        case .productivity: "sparkles"
        }
    }
}

struct ContextTrigger: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let kind: ContextKind
    let identifiers: [String]
    let confidence: Double
    let source: TriggerSource

    init(
        id: UUID = UUID(),
        kind: ContextKind,
        identifiers: [String],
        confidence: Double,
        source: TriggerSource
    ) {
        self.id = id
        self.kind = kind
        self.identifiers = identifiers
        self.confidence = confidence
        self.source = source
    }
}

struct NudgeItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let originalRequest: String
    let title: String
    let detail: String
    let priority: NudgePriority
    let triggers: [ContextTrigger]
    let fallbackAt: Date
    let createdAt: Date
    var status: NudgeStatus
    var surfacedAt: Date?
    var invocation: NudgeInvocation
    let primaryURL: URL?
    let canInterruptFocus: Bool

    init(
        id: UUID = UUID(),
        originalRequest: String,
        title: String,
        detail: String,
        priority: NudgePriority = .actionable,
        triggers: [ContextTrigger],
        fallbackAt: Date,
        createdAt: Date = .now,
        status: NudgeStatus = .pending,
        surfacedAt: Date? = nil,
        invocation: NudgeInvocation = .temporal,
        primaryURL: URL? = nil,
        canInterruptFocus: Bool = false
    ) {
        self.id = id
        self.originalRequest = originalRequest
        self.title = title
        self.detail = detail
        self.priority = priority
        self.triggers = triggers
        self.fallbackAt = fallbackAt
        self.createdAt = createdAt
        self.status = status
        self.surfacedAt = surfacedAt ?? (status == .active ? createdAt : nil)
        self.invocation = invocation
        self.primaryURL = primaryURL
        self.canInterruptFocus = canInterruptFocus
    }

    var contextLabel: String {
        triggers.first?.kind.label ?? "At a helpful moment"
    }

    var timelineDate: Date {
        surfacedAt ?? createdAt
    }
}

struct ContextEvent: Identifiable, Hashable, Sendable {
    let id: String
    let kind: ContextKind
    let label: String
    let identifiers: Set<String>

    static let slack = ContextEvent(
        id: "slack",
        kind: .messaging,
        label: "Slack is active",
        identifiers: ["com.tinyspeck.slackmacgap", "slack.com"]
    )

    static let messages = ContextEvent(
        id: "messages",
        kind: .messaging,
        label: "Messages is active",
        identifiers: ["com.apple.MobileSMS"]
    )

    static let amazon = ContextEvent(
        id: "amazon",
        kind: .onlineShopping,
        label: "Shopping on amazon.com",
        identifiers: ["amazon.com"]
    )

    static let calendar = ContextEvent(
        id: "calendar",
        kind: .calendar,
        label: "A meeting starts soon",
        identifiers: ["calendar.urgent"]
    )

    static func activatedApplication(bundleIdentifier: String, name: String) -> ContextEvent? {
        let messagingBundleIDs: Set<String> = [
            "com.tinyspeck.slackmacgap",
            "com.apple.MobileSMS",
            "com.microsoft.teams2"
        ]

        if messagingBundleIDs.contains(bundleIdentifier) {
            return ContextEvent(
                id: "app:\(bundleIdentifier)",
                kind: .messaging,
                label: "\(name) is active",
                identifiers: [bundleIdentifier]
            )
        }

        return nil
    }
}
