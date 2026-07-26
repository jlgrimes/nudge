import Foundation

struct NudgeInferenceRequest: Codable, Equatable, Sendable {
    let text: String
    let referenceDate: Date
    let fallbackDays: Int
    let localeIdentifier: String
    let timeZoneIdentifier: String

    init(
        text: String,
        referenceDate: Date = .now,
        fallbackDays: Int,
        localeIdentifier: String = Locale.current.identifier,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.text = text
        self.referenceDate = referenceDate
        self.fallbackDays = min(max(fallbackDays, 1), 7)
        self.localeIdentifier = localeIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

struct NudgeInferenceResponse: Equatable, Sendable {
    let result: InferenceResult
    let providerID: String
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

/// The current stand-in for an LLM. It obeys the same asynchronous provider
/// contract as a remote or local model, but delegates to deterministic rules.
struct MockLLMInferenceProvider: NudgeInferenceProvider {
    let id = "mock-rule-based"

    func infer(_ request: NudgeInferenceRequest) async throws -> InferenceResult {
        ContextInferenceEngine.infer(from: request.text)
    }
}

/// Composes a preferred provider with a reliable fallback. A future network
/// provider can fail offline without making reminder creation unavailable.
struct FallbackInferenceProvider: NudgeInferenceProvider {
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
        do {
            return try await primary.infer(request)
        } catch {
            return try await fallback.infer(request)
        }
    }
}

struct NudgeInferenceService: Sendable {
    static let live = NudgeInferenceService(provider: MockLLMInferenceProvider())

    private let provider: any NudgeInferenceProvider

    init(provider: any NudgeInferenceProvider) {
        self.provider = provider
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

        let request = NudgeInferenceRequest(
            text: normalized,
            referenceDate: referenceDate,
            fallbackDays: fallbackDays,
            localeIdentifier: locale.identifier,
            timeZoneIdentifier: timeZone.identifier
        )
        let result = try await provider.infer(request)
        try validate(result)

        return NudgeInferenceResponse(result: result, providerID: provider.id)
    }

    private func validate(_ result: InferenceResult) throws {
        guard !result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NudgeInferenceError.invalidResponse("missing title")
        }
        guard !result.triggers.isEmpty else {
            throw NudgeInferenceError.invalidResponse("missing trigger")
        }
        guard result.triggers.allSatisfy({ (0...1).contains($0.confidence) }) else {
            throw NudgeInferenceError.invalidResponse("confidence must be between zero and one")
        }
    }
}
