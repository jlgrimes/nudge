import Foundation
import XCTest
@testable import Nudge

final class ProductionCoreTests: XCTestCase {
    func testProductivityApplicationCreatesBroadWorkContext() {
        let event = ContextEvent.activatedApplication(
            bundleIdentifier: "com.apple.dt.Xcode",
            name: "Xcode"
        )

        XCTAssertEqual(event?.kind, .productivity)
        XCTAssertTrue(event?.identifiers.contains("context:any-work") == true)
    }

    func testBrowserApplicationCreatesBrowserContext() {
        let event = ContextEvent.activatedApplication(
            bundleIdentifier: "com.apple.Safari",
            name: "Safari"
        )

        XCTAssertEqual(event?.kind, .browser)
        XCTAssertTrue(event?.identifiers.contains("context:any-browser") == true)
    }

    func testCalendarIntentMatchesCalendarApplication() {
        let inference = ContextInferenceEngine.infer(
            from: "Remind me to join the design review meeting"
        )
        let event = ContextEvent.activatedApplication(
            bundleIdentifier: "com.apple.iCal",
            name: "Calendar"
        )

        XCTAssertEqual(inference.triggers.first?.kind, .calendar)
        XCTAssertEqual(inference.priority, .urgent)
        XCTAssertTrue(inference.canInterruptFocus)
        XCTAssertTrue(
            event.map { ContextInferenceEngine.matches($0, trigger: inference.triggers[0]) } == true
        )
    }

    func testExplicitShoppingIntentProvidesAUsefulURL() {
        let inference = ContextInferenceEngine.infer(
            from: "Remind me to order coffee filters from Amazon"
        )

        XCTAssertEqual(inference.primaryURL?.absoluteString, "https://amazon.com")
    }

    @MainActor
    func testRuntimeLoadsAndPersistsState() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }

        let persistence = NudgePersistence(fileURL: stateURL)
        let item = makeNudge(fallbackAt: Date.now.addingTimeInterval(3_600))
        try persistence.save(
            NudgeSnapshot(
                nudges: [item],
                fallbackDays: 4,
                isFocusMode: true
            )
        )

        let store = NudgeStore(seedDemoData: false)
        let runtime = NudgeRuntimeController(
            store: store,
            persistence: persistence,
            startsAutomatically: false
        )

        XCTAssertEqual(store.nudges, [item])
        XCTAssertEqual(store.fallbackDays, 4)
        XCTAssertTrue(store.isFocusMode)

        store.fallbackDays = 6
        runtime.flush()

        XCTAssertEqual(persistence.load()?.fallbackDays, 6)
    }

    @MainActor
    func testOverdueFallbackSurfacesAndPersists() {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }

        let persistence = NudgePersistence(fileURL: stateURL)
        let store = NudgeStore(seedDemoData: false)
        let runtime = NudgeRuntimeController(
            store: store,
            persistence: persistence,
            startsAutomatically: false
        )
        let now = Date.now
        let item = makeNudge(fallbackAt: now.addingTimeInterval(-1))
        store.nudges = [item]

        runtime.runMaintenance(now: now)

        XCTAssertEqual(store.nudges.first?.status, .active)
        XCTAssertEqual(store.nudges.first?.invocation, .temporal)
        XCTAssertNotNil(store.nudges.first?.surfacedAt)
        XCTAssertEqual(store.activeContextLabel, "Fallback reminder")
        XCTAssertEqual(store.presentation, .peek)
        XCTAssertEqual(persistence.load()?.nudges.first?.status, .active)
    }

    @MainActor
    func testFocusModeDefersNonUrgentFallback() {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }

        let persistence = NudgePersistence(fileURL: stateURL)
        let store = NudgeStore(seedDemoData: false)
        let runtime = NudgeRuntimeController(
            store: store,
            persistence: persistence,
            startsAutomatically: false
        )
        let now = Date.now
        store.isFocusMode = true
        store.nudges = [makeNudge(fallbackAt: now.addingTimeInterval(-1))]

        runtime.runMaintenance(now: now)

        XCTAssertEqual(store.nudges.first?.status, .deferred)
        XCTAssertEqual(store.deferredCount, 1)
        XCTAssertEqual(store.activeContextLabel, "Focus mode · nudges held quietly")
    }

    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NudgeTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }

    private func makeNudge(fallbackAt: Date) -> NudgeItem {
        NudgeItem(
            originalRequest: "Review the launch checklist",
            title: "Review the launch checklist",
            detail: "At a useful moment while you work",
            triggers: [
                ContextTrigger(
                    kind: .productivity,
                    identifiers: ["context:any-work"],
                    confidence: 0.58,
                    source: .inferred
                )
            ],
            fallbackAt: fallbackAt
        )
    }
}
