import Foundation
import XCTest
@testable import Nudge

final class NudgeInferenceProviderTests: XCTestCase {
    func testServicePassesStructuredRequestContextToProvider() async throws {
        let service = NudgeInferenceService(provider: EchoProvider())
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

        let response = try await service.infer(
            text: "  Remind me to review the launch plan  ",
            fallbackDays: 4,
            referenceDate: referenceDate,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "America/Detroit")!
        )

        XCTAssertEqual(response.providerID, "echo")
        XCTAssertEqual(response.result.title, "Remind me to review the launch plan")
        XCTAssertEqual(response.result.detail, "4 · en_US · America/Detroit")
        XCTAssertEqual(response.result.fallbackAt, referenceDate.addingTimeInterval(600))
    }

    @MainActor
    func testStoreUsesInjectedProviderWithoutKnowingItsImplementation() async {
        let exactFallback = Date.now.addingTimeInterval(1_234)
        let provider = StubProvider(
            id: "future-llm",
            result: InferenceResult(
                title: "Provider-generated title",
                detail: "When the design app is active",
                priority: .urgent,
                triggers: [
                    ContextTrigger(
                        kind: .productivity,
                        identifiers: ["com.figma.Desktop"],
                        confidence: 0.99,
                        source: .inferred
                    )
                ],
                primaryURL: URL(string: "https://figma.com"),
                canInterruptFocus: true,
                fallbackAt: exactFallback
            )
        )
        let store = NudgeStore(
            seedDemoData: false,
            inferenceService: NudgeInferenceService(provider: provider)
        )
        store.captureDraft = "Anything—the provider owns interpretation"

        await store.createNudgeFromCaptureNow()

        XCTAssertEqual(store.nudges.count, 1)
        XCTAssertEqual(store.nudges.first?.title, "Provider-generated title")
        XCTAssertEqual(store.nudges.first?.triggers.first?.identifiers, ["com.figma.Desktop"])
        XCTAssertEqual(store.nudges.first?.fallbackAt, exactFallback)
        XCTAssertEqual(store.nudges.first?.primaryURL?.absoluteString, "https://figma.com")
        XCTAssertTrue(store.nudges.first?.canInterruptFocus == true)
        XCTAssertEqual(store.lastInferenceProviderID, "future-llm")
    }

    func testFallbackProviderUsesMockWhenPrimaryFails() async throws {
        let provider = FallbackInferenceProvider(
            primary: FailingProvider(),
            fallback: MockLLMInferenceProvider()
        )
        let service = NudgeInferenceService(provider: provider)

        let response = try await service.infer(
            text: "Remind me to message Alex in Slack",
            fallbackDays: 2
        )

        XCTAssertEqual(response.providerID, "provider-with-fallback")
        XCTAssertEqual(response.result.triggers.first?.kind, .messaging)
        XCTAssertEqual(
            response.result.triggers.first?.identifiers,
            ["com.tinyspeck.slackmacgap"]
        )
    }

    func testServiceRejectsMalformedProviderOutput() async {
        let service = NudgeInferenceService(
            provider: StubProvider(
                id: "broken",
                result: InferenceResult(
                    title: "",
                    detail: "",
                    priority: .actionable,
                    triggers: [],
                    primaryURL: nil,
                    canInterruptFocus: false
                )
            )
        )

        do {
            _ = try await service.infer(text: "Remember this", fallbackDays: 2)
            XCTFail("Expected malformed output to be rejected")
        } catch let error as NudgeInferenceError {
            XCTAssertEqual(error, .invalidResponse("missing title"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct EchoProvider: NudgeInferenceProvider {
    let id = "echo"

    func infer(_ request: NudgeInferenceRequest) async throws -> InferenceResult {
        InferenceResult(
            title: request.text,
            detail: "\(request.fallbackDays) · \(request.localeIdentifier) · \(request.timeZoneIdentifier)",
            priority: .actionable,
            triggers: [
                ContextTrigger(
                    kind: .productivity,
                    identifiers: ["context:any-work"],
                    confidence: 1,
                    source: .inferred
                )
            ],
            primaryURL: nil,
            canInterruptFocus: false,
            fallbackAt: request.referenceDate.addingTimeInterval(600)
        )
    }
}

private struct StubProvider: NudgeInferenceProvider {
    let id: String
    let result: InferenceResult

    func infer(_ request: NudgeInferenceRequest) async throws -> InferenceResult {
        result
    }
}

private struct FailingProvider: NudgeInferenceProvider {
    let id = "failing"

    func infer(_ request: NudgeInferenceRequest) async throws -> InferenceResult {
        throw TestProviderError.unavailable
    }
}

private enum TestProviderError: Error {
    case unavailable
}
