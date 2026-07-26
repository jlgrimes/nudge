import Foundation

/// Provider-neutral structured output. Remote LLM providers, local models, and
/// deterministic mocks all return this same shape.
struct InferenceResult: Codable, Equatable, Sendable {
    let title: String
    let detail: String
    let priority: NudgePriority
    let conditions: [NudgeCondition]
    let action: NudgeAction
    let canInterruptFocus: Bool
    let fallbackAt: Date?

    init(
        title: String,
        detail: String,
        priority: NudgePriority,
        conditions: [NudgeCondition],
        action: NudgeAction = .none,
        canInterruptFocus: Bool,
        fallbackAt: Date? = nil
    ) {
        self.title = title
        self.detail = detail
        self.priority = priority
        self.conditions = conditions
        self.action = action
        self.canInterruptFocus = canInterruptFocus
        self.fallbackAt = fallbackAt
    }

    /// Compatibility initializer for existing providers and tests.
    init(
        title: String,
        detail: String,
        priority: NudgePriority,
        triggers: [ContextTrigger],
        primaryURL: URL?,
        canInterruptFocus: Bool,
        fallbackAt: Date? = nil
    ) {
        self.init(
            title: title,
            detail: detail,
            priority: priority,
            conditions: triggers.map(NudgeCondition.context),
            action: primaryURL.map(NudgeAction.openURL) ?? .none,
            canInterruptFocus: canInterruptFocus,
            fallbackAt: fallbackAt
        )
    }

    var triggers: [ContextTrigger] {
        conditions.map(\.legacyTrigger)
    }

    var primaryURL: URL? {
        guard case .openURL(let url) = action else { return nil }
        return url
    }

    func targeting(_ application: InstalledApplicationDescriptor) -> InferenceResult {
        InferenceResult(
            title: title,
            detail: "When \(application.name) is active",
            priority: priority,
            conditions: [
                .applicationActivated(
                    bundleIdentifier: application.bundleIdentifier,
                    applicationName: application.name
                )
            ],
            action: .openApplication(
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.name
            ),
            canInterruptFocus: canInterruptFocus,
            fallbackAt: fallbackAt
        )
    }
}

/// Deterministic parser used by MockLLMInferenceProvider. Matching stays here
/// because it is application domain logic, not provider-specific behavior.
enum ContextInferenceEngine {
    private static let messagingIdentifiers = [
        "com.tinyspeck.slackmacgap",
        "com.apple.MobileSMS",
        "com.microsoft.teams2",
        "slack.com",
        "messages.google.com"
    ]

    private static let shoppingIdentifiers = [
        "amazon.com",
        "ebay.com",
        "walmart.com",
        "etsy.com",
        "target.com"
    ]

    private static let calendarIdentifiers = [
        "calendar:any",
        "com.apple.iCal",
        "com.flexibits.fantastical2.mac",
        "com.microsoft.Outlook"
    ]

    private static let browserIdentifiers = [
        "context:any-browser",
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.microsoft.edgemac"
    ]

    static func infer(from request: String) -> InferenceResult {
        let normalized = request
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^(hey\s+)?(nudge,?\s+)?(please\s+)?remind me to\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )

        let lowercased = normalized.lowercased()

        if containsAny(lowercased, ["message", "text", "reply", "dm", "send a note"]) {
            let explicitApps = explicitMessagingIdentifiers(in: lowercased)
            let isExplicit = !explicitApps.isEmpty
            return InferenceResult(
                title: sentenceCase(normalized),
                detail: isExplicit ? "When the specified messaging app is active" : "When you’re messaging",
                priority: .actionable,
                triggers: [
                    ContextTrigger(
                        kind: .messaging,
                        identifiers: isExplicit ? explicitApps : messagingIdentifiers,
                        confidence: isExplicit ? 1 : 0.87,
                        source: isExplicit ? .explicit : .inferred
                    )
                ],
                primaryURL: nil,
                canInterruptFocus: false
            )
        }

        if containsAny(lowercased, ["buy", "order", "shop", "purchase", "find a price"]) {
            let explicitDomains = shoppingIdentifiers.filter { lowercased.contains(domainName($0)) }
            let isExplicit = !explicitDomains.isEmpty
            let primaryURL = explicitDomains.first.flatMap { URL(string: "https://\($0)") }
            return InferenceResult(
                title: sentenceCase(normalized),
                detail: isExplicit ? "On the specified store" : "While you’re shopping online",
                priority: .actionable,
                triggers: [
                    ContextTrigger(
                        kind: .onlineShopping,
                        identifiers: isExplicit ? explicitDomains : shoppingIdentifiers,
                        confidence: isExplicit ? 1 : 0.9,
                        source: isExplicit ? .explicit : .inferred
                    )
                ],
                primaryURL: primaryURL,
                canInterruptFocus: false
            )
        }

        if containsAny(lowercased, ["meeting", "appointment", "calendar", "standup", "call starts", "before the call"]) {
            let isUrgent = containsAny(lowercased, ["leave for", "join", "starts", "urgent"])
            return InferenceResult(
                title: sentenceCase(normalized),
                detail: "When your calendar is active",
                priority: isUrgent ? .urgent : .actionable,
                triggers: [
                    ContextTrigger(
                        kind: .calendar,
                        identifiers: calendarIdentifiers,
                        confidence: 0.84,
                        source: .inferred
                    )
                ],
                primaryURL: nil,
                canInterruptFocus: isUrgent
            )
        }

        if containsAny(lowercased, ["look up", "research", "read online", "website", "browse", "check online"]) {
            return InferenceResult(
                title: sentenceCase(normalized),
                detail: "When you’re browsing",
                priority: .actionable,
                triggers: [
                    ContextTrigger(
                        kind: .browser,
                        identifiers: browserIdentifiers,
                        confidence: 0.8,
                        source: .inferred
                    )
                ],
                primaryURL: nil,
                canInterruptFocus: false
            )
        }

        return InferenceResult(
            title: sentenceCase(normalized),
            detail: "At a useful moment while you work",
            priority: .actionable,
            triggers: [
                ContextTrigger(
                    kind: .productivity,
                    identifiers: ["context:any-work"],
                    confidence: 0.58,
                    source: .inferred
                )
            ],
            primaryURL: nil,
            canInterruptFocus: false
        )
    }

    static func matches(_ event: ContextEvent, trigger: ContextTrigger) -> Bool {
        if trigger.kind == .onlineShopping, event.kind == .browser {
            return event.identifiers.contains("context:any-browser")
        }

        if trigger.kind == .application {
            return !event.identifiers.isDisjoint(with: Set(trigger.identifiers))
        }

        guard event.kind == trigger.kind else { return false }
        return !event.identifiers.isDisjoint(with: Set(trigger.identifiers))
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains(where: text.contains)
    }

    private static func explicitMessagingIdentifiers(in text: String) -> [String] {
        var identifiers: [String] = []
        if text.contains("slack") { identifiers.append("com.tinyspeck.slackmacgap") }
        if text.contains("messages") || text.contains("imessage") { identifiers.append("com.apple.MobileSMS") }
        if text.contains("teams") { identifiers.append("com.microsoft.teams2") }
        return identifiers
    }

    private static func domainName(_ domain: String) -> String {
        domain.split(separator: ".").first.map(String.init) ?? domain
    }

    private static func sentenceCase(_ text: String) -> String {
        guard let first = text.first else { return "New nudge" }
        return first.uppercased() + text.dropFirst()
    }
}
