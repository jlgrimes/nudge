import XCTest
@testable import Nudge

final class AppleIntelligenceInferenceProviderTests: XCTestCase {
    func testGeneratedDraftMapsToProviderNeutralInferenceResult() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_000_000)
        let request = NudgeInferenceRequest(
            text: "Remind me to message Alex in Slack in 45 minutes",
            referenceDate: referenceDate,
            fallbackDays: 2,
            localeIdentifier: "en_US",
            timeZoneIdentifier: "America/Detroit"
        )
        let draft = AppleIntelligenceDraft(
            title: "Message Alex in Slack",
            detail: "When Slack is active",
            priority: .urgent,
            context: .messaging,
            identifiers: ["com.tinyspeck.slackmacgap"],
            source: .explicit,
            confidence: 0.96,
            hasPrimaryURL: false,
            primaryURL: "",
            canInterruptFocus: true,
            hasExplicitFallback: true,
            fallbackDelayMinutes: 45
        )

        let result = try AppleIntelligenceInferenceProvider.map(draft, request: request)

        XCTAssertEqual(result.title, "Message Alex in Slack")
        XCTAssertEqual(result.priority, .urgent)
        XCTAssertEqual(result.triggers.first?.kind, .messaging)
        XCTAssertEqual(result.triggers.first?.identifiers, ["com.tinyspeck.slackmacgap"])
        XCTAssertEqual(result.triggers.first?.source, .explicit)
        XCTAssertEqual(result.triggers.first?.confidence, 0.96)
        XCTAssertTrue(result.canInterruptFocus)
        XCTAssertEqual(result.fallbackAt, referenceDate.addingTimeInterval(45 * 60))
    }

    func testUnknownIdentifiersAreDiscardedAndBroadContextIsRestored() throws {
        let request = NudgeInferenceRequest(
            text: "Remind me to message Alex",
            fallbackDays: 2
        )
        let draft = AppleIntelligenceDraft(
            title: "Message Alex",
            detail: "",
            priority: .actionable,
            context: .messaging,
            identifiers: ["com.example.invented-chat-app"],
            source: .inferred,
            confidence: 1.4,
            hasPrimaryURL: false,
            primaryURL: "",
            canInterruptFocus: true,
            hasExplicitFallback: false,
            fallbackDelayMinutes: 0
        )

        let result = try AppleIntelligenceInferenceProvider.map(draft, request: request)

        XCTAssertEqual(result.detail, "When you’re messaging")
        XCTAssertEqual(
            Set(result.triggers.first?.identifiers ?? []),
            Set([
                "com.tinyspeck.slackmacgap",
                "com.apple.MobileSMS",
                "com.microsoft.teams2",
                "slack.com",
                "messages.google.com"
            ])
        )
        XCTAssertEqual(result.triggers.first?.confidence, 1)
        XCTAssertFalse(result.canInterruptFocus)
        XCTAssertNil(result.fallbackAt)
    }

    func testOnlyHTTPURLsAreAccepted() throws {
        let request = NudgeInferenceRequest(text: "Buy filters on Amazon", fallbackDays: 2)
        let valid = AppleIntelligenceDraft(
            title: "Buy filters",
            detail: "On Amazon",
            priority: .actionable,
            context: .onlineShopping,
            identifiers: ["amazon.com"],
            source: .explicit,
            confidence: 0.9,
            hasPrimaryURL: true,
            primaryURL: "https://amazon.com",
            canInterruptFocus: false,
            hasExplicitFallback: false,
            fallbackDelayMinutes: 0
        )
        let unsafe = AppleIntelligenceDraft(
            title: "Buy filters",
            detail: "On Amazon",
            priority: .actionable,
            context: .onlineShopping,
            identifiers: ["amazon.com"],
            source: .explicit,
            confidence: 0.9,
            hasPrimaryURL: true,
            primaryURL: "file:///tmp/not-allowed",
            canInterruptFocus: false,
            hasExplicitFallback: false,
            fallbackDelayMinutes: 0
        )

        XCTAssertEqual(
            try AppleIntelligenceInferenceProvider.map(valid, request: request).primaryURL,
            URL(string: "https://amazon.com")
        )
        XCTAssertNil(
            try AppleIntelligenceInferenceProvider.map(unsafe, request: request).primaryURL
        )
    }

    func testMissingTitleIsRejectedBeforeItReachesTheStore() {
        let request = NudgeInferenceRequest(text: "Something", fallbackDays: 2)
        let draft = AppleIntelligenceDraft(
            title: "   ",
            detail: "",
            priority: .actionable,
            context: .productivity,
            identifiers: [],
            source: .inferred,
            confidence: 0.5,
            hasPrimaryURL: false,
            primaryURL: "",
            canInterruptFocus: false,
            hasExplicitFallback: false,
            fallbackDelayMinutes: 0
        )

        XCTAssertThrowsError(
            try AppleIntelligenceInferenceProvider.map(draft, request: request)
        )
    }
}
