import Foundation

struct NudgeInferenceRequest: Codable, Equatable, Sendable {
    let text: String
    let referenceDate: Date
    let fallbackDays: Int
    let localeIdentifier: String
    let timeZoneIdentifier: String
    let installedApplications: [InstalledApplicationDescriptor]

    init(
        text: String,
        referenceDate: Date = .now,
        fallbackDays: Int,
        localeIdentifier: String = Locale.current.identifier,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        installedApplications: [InstalledApplicationDescriptor] = []
    ) {
        self.text = text
        self.referenceDate = referenceDate
        self.fallbackDays = min(max(fallbackDays, 1), 7)
        self.localeIdentifier = localeIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.installedApplications = installedApplications
    }
}

struct NudgeInferenceResponse: Equatable, Sendable {
    let result: InferenceResult
    let providerID: String
    let fallbackReason: String?
}

struct NudgeProviderInferenceResponse: Equatable, Sendable {
    let result: InferenceResult
    let providerID: String
    let fallbackReason: String?

    init(
        result: InferenceResult,
        providerID: String,
        fallbackReason: String? = nil
    ) {
        self.result = result
        self.providerID = providerID
        self.fallbackReason = fallbackReason
    }
}

enum NudgeInferenceError: LocalizedError, Equatable {
    case emptyRequest
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .emptyRequest:
            "Enter something you want to remember."
        case .invalidResponse(let reason):
            "The inference provider returned an invalid nudge: \(reason)"
        }
    }
}

protocol NudgeInferenceProvider: Sendable {
    var id: String { get }
    func infer(_ request: NudgeInferenceRequest) async throws -> InferenceResult
}

/// Optional diagnostics supplied by composed providers. The core provider
/// contract remains a black box returning only an InferenceResult.
protocol NudgeInferenceProvenanceProviding: Sendable {
    func inferWithProvenance(
        _ request: NudgeInferenceRequest
    ) async throws -> NudgeProviderInferenceResponse
}

/// A deterministic offline provider. It obeys the same asynchronous provider
/// contract as a model, but delegates to the local rule engine.
struct MockLLMInferenceProvider: NudgeInferenceProvider {
    let id = "mock-rule-based"

    func infer(_ request: NudgeInferenceRequest) async throws -> InferenceResult {
        let result = ContextInferenceEngine.infer(from: request.text)
        guard let application = ApplicationMentionResolver.bestMatch(
            in: request.text,
            applications: request.installedApplications
        ) else { return result }
        return result.targeting(application)
    }
}

/// Composes a preferred provider with a reliable fallback. Apple Intelligence
/// can be unavailable because of device eligibility, settings, or model state;
/// reminder creation should remain usable in all of those cases.
struct FallbackInferenceProvider: NudgeInferenceProvider, NudgeInferenceProvenanceProviding {
    let id: String
    private let primary: any NudgeInferenceProvider
    private let fallback: any NudgeInferenceProvider

    init(
        id: String = "provider-with-fallback",
        primary: any NudgeInferenceProvider,
        fallback: any NudgeInferenceProvider = MockLLMInferenceProvider()
    ) {
        self.id = id
        self.primary = primary
        self.fallback = fallback
    }

    func infer(_ request: NudgeInferenceRequest) async throws -> InferenceResult {
        try await inferWithProvenance(request).result
    }

    func inferWithProvenance(
        _ request: NudgeInferenceRequest
    ) async throws -> NudgeProviderInferenceResponse {
        do {
            return NudgeProviderInferenceResponse(
                result: try await primary.infer(request),
                providerID: primary.id
            )
        } catch {
            return NudgeProviderInferenceResponse(
                result: try await fallback.infer(request),
                providerID: fallback.id,
                fallbackReason: error.localizedDescription
            )
        }
    }
}

struct NudgeInferenceService: Sendable {
    static let live = NudgeInferenceService(
        provider: FallbackInferenceProvider(
            id: "apple-intelligence-with-rule-fallback",
            primary: AppleIntelligenceInferenceProvider()
        ),
        applicationCatalog: InstalledApplicationCatalog.live
    )

    private let provider: any NudgeInferenceProvider
    private let applicationCatalog: any InstalledApplicationProviding

    init(
        provider: any NudgeInferenceProvider,
        applicationCatalog: any InstalledApplicationProviding = StaticInstalledApplicationCatalog(values: [])
    ) {
        self.provider = provider
        self.applicationCatalog = applicationCatalog
    }

    func infer(
        text: String,
        fallbackDays: Int,
        referenceDate: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) async throws -> NudgeInferenceResponse {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw NudgeInferenceError.emptyRequest }

        let installedApplications = await applicationCatalog.applications()
        let request = NudgeInferenceRequest(
            text: normalized,
            referenceDate: referenceDate,
            fallbackDays: fallbackDays,
            localeIdentifier: locale.identifier,
            timeZoneIdentifier: timeZone.identifier,
            installedApplications: Self.relevantApplications(
                for: normalized,
                from: installedApplications
            )
        )

        let providerResponse: NudgeProviderInferenceResponse
        if let provenanceProvider = provider as? any NudgeInferenceProvenanceProviding {
            providerResponse = try await provenanceProvider.inferWithProvenance(request)
        } else {
            providerResponse = NudgeProviderInferenceResponse(
                result: try await provider.infer(request),
                providerID: provider.id
            )
        }
        try validate(providerResponse.result)

        return NudgeInferenceResponse(
            result: providerResponse.result,
            providerID: providerResponse.providerID,
            fallbackReason: providerResponse.fallbackReason
        )
    }

    private func validate(_ result: InferenceResult) throws {
        guard !result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NudgeInferenceError.invalidResponse("missing title")
        }
        guard !result.conditions.isEmpty else {
            throw NudgeInferenceError.invalidResponse("missing condition")
        }
        guard result.triggers.allSatisfy({ (0...1).contains($0.confidence) }) else {
            throw NudgeInferenceError.invalidResponse("confidence must be between zero and one")
        }
    }

    private static func relevantApplications(
        for text: String,
        from applications: [InstalledApplicationDescriptor]
    ) -> [InstalledApplicationDescriptor] {
        let mentioned = ApplicationMentionResolver.matches(in: text, applications: applications)
        let mentionedIDs = Set(mentioned.map(\.bundleIdentifier))
        let remaining = applications.filter { !mentionedIDs.contains($0.bundleIdentifier) }
        return Array((mentioned + remaining).prefix(120))
    }
}

enum ApplicationMentionResolver {
    static func bestMatch(
        in text: String,
        applications: [InstalledApplicationDescriptor]
    ) -> InstalledApplicationDescriptor? {
        matches(in: text, applications: applications).first
    }

    static func matches(
        in text: String,
        applications: [InstalledApplicationDescriptor]
    ) -> [InstalledApplicationDescriptor] {
        let normalizedText = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )

        return applications
            .filter { application in
                let normalizedName = application.name.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                guard normalizedName.count >= 3 else { return false }

                let escapedName = NSRegularExpression.escapedPattern(for: normalizedName)
                let pattern = "(?<![\\p{L}\\p{N}])\(escapedName)(?![\\p{L}\\p{N}])"
                return normalizedText.range(of: pattern, options: .regularExpression) != nil
            }
            .sorted {
                if $0.name.count != $1.name.count {
                    return $0.name.count > $1.name.count
                }
                let nameComparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                return $0.bundleIdentifier < $1.bundleIdentifier
            }
    }
}
