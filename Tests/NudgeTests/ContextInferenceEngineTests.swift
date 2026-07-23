import XCTest
@testable import Nudge

final class ContextInferenceEngineTests: XCTestCase {
    func testAmbiguousMessageRequestCastsAWideNet() {
        let result = ContextInferenceEngine.infer(from: "Remind me to message Alex")

        XCTAssertEqual(result.triggers.first?.kind, .messaging)
        XCTAssertEqual(result.triggers.first?.source, .inferred)
        XCTAssertTrue(result.triggers.first?.identifiers.contains("com.tinyspeck.slackmacgap") == true)
        XCTAssertTrue(result.triggers.first?.identifiers.contains("com.apple.MobileSMS") == true)
        XCTAssertTrue(result.triggers.first?.identifiers.contains("com.microsoft.teams2") == true)
    }

    func testExplicitMessagingAppNarrowsTheTrigger() {
        let result = ContextInferenceEngine.infer(from: "Remind me to message Alex in Slack")

        XCTAssertEqual(result.triggers.first?.source, .explicit)
        XCTAssertEqual(result.triggers.first?.identifiers, ["com.tinyspeck.slackmacgap"])
    }

    func testShoppingIntentInfersCommerceDomains() {
        let result = ContextInferenceEngine.infer(from: "Remind me to order coffee filters")

        XCTAssertEqual(result.triggers.first?.kind, .onlineShopping)
        XCTAssertTrue(result.triggers.first?.identifiers.contains("amazon.com") == true)
        XCTAssertTrue(result.triggers.first?.identifiers.contains("ebay.com") == true)
    }

    @MainActor
    func testFocusDefersAndThenReleasesAContextualNudge() {
        let store = NudgeStore()
        store.resetDemo()
        store.setFocusMode(true)
        store.receive(context: .amazon)

        XCTAssertEqual(store.deferredCount, 1)
        XCTAssertFalse(store.activeNudges.contains(where: { $0.title == "Order coffee filters" }))

        store.setFocusMode(false)

        XCTAssertEqual(store.deferredCount, 0)
        XCTAssertTrue(store.activeNudges.contains(where: { $0.title == "Order coffee filters" }))
        XCTAssertNotNil(store.recapMessage)
    }
}
