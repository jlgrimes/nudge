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

    func testRealSlackActivationCreatesAMessagingContext() {
        let event = ContextEvent.activatedApplication(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            name: "Slack"
        )

        XCTAssertEqual(event?.kind, .messaging)
        XCTAssertEqual(event?.identifiers, ["com.tinyspeck.slackmacgap"])
        XCTAssertEqual(event?.label, "Slack is active")
    }

    func testUnrelatedApplicationDoesNotCreateAContext() {
        let event = ContextEvent.activatedApplication(
            bundleIdentifier: "com.apple.finder",
            name: "Finder"
        )

        XCTAssertNil(event)
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
        XCTAssertEqual(store.surfacedBatch?.nudgeIDs.count, 1)
    }

    @MainActor
    func testDayScenarioSurfacesItsFirstItemAsAnArrivalBatch() {
        let store = NudgeStore(seedDemoData: false)

        store.runDebugScenario(.day)

        XCTAssertEqual(store.activeNudges.count, 1)
        XCTAssertEqual(store.presentation, .collapsed)
        XCTAssertEqual(store.activeDebugScenario, .day)
        XCTAssertEqual(store.surfacedBatch?.nudgeIDs, [store.activeNudges[0].id])
        store.resetDemo()
    }

    @MainActor
    func testMultipleNotificationScenarioShowsOneAmbientList() {
        let store = NudgeStore(seedDemoData: false)

        store.runDebugScenario(.multiple)

        XCTAssertEqual(store.activeNudges.count, 4)
        XCTAssertEqual(store.presentation, .collapsed)
        XCTAssertEqual(store.activeContextLabel, "4 nudges arrived together")
        XCTAssertEqual(Set(store.surfacedBatch?.nudgeIDs ?? []), Set(store.activeNudges.map(\.id)))
    }

    @MainActor
    func testAmbientListExcludesFutureNudges() {
        let store = NudgeStore()

        XCTAssertEqual(store.activeNudges.count, 1)
        XCTAssertEqual(store.futureNudges.count, 3)
        XCTAssertTrue(store.activeNudges.allSatisfy { $0.status == .active })
        XCTAssertTrue(store.futureNudges.allSatisfy { $0.status == .pending })
    }

    @MainActor
    func testSingleScenarioRetimestampsAndSurfacesExistingNudgeAsABatch() async {
        let store = NudgeStore(seedDemoData: false)
        store.runDebugScenario(.single)

        XCTAssertNotEqual(store.activeNudges.last?.title, "Message Alex")

        try? await Task.sleep(for: .seconds(1.1))

        XCTAssertEqual(store.activeNudges.last?.title, "Message Alex")
        XCTAssertEqual(store.surfacedBatch?.nudgeIDs, [store.activeNudges.last?.id].compactMap { $0 })
        store.resetDemo()
    }

    @MainActor
    func testFocusScenarioHoldsNormalNudgesButShowsUrgentOne() {
        let store = NudgeStore(seedDemoData: false)

        store.runDebugScenario(.focus)

        XCTAssertTrue(store.isFocusMode)
        XCTAssertEqual(store.deferredCount, 2)
        XCTAssertEqual(store.activeNudges.count, 1)
        XCTAssertEqual(store.activeNudges.first?.priority, .urgent)
        store.resetDemo()
    }

    @MainActor
    func testContextualNotificationIsTimestampedAtBottomOfTimeline() {
        let store = NudgeStore()

        store.receive(context: .slack)

        XCTAssertEqual(store.activeNudges.last?.title, "Message Alex")
        XCTAssertNotNil(store.activeNudges.last?.surfacedAt)
        XCTAssertEqual(store.activeNudges.last?.invocation, .contextual(.messaging))
        XCTAssertEqual(store.surfacedBatch?.nudgeIDs, [store.activeNudges.last?.id].compactMap { $0 })
    }

    @MainActor
    func testAcknowledgingAnArrivalOnlyClearsTheMatchingBatch() {
        let store = NudgeStore(seedDemoData: false)
        store.runDebugScenario(.multiple)
        let batchID = store.surfacedBatch?.id

        store.acknowledgeSurfacedBatch(UUID())
        XCTAssertEqual(store.surfacedBatch?.id, batchID)

        if let batchID {
            store.acknowledgeSurfacedBatch(batchID)
        }
        XCTAssertNil(store.surfacedBatch)
    }
}
