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
        XCTAssertNil(store.recapMessage)
        XCTAssertEqual(store.activeContextLabel, "While you were away")
        XCTAssertEqual(store.presentation, .collapsed)
    }

    @MainActor
    func testDayScenarioStartsWithOneSettledNudge() {
        let store = NudgeStore(seedDemoData: false)

        store.runDebugScenario(.day)

        XCTAssertEqual(store.activeNudges.count, 1)
        XCTAssertEqual(store.presentation, .collapsed)
        XCTAssertEqual(store.activeDebugScenario, .day)
        store.resetDemo()
    }

    @MainActor
    func testMultipleNotificationScenarioAppendsArrivalsToOneAmbientList() async {
        let store = NudgeStore(seedDemoData: false)

        store.runDebugScenario(.multiple)

        XCTAssertEqual(store.activeNudges.count, 2)
        XCTAssertEqual(store.activeContextLabel, "Timeline · waiting for notifications")

        try? await Task.sleep(for: .seconds(1.1))

        XCTAssertEqual(store.activeNudges.count, 6)
        XCTAssertEqual(store.presentation, .collapsed)
        XCTAssertEqual(store.activeContextLabel, "4 nudges arrived together")
        store.resetDemo()
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
    func testSingleScenarioStartsSettledThenSurfacesOneArrival() async {
        let store = NudgeStore(seedDemoData: false)
        store.runDebugScenario(.single)

        XCTAssertEqual(store.activeNudges.map(\.title), ["Review the launch notes"])

        try? await Task.sleep(for: .seconds(1.1))

        XCTAssertEqual(store.activeNudges.count, 2)
        XCTAssertEqual(store.activeNudges.last?.title, "Message Alex")
        store.resetDemo()
    }

    @MainActor
    func testFocusScenarioHoldsThenShowsAWhileAwayBatchCollapsed() {
        let store = NudgeStore(seedDemoData: false)

        store.runDebugScenario(.focus)

        XCTAssertTrue(store.isFocusMode)
        XCTAssertEqual(store.deferredCount, 2)
        XCTAssertEqual(store.activeNudges.count, 3)
        XCTAssertEqual(store.activeContextLabel, "Focus mode · 2 nudges held quietly")
        XCTAssertEqual(store.presentation, .peek)

        store.setFocusMode(false)

        XCTAssertFalse(store.isFocusMode)
        XCTAssertEqual(store.deferredCount, 0)
        XCTAssertEqual(store.activeNudges.count, 5)
        XCTAssertTrue(store.activeNudges.contains { $0.title == "Message Alex about the launch" })
        XCTAssertTrue(store.activeNudges.contains { $0.title == "Order coffee filters" })
        XCTAssertEqual(store.activeContextLabel, "While you were away")
        XCTAssertEqual(store.presentation, .collapsed)
        store.resetDemo()
    }

    @MainActor
    func testContextualNotificationIsTimestampedAtBottomOfTimeline() {
        let store = NudgeStore()

        store.receive(context: .slack)

        XCTAssertEqual(store.activeNudges.last?.title, "Message Alex")
        XCTAssertNotNil(store.activeNudges.last?.surfacedAt)
        XCTAssertEqual(store.activeNudges.last?.invocation, .contextual(.messaging))
    }

    @MainActor
    func testDayScenarioStreamsTheNextNudgeIntoTheSameList() async {
        let store = NudgeStore(seedDemoData: false)
        store.runDebugScenario(.day)

        try? await Task.sleep(for: .milliseconds(750))

        XCTAssertEqual(store.activeNudges.count, 2)
        store.resetDemo()
    }
}
