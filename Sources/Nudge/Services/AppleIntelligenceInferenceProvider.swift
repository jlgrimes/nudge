import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleIntelligenceDraft: Equatable, Sendable {
    enum Priority: String, Equatable, Sendable {
        case urgent
        case actionable
        case informational
    }

    enum Context: String, Equatable, Sendable {
        case messaging
        case onlineShopping
        case calendar
        case browser
        case productivity
    }

    enum Source: String, Equatable, Sendable {
        case inferred
        case explicit
    }

    let title: String
    let detail: String
    let priority: Priority
    let context: Context
    let identifiers: [String]
    let source: Source
    let confidence: Double
    let hasPrimaryURL: Bool
    let primaryURL: String
    let canInterruptFocus: Bool
    let hasExplicitFallback: Bool
    let fallbackDelayMinutes: Int
}

enum AppleIntelligenceInferenceError: LocalizedError, Equatable {
    case unavailable(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            "Apple Intelligence is unavailable: \(reason)"
        case .invalidOutput(let reason):
            "Apple Intelligence returned an invalid nudge: \(reason)"
        }
    }
}

struct AppleIntelligenceInferenceProvider: NudgeInferenceProvider {
    let id = "apple-intelligence-on-device"

    func infer(_ request: NudgeInferenceRequest) async throws -> InferenceResult {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw AppleIntelligenceInferenceError.unavailable(
                String(describing: model.availability)
            )
        }

        let session = LanguageModelSession(model: model) {
            Self.instructions
        }
        let response = try await session.respond(
            to: Self.prompt(for: request),
            generating: AppleGeneratedNudge.self
        )
        return try Self.map(
            AppleIntelligenceDraft(generated: response.content),
            request: request
        )
        #else
        throw AppleIntelligenceInferenceError.unavailable(
            "the Foundation Models framework is not present on this platform"
        )
        #endif
    }

    static func map(
        _ draft: AppleIntelligenceDraft,
        request: NudgeInferenceRequest
    ) throws -> InferenceResult {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw AppleIntelligenceInferenceError.invalidOutput("missing title")
        }

        let kind = contextKind(for: draft.context)
        let allowed = Set(allowedIdentifiers(for: kind))
        let identifiers = Array(
            Set(draft.identifiers.filter(allowed.contains))
        ).sorted()
        let resolvedIdentifiers = identifiers.isEmpty
            ? defaultIdentifiers(for: kind)
            : identifiers

        let priority = nudgePriority(for: draft.priority)
        let detail = draft.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let confidence = min(max(draft.confidence, 0), 1)
        let primaryURL = validatedURL(
            enabled: draft.hasPrimaryURL,
            value: draft.primaryURL
        )
        let fallbackAt = explicitFallbackDate(
            enabled: draft.hasExplicitFallback,
            delayMinutes: draft.fallbackDelayMinutes,
            referenceDate: request.referenceDate
        )

        return InferenceResult(
            title: title,
            detail: detail.isEmpty ? defaultDetail(for: kind) : detail,
            priority: priority,
            triggers: [
                ContextTrigger(
                    kind: kind,
                    identifiers: resolvedIdentifiers,
                    confidence: confidence,
                    source: draft.source == .explicit ? .explicit : .inferred
                )
            ],
            primaryURL: primaryURL,
            canInterruptFocus: priority == .urgent && draft.canInterruptFocus,
            fallbackAt: fallbackAt
        )
    }

    private static func contextKind(for context: AppleIntelligenceDraft.Context) -> ContextKind {
        switch context {
        case .messaging: .messaging
        case .onlineShopping: .onlineShopping
        case .calendar: .calendar
        case .browser: .browser
        case .productivity: .productivity
        }
    }

    private static func nudgePriority(for priority: AppleIntelligenceDraft.Priority) -> NudgePriority {
        switch priority {
        case .urgent: .urgent
        case .actionable: .actionable
        case .informational: .informational
        }
    }

    private static func allowedIdentifiers(for kind: ContextKind) -> [String] {
        switch kind {
        case .messaging:
            [
                "com.tinyspeck.slackmacgap",
                "com.apple.MobileSMS",
                "com.microsoft.teams2",
                "slack.com",
                "messages.google.com"
            ]
        case .onlineShopping:
            ["amazon.com", "ebay.com", "walmart.com", "etsy.com", "target.com"]
        case .calendar:
            [
                "calendar:any",
                "com.apple.iCal",
                "com.flexibits.fantastical2.mac",
                "com.microsoft.Outlook"
            ]
        case .browser:
            [
                "context:any-browser",
                "com.apple.Safari",
                "com.google.Chrome",
                "company.thebrowser.Browser",
                "org.mozilla.firefox",
                "com.microsoft.edgemac"
            ]
        case .productivity:
            ["context:any-work"]
        }
    }

    private static func defaultIdentifiers(for kind: ContextKind) -> [String] {
        switch kind {
        case .messaging:
            allowedIdentifiers(for: kind)
        case .onlineShopping:
            allowedIdentifiers(for: kind)
        case .calendar:
            ["calendar:any"]
        case .browser:
            ["context:any-browser"]
        case .productivity:
            ["context:any-work"]
        }
    }

    private static func defaultDetail(for kind: ContextKind) -> String {
        switch kind {
        case .messaging: "When you’re messaging"
        case .onlineShopping: "While you’re shopping online"
        case .calendar: "When your calendar is active"
        case .browser: "When you’re browsing"
        case .productivity: "At a useful moment while you work"
        }
    }

    private static func validatedURL(enabled: Bool, value: String) -> URL? {
        guard enabled else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            url.host != nil
        else { return nil }
        return url
    }

    private static func explicitFallbackDate(
        enabled: Bool,
        delayMinutes: Int,
        referenceDate: Date
    ) -> Date? {
        guard enabled, delayMinutes > 0 else { return nil }
        let maximumMinutes = 10 * 365 * 24 * 60
        guard delayMinutes <= maximumMinutes else { return nil }
        return referenceDate.addingTimeInterval(TimeInterval(delayMinutes * 60))
    }

    #if canImport(FoundationModels)
    private static let instructions = """
    You convert a person's reminder request into one concise contextual nudge.
    Return only the guided structure requested by the app.

    Choose the context in which the reminder is most useful. Use an explicit app,
    website, date, or time only when the person actually names or clearly implies it.
    Never invent bundle identifiers, domains, contacts, dates, or URLs.

    Urgent means the reminder is time-sensitive enough to interrupt Focus, such as
    leaving for or joining something soon. Most reminders are actionable. Use
    informational only for passive context or summaries.

    Only set an explicit fallback when the request itself gives a time, date, or
    deadline. Otherwise let the app use its configured fallback.
    """

    private static func prompt(for request: NudgeInferenceRequest) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: request.timeZoneIdentifier) ?? .current
        let reference = formatter.string(from: request.referenceDate)

        return """
        Reminder request: \(request.text)
        Reference date and time: \(reference)
        Locale: \(request.localeIdentifier)
        Time zone: \(request.timeZoneIdentifier)
        App fallback preference when no explicit time is stated: \(request.fallbackDays) days

        Allowed identifiers by context:
        messaging: com.tinyspeck.slackmacgap, com.apple.MobileSMS, com.microsoft.teams2, slack.com, messages.google.com
        onlineShopping: amazon.com, ebay.com, walmart.com, etsy.com, target.com
        calendar: calendar:any, com.apple.iCal, com.flexibits.fantastical2.mac, com.microsoft.Outlook
        browser: context:any-browser, com.apple.Safari, com.google.Chrome, company.thebrowser.Browser, org.mozilla.firefox, com.microsoft.edgemac
        productivity: context:any-work

        For a named supported app or store, return only its exact identifier and mark
        the source explicit. Otherwise use the broad identifiers appropriate to the
        selected context and mark the source inferred.

        If the person gives an explicit time or date, calculate fallbackDelayMinutes
        as whole minutes after the reference date. Otherwise set hasExplicitFallback
        to false and fallbackDelayMinutes to 0.

        Set primaryURL only for a clearly named website or store when a useful HTTP or
        HTTPS destination can be provided. Otherwise set hasPrimaryURL to false and
        primaryURL to an empty string.
        """
    }
    #endif
}

#if canImport(FoundationModels)
@Generable(description: "A structured contextual reminder inferred from one user request")
private struct AppleGeneratedNudge {
    @Guide(description: "A concise action-oriented reminder title")
    var title: String

    @Guide(description: "A short explanation of the context in which this reminder should surface")
    var detail: String

    var priority: AppleGeneratedPriority
    var context: AppleGeneratedContext

    @Guide(
        description: "Only identifiers from the allowed identifier list in the prompt",
        .maximumCount(5)
    )
    var identifiers: [String]

    var source: AppleGeneratedSource

    @Guide(description: "Confidence from zero to one")
    var confidence: Double

    var hasPrimaryURL: Bool

    @Guide(description: "An absolute HTTP or HTTPS URL, or an empty string")
    var primaryURL: String

    var canInterruptFocus: Bool
    var hasExplicitFallback: Bool

    @Guide(description: "Whole minutes after the reference time, or zero")
    var fallbackDelayMinutes: Int
}

@Generable
private enum AppleGeneratedPriority {
    case urgent
    case actionable
    case informational
}

@Generable
private enum AppleGeneratedContext {
    case messaging
    case onlineShopping
    case calendar
    case browser
    case productivity
}

@Generable
private enum AppleGeneratedSource {
    case inferred
    case explicit
}

private extension AppleIntelligenceDraft {
    init(generated: AppleGeneratedNudge) {
        self.init(
            title: generated.title,
            detail: generated.detail,
            priority: switch generated.priority {
            case .urgent: .urgent
            case .actionable: .actionable
            case .informational: .informational
            },
            context: switch generated.context {
            case .messaging: .messaging
            case .onlineShopping: .onlineShopping
            case .calendar: .calendar
            case .browser: .browser
            case .productivity: .productivity
            },
            identifiers: generated.identifiers,
            source: switch generated.source {
            case .inferred: .inferred
            case .explicit: .explicit
            },
            confidence: generated.confidence,
            hasPrimaryURL: generated.hasPrimaryURL,
            primaryURL: generated.primaryURL,
            canInterruptFocus: generated.canInterruptFocus,
            hasExplicitFallback: generated.hasExplicitFallback,
            fallbackDelayMinutes: generated.fallbackDelayMinutes
        )
    }
}
#endif
