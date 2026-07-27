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

enum NudgeInvocation: Hashable, Codable, Sendable {
    case temporal
    case contextual(ContextKind)
}

enum TriggerSource: String, Codable, Sendable {
    case inferred
    case explicit
}

enum ContextKind: String, Codable, CaseIterable, Sendable {
    case application
    case messaging
    case onlineShopping
    case calendar
    case browser
    case productivity

    var label: String {
        switch self {
        case .application: "Application"
        case .messaging: "Messaging"
        case .onlineShopping: "Shopping online"
        case .calendar: "Calendar"
        case .browser: "Browser"
        case .productivity: "Working"
        }
    }

    var symbol: String {
        switch self {
        case .application: "app.fill"
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
    let applicationName: String?

    init(
        id: UUID = UUID(),
        kind: ContextKind,
        identifiers: [String],
        confidence: Double,
        source: TriggerSource,
        applicationName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.identifiers = identifiers
        self.confidence = confidence
        self.source = source
        self.applicationName = applicationName
    }
}

enum NudgeCondition: Hashable, Codable, Sendable {
    case applicationActivated(bundleIdentifier: String, applicationName: String)
    case context(ContextTrigger)
    case urlDomain(String)

    var label: String {
        switch self {
        case .applicationActivated(_, let applicationName):
            "When \(applicationName) is active"
        case .context(let trigger):
            trigger.kind.label
        case .urlDomain(let domain):
            "When visiting \(domain)"
        }
    }

    var kind: ContextKind {
        switch self {
        case .applicationActivated:
            .application
        case .context(let trigger):
            trigger.kind
        case .urlDomain:
            .browser
        }
    }

    func matches(_ event: ContextEvent) -> Bool {
        switch self {
        case .applicationActivated(let bundleIdentifier, _):
            event.identifiers.contains(bundleIdentifier)
        case .context(let trigger):
            ContextInferenceEngine.matches(event, trigger: trigger)
        case .urlDomain(let domain):
            event.identifiers.contains(domain)
        }
    }

    var legacyTrigger: ContextTrigger {
        switch self {
        case .applicationActivated(let bundleIdentifier, let applicationName):
            ContextTrigger(
                kind: .application,
                identifiers: [bundleIdentifier],
                confidence: 1,
                source: .explicit,
                applicationName: applicationName
            )
        case .context(let trigger):
            trigger
        case .urlDomain(let domain):
            ContextTrigger(
                kind: .browser,
                identifiers: [domain],
                confidence: 1,
                source: .explicit
            )
        }
    }
}

enum NudgeAction: Hashable, Codable, Sendable {
    case openApplication(
        bundleIdentifier: String,
        applicationName: String,
        applicationURL: URL
    )
    case openURL(URL)
    case none

    var label: String {
        switch self {
        case .openApplication(_, let applicationName, _):
            "Open \(applicationName)"
        case .openURL(let url):
            "Open \(url.host ?? "link")"
        case .none:
            "No action"
        }
    }

    var symbol: String {
        switch self {
        case .openApplication: "arrow.up.forward.app"
        case .openURL: "arrow.up.forward.square"
        case .none: "circle"
        }
    }

    var targetURL: URL? {
        switch self {
        case .openApplication(_, _, let applicationURL): applicationURL
        case .openURL(let url): url
        case .none: nil
        }
    }
}

struct NudgeItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let originalRequest: String
    let title: String
    let detail: String
    let priority: NudgePriority
    let conditions: [NudgeCondition]
    let fallbackAt: Date
    let createdAt: Date
    var status: NudgeStatus
    var surfacedAt: Date?
    var invocation: NudgeInvocation
    let action: NudgeAction
    let canInterruptFocus: Bool

    init(
        id: UUID = UUID(),
        originalRequest: String,
        title: String,
        detail: String,
        priority: NudgePriority = .actionable,
        conditions: [NudgeCondition],
        fallbackAt: Date,
        createdAt: Date = .now,
        status: NudgeStatus = .pending,
        surfacedAt: Date? = nil,
        invocation: NudgeInvocation = .temporal,
        action: NudgeAction = .none,
        canInterruptFocus: Bool = false
    ) {
        self.id = id
        self.originalRequest = originalRequest
        self.title = title
        self.detail = detail
        self.priority = priority
        self.conditions = conditions
        self.fallbackAt = fallbackAt
        self.createdAt = createdAt
        self.status = status
        self.surfacedAt = surfacedAt ?? (status == .active ? createdAt : nil)
        self.invocation = invocation
        self.action = action
        self.canInterruptFocus = canInterruptFocus
    }

    /// Compatibility initializer for the original provider contract and demo data.
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
        let applicationTrigger = triggers.first { $0.kind == .application }
        let decodedConditions = triggers.compactMap { trigger -> NudgeCondition? in
            if
                trigger.kind == .application,
                let bundleIdentifier = trigger.identifiers.first
            {
                return .applicationActivated(
                    bundleIdentifier: bundleIdentifier,
                    applicationName: trigger.applicationName ?? bundleIdentifier
                )
            }
            return .context(trigger)
        }

        let decodedAction: NudgeAction
        if
            let applicationTrigger,
            let bundleIdentifier = applicationTrigger.identifiers.first,
            let primaryURL
        {
            decodedAction = .openApplication(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationTrigger.applicationName ?? bundleIdentifier,
                applicationURL: primaryURL
            )
        } else if let primaryURL {
            decodedAction = .openURL(primaryURL)
        } else {
            decodedAction = .none
        }

        self.init(
            id: id,
            originalRequest: originalRequest,
            title: title,
            detail: detail,
            priority: priority,
            conditions: decodedConditions,
            fallbackAt: fallbackAt,
            createdAt: createdAt,
            status: status,
            surfacedAt: surfacedAt,
            invocation: invocation,
            action: decodedAction,
            canInterruptFocus: canInterruptFocus
        )
    }

    var triggers: [ContextTrigger] {
        conditions.map(\.legacyTrigger)
    }

    var primaryURL: URL? {
        action.targetURL
    }

    var contextLabel: String {
        conditions.first?.label ?? "At a helpful moment"
    }

    var timelineDate: Date {
        surfacedAt ?? createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case originalRequest
        case title
        case detail
        case priority
        case conditions
        case triggers
        case fallbackAt
        case createdAt
        case status
        case surfacedAt
        case invocation
        case action
        case primaryURL
        case canInterruptFocus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        originalRequest = try container.decode(String.self, forKey: .originalRequest)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decode(String.self, forKey: .detail)
        priority = try container.decode(NudgePriority.self, forKey: .priority)
        fallbackAt = try container.decode(Date.self, forKey: .fallbackAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = try container.decode(NudgeStatus.self, forKey: .status)
        surfacedAt = try container.decodeIfPresent(Date.self, forKey: .surfacedAt)
        invocation = try container.decode(NudgeInvocation.self, forKey: .invocation)
        canInterruptFocus = try container.decode(Bool.self, forKey: .canInterruptFocus)

        if let decodedConditions = try container.decodeIfPresent(
            [NudgeCondition].self,
            forKey: .conditions
        ) {
            conditions = decodedConditions
        } else {
            let legacyTriggers = try container.decodeIfPresent(
                [ContextTrigger].self,
                forKey: .triggers
            ) ?? []
            conditions = legacyTriggers.map(NudgeCondition.context)
        }

        if let decodedAction = try container.decodeIfPresent(NudgeAction.self, forKey: .action) {
            action = decodedAction
        } else if let legacyURL = try container.decodeIfPresent(URL.self, forKey: .primaryURL) {
            action = .openURL(legacyURL)
        } else {
            action = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(originalRequest, forKey: .originalRequest)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encode(priority, forKey: .priority)
        try container.encode(conditions, forKey: .conditions)
        try container.encode(fallbackAt, forKey: .fallbackAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(surfacedAt, forKey: .surfacedAt)
        try container.encode(invocation, forKey: .invocation)
        try container.encode(action, forKey: .action)
        try container.encode(canInterruptFocus, forKey: .canInterruptFocus)
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
        identifiers: ["calendar.urgent", "calendar:any"]
    )

    static func activatedApplication(bundleIdentifier: String, name: String) -> ContextEvent {
        let messagingBundleIDs: Set<String> = [
            "com.tinyspeck.slackmacgap",
            "com.apple.MobileSMS",
            "com.microsoft.teams2"
        ]
        let calendarBundleIDs: Set<String> = [
            "com.apple.iCal",
            "com.flexibits.fantastical2.mac",
            "com.microsoft.Outlook"
        ]
        let browserBundleIDs: Set<String> = [
            "com.apple.Safari",
            "com.google.Chrome",
            "company.thebrowser.Browser",
            "org.mozilla.firefox",
            "com.microsoft.edgemac"
        ]
        let productivityBundleIDs: Set<String> = [
            "com.apple.dt.Xcode",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.figma.Desktop",
            "notion.id",
            "com.linear"
        ]

        let kind: ContextKind
        var identifiers: Set<String> = [bundleIdentifier]

        if messagingBundleIDs.contains(bundleIdentifier) {
            kind = .messaging
        } else if calendarBundleIDs.contains(bundleIdentifier) {
            kind = .calendar
            identifiers.insert("calendar:any")
        } else if browserBundleIDs.contains(bundleIdentifier) {
            kind = .browser
            identifiers.insert("context:any-browser")
        } else if productivityBundleIDs.contains(bundleIdentifier) {
            kind = .productivity
            identifiers.insert("context:any-work")
        } else {
            kind = .application
        }

        return ContextEvent(
            id: "app:\(bundleIdentifier)",
            kind: kind,
            label: "\(name) is active",
            identifiers: identifiers
        )
    }
}
