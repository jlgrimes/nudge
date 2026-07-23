import Foundation

struct InferenceResult: Sendable {
    let title: String
    let detail: String
    let priority: NudgePriority
    let triggers: [ContextTrigger]
    let primaryURL: URL?
    let canInterruptFocus: Bool
}

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
            let triggers = [
                ContextTrigger(
                    kind: .messaging,
                    identifiers: isExplicit ? explicitApps : messagingIdentifiers,
                    confidence: isExplicit ? 1 : 0.87,
                    source: isExplicit ? .explicit : .inferred
                )
            ]

            return InferenceResult(
                title: sentenceCase(normalized),
                detail: isExplicit ? "When the specified messaging app is active" : "When you’re messaging",
                priority: .actionable,
                triggers: triggers,
                primaryURL: nil,
                canInterruptFocus: false
            )
        }

        if containsAny(lowercased, ["buy", "order", "shop", "purchase", "find a price"]) {
            let explicitDomains = shoppingIdentifiers.filter { lowercased.contains(domainName($0)) }
            let isExplicit = !explicitDomains.isEmpty
            let triggers = [
                ContextTrigger(
                    kind: .onlineShopping,
                    identifiers: isExplicit ? explicitDomains : shoppingIdentifiers,
                    confidence: isExplicit ? 1 : 0.9,
                    source: isExplicit ? .explicit : .inferred
                )
            ]

            return InferenceResult(
                title: sentenceCase(normalized),
                detail: isExplicit ? "On the specified store" : "While you’re shopping online",
                priority: .actionable,
                triggers: triggers,
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
