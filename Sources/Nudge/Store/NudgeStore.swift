import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class NudgeStore {
    struct SurfacedBatch: Identifiable, Equatable, Sendable {
        let id: UUID
        let nudgeIDs: [UUID]
        let headerTitle: String?

        init(id: UUID = UUID(), nudgeIDs: [UUID], headerTitle: String? = nil) {
            self.id = id
            self.nudgeIDs = nudgeIDs
            self.headerTitle = headerTitle
        }
    }

    enum Presentation: Equatable {
        case collapsed
        case peek
        case expanded
        case capture
    }

    enum DebugScenario: String, CaseIterable {
        case day
        case single
        case multiple
        case focus
    }

    static let shared = NudgeStore()

    var nudges: [NudgeItem] {
        didSet { panelLayoutDidChange?() }
    }
    var presentation: Presentation = .collapsed {
        didSet { presentationDidChange?() }
    }
    var isFocusMode = false
    var activeContextLabel = "Context ready"
    var recapMessage: String? {
        didSet { panelLayoutDidChange?() }
    }
    var captureDraft = ""
    var capturePreview: NudgeItem? {
        didSet { panelLayoutDidChange?() }
    }
    var fallbackDays = 2
    var isListening = false
    var activeDebugScenario: DebugScenario?
    var surfacedBatch: SurfacedBatch? {
        didSet { panelLayoutDidChange?() }
    }

    @ObservationIgnored var presentationDidChange: (() -> Void)?
    @ObservationIgnored var panelLayoutDidChange: (() -> Void)?
    @ObservationIgnored var debugScenarioDidRun: (() -> Void)?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    @ObservationIgnored private var demoTask: Task<Void, Never>?

    init(seedDemoData: Bool = true) {
        self.nudges = seedDemoData ? Self.demoNudges() : []
    }

    var activeNudges: [NudgeItem] {
        nudges
            .filter { $0.status == .active }
            .sorted { lhs, rhs in
                if lhs.timelineDate != rhs.timelineDate {
                    return lhs.timelineDate < rhs.timelineDate
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    var deferredCount: Int {
        nudges.filter { $0.status == .deferred }.count
    }

    var futureNudges: [NudgeItem] {
        nudges
            .filter { $0.status == .pending }
            .sorted { lhs, rhs in
                if lhs.fallbackAt != rhs.fallbackAt {
                    return lhs.fallbackAt < rhs.fallbackAt
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    var pendingCount: Int {
        nudges.filter { $0.status == .pending }.count
    }

    var bubbleCount: Int {
        activeNudges.count + deferredCount
    }

    func toggleExpanded() {
        presentation = presentation == .expanded ? .collapsed : .expanded
    }

    func showExpanded() {
        peekTask?.cancel()
        presentation = .expanded
    }

    func collapse() {
        peekTask?.cancel()
        presentation = .collapsed
    }

    func showCapture() {
        peekTask?.cancel()
        captureDraft = ""
        capturePreview = nil
        isListening = false
        presentation = .capture
    }

    func createNudgeFromCapture() {
        let request = captureDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }

        let inference = ContextInferenceEngine.infer(from: request)
        let item = NudgeItem(
            originalRequest: request,
            title: inference.title,
            detail: inference.detail,
            priority: inference.priority,
            triggers: inference.triggers,
            fallbackAt: Calendar.current.date(byAdding: .day, value: fallbackDays, to: .now) ?? .now,
            primaryURL: inference.primaryURL,
            canInterruptFocus: inference.canInterruptFocus
        )

        nudges.append(item)
        capturePreview = item
        activeContextLabel = "Saved with inferred context"
    }

    func simulateVoiceCapture() {
        guard !isListening else { return }
        isListening = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self else { return }
            captureDraft = "Remind me to message Alex"
            isListening = false
        }
    }

    func receive(context event: ContextEvent) {
        activeContextLabel = event.label
        let wasExpanded = presentation == .expanded

        let matchingIDs = nudges.compactMap { item -> UUID? in
            guard item.status == .pending else { return nil }
            let matches = item.triggers.contains { ContextInferenceEngine.matches(event, trigger: $0) }
            return matches ? item.id : nil
        }

        guard !matchingIDs.isEmpty else { return }

        withAnimation(.snappy(duration: 0.3)) {
            for (offset, id) in matchingIDs.enumerated() {
                guard let index = nudges.firstIndex(where: { $0.id == id }) else { continue }
                nudges[index].surfacedAt = Date.now.addingTimeInterval(Double(offset) * 0.001)
                nudges[index].invocation = .contextual(event.kind)
                if isFocusMode && !nudges[index].canInterruptFocus {
                    nudges[index].status = .deferred
                } else {
                    nudges[index].status = .active
                }
            }
        }

        guard matchingIDs.contains(where: { id in
            nudges.first(where: { $0.id == id })?.status == .active
        }) else { return }

        let activeMatchingIDs = matchingIDs.filter { id in
            nudges.first(where: { $0.id == id })?.status == .active
        }
        publishSurfaceBatch(activeMatchingIDs)

        if wasExpanded {
            panelLayoutDidChange?()
        } else {
            showPeekTemporarily()
        }
    }

    func complete(_ id: UUID) {
        guard let index = nudges.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeOut(duration: 0.24)) {
            nudges[index].status = .completed
        }
        if activeNudges.isEmpty {
            collapse()
        }
    }

    func dismiss(_ id: UUID) {
        guard let index = nudges.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeOut(duration: 0.24)) {
            nudges[index].status = .dismissed
        }
    }

    func setFocusMode(_ enabled: Bool) {
        guard isFocusMode != enabled else { return }
        isFocusMode = enabled

        if enabled {
            recapMessage = nil
            activeContextLabel = "Focus mode · nudges held quietly"
            collapse()
            return
        }

        let deferredIDs = nudges.filter { $0.status == .deferred }.map(\.id)
        for (offset, id) in deferredIDs.enumerated() {
            if let index = nudges.firstIndex(where: { $0.id == id }) {
                nudges[index].status = .active
                nudges[index].surfacedAt = Date.now.addingTimeInterval(Double(offset) * 0.001)
            }
        }

        if !deferredIDs.isEmpty {
            recapMessage = nil
            activeContextLabel = "While you were away"
            publishSurfaceBatch(deferredIDs, headerTitle: "While you were away")
            presentation = .collapsed
        } else {
            activeContextLabel = "Context ready"
        }
    }

    func resetDemo() {
        demoTask?.cancel()
        peekTask?.cancel()
        surfacedBatch = nil
        nudges = Self.demoNudges()
        isFocusMode = false
        recapMessage = nil
        activeContextLabel = "Context ready"
        captureDraft = ""
        capturePreview = nil
        activeDebugScenario = nil
        presentation = .collapsed
    }

    func runDemo() {
        resetDemo()
        demoTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            receive(context: .slack)

            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            setFocusMode(true)

            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            receive(context: .amazon)

            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            receive(context: .calendar)

            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            setFocusMode(false)
        }
    }

    func runDebugScenario(_ scenario: DebugScenario) {
        prepareDebugScenario(scenario)

        switch scenario {
        case .day:
            let dayNudges = Self.dayScenarioNudges()
            nudges = Array(dayNudges.prefix(1))
            activeContextLabel = "Today · 1 unresolved nudge"
            presentation = .collapsed
            if let firstNudge = dayNudges.first {
                publishSurfaceBatch([firstNudge.id])
            }

            demoTask = Task { @MainActor [weak self] in
                guard let self else { return }
                for item in dayNudges.dropFirst() {
                    // Leave enough room for the shared one-second hold and absorption
                    // before materializing the next Day Stream bubble.
                    try? await Task.sleep(for: .milliseconds(1_650))
                    guard !Task.isCancelled else { return }
                    publishSurfaceBatch([item.id])
                    nudges.append(item)
                    activeContextLabel = "Today · \(nudges.count) unresolved nudges"
                }
            }

        case .single:
            nudges = Self.singleScenarioTimeline()
            activeContextLabel = "Timeline · waiting for context"
            presentation = .collapsed

            demoTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, !Task.isCancelled else { return }
                guard let index = nudges.firstIndex(where: { $0.title == "Message Alex" }) else { return }
                let id = nudges[index].id
                withAnimation(.snappy(duration: 0.42)) {
                    nudges[index].surfacedAt = .now
                    nudges[index].invocation = .contextual(.messaging)
                }
                activeContextLabel = "Slack is active · nudge refreshed"
                publishSurfaceBatch([id])
            }

        case .multiple:
            let incomingNudges = Self.multipleScenarioNudges()
            nudges = Self.settledScenarioNudges() + incomingNudges
            activeContextLabel = "\(incomingNudges.count) nudges arrived together"
            publishSurfaceBatch(incomingNudges.map(\.id))
            presentation = .collapsed

        case .focus:
            nudges = Self.settledScenarioNudges() + Self.focusScenarioNudges()
            isFocusMode = true
            activeContextLabel = "Focus mode · 2 nudges held quietly"
            presentation = .peek

            demoTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                setFocusMode(false)
            }
        }

        debugScenarioDidRun?()
    }

    private func showPeekTemporarily() {
        peekTask?.cancel()
        presentation = .peek
        peekTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled, presentation == .peek else { return }
            presentation = .collapsed
        }
    }

    private func prepareDebugScenario(_ scenario: DebugScenario) {
        demoTask?.cancel()
        peekTask?.cancel()
        surfacedBatch = nil
        activeDebugScenario = scenario
        nudges = []
        isFocusMode = false
        recapMessage = nil
        captureDraft = ""
        capturePreview = nil
        activeContextLabel = "Context ready"
        presentation = .collapsed
    }

    func acknowledgeSurfacedBatch(_ id: UUID) {
        guard surfacedBatch?.id == id else { return }
        surfacedBatch = nil
    }

    private func publishSurfaceBatch(_ ids: [UUID], headerTitle: String? = nil) {
        guard !ids.isEmpty else { return }
        surfacedBatch = SurfacedBatch(nudgeIDs: ids, headerTitle: headerTitle)
    }

    private static func demoNudges() -> [NudgeItem] {
        let twoDays = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
        let messaging = ContextTrigger(
            kind: .messaging,
            identifiers: [
                "com.tinyspeck.slackmacgap",
                "com.apple.MobileSMS",
                "com.microsoft.teams2",
                "slack.com"
            ],
            confidence: 0.87,
            source: .inferred
        )
        let shopping = ContextTrigger(
            kind: .onlineShopping,
            identifiers: ["amazon.com", "ebay.com", "walmart.com", "etsy.com", "target.com"],
            confidence: 0.9,
            source: .inferred
        )
        let calendar = ContextTrigger(
            kind: .calendar,
            identifiers: ["calendar.urgent"],
            confidence: 1,
            source: .explicit
        )

        return [
            NudgeItem(
                originalRequest: "Remind me to send Maya the final mockup",
                title: "Send Maya the final mockup",
                detail: "When you’re messaging",
                triggers: [messaging],
                fallbackAt: twoDays,
                status: .active
            ),
            NudgeItem(
                originalRequest: "Remind me to message Alex",
                title: "Message Alex",
                detail: "When you’re messaging",
                triggers: [messaging],
                fallbackAt: twoDays
            ),
            NudgeItem(
                originalRequest: "Remind me to order coffee filters",
                title: "Order coffee filters",
                detail: "While you’re shopping online",
                triggers: [shopping],
                fallbackAt: twoDays,
                primaryURL: URL(string: "https://amazon.com")
            ),
            NudgeItem(
                originalRequest: "Leave for the dentist",
                title: "Leave for the dentist",
                detail: "12 min drive · appointment at 2:00",
                priority: .urgent,
                triggers: [calendar],
                fallbackAt: .now,
                canInterruptFocus: true
            )
        ]
    }

    private static func dayScenarioNudges() -> [NudgeItem] {
        let context = ContextTrigger(
            kind: .productivity,
            identifiers: ["mock.day"],
            confidence: 1,
            source: .inferred
        )
        let messaging = ContextTrigger(
            kind: .messaging,
            identifiers: ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS"],
            confidence: 0.87,
            source: .inferred
        )
        let calendar = ContextTrigger(
            kind: .calendar,
            identifiers: ["mock.calendar"],
            confidence: 1,
            source: .inferred
        )
        let fallback = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now

        return [
            NudgeItem(
                originalRequest: "Morning overview",
                title: "Plan the three things that matter today",
                detail: "Morning overview",
                priority: .informational,
                triggers: [context],
                fallbackAt: fallback,
                createdAt: mockDate(hour: 8, minute: 30),
                status: .active
            ),
            NudgeItem(
                originalRequest: "Prepare for design review",
                title: "Prepare for the design review",
                detail: "Meeting in 40 minutes",
                triggers: [calendar],
                fallbackAt: fallback,
                createdAt: mockDate(hour: 9, minute: 20),
                status: .active
            ),
            NudgeItem(
                originalRequest: "Message Alex",
                title: "Message Alex about the launch",
                detail: "Slack became active",
                triggers: [messaging],
                fallbackAt: fallback,
                createdAt: mockDate(hour: 10, minute: 5),
                status: .active,
                invocation: .contextual(.messaging)
            ),
            NudgeItem(
                originalRequest: "Submit lunch order",
                title: "Submit the team lunch order",
                detail: "Ordering closes soon",
                priority: .urgent,
                triggers: [context],
                fallbackAt: fallback,
                createdAt: mockDate(hour: 11, minute: 45),
                status: .active,
                canInterruptFocus: true
            ),
            NudgeItem(
                originalRequest: "Review afternoon",
                title: "Your afternoon is meeting-free",
                detail: "A good time for focused work",
                priority: .informational,
                triggers: [calendar],
                fallbackAt: fallback,
                createdAt: mockDate(hour: 14, minute: 30),
                status: .active
            ),
            NudgeItem(
                originalRequest: "Wrap up",
                title: "Capture loose ends before signing off",
                detail: "End-of-day review",
                triggers: [context],
                fallbackAt: fallback,
                createdAt: mockDate(hour: 17, minute: 15),
                status: .active
            )
        ]
    }

    private static func singleScenarioTimeline() -> [NudgeItem] {
        let messaging = ContextTrigger(
            kind: .messaging,
            identifiers: ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "com.microsoft.teams2"],
            confidence: 0.87,
            source: .inferred
        )
        let context = ContextTrigger(
            kind: .productivity,
            identifiers: ["mock.single"],
            confidence: 1,
            source: .inferred
        )
        let fallback = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
        let now = Date.now

        return [
            NudgeItem(
                originalRequest: "Review launch notes",
                title: "Review the launch notes",
                detail: "",
                triggers: [context],
                fallbackAt: fallback,
                createdAt: now.addingTimeInterval(-3_600),
                status: .active
            ),
            NudgeItem(
                originalRequest: "Message Alex",
                title: "Message Alex",
                detail: "",
                triggers: [messaging],
                fallbackAt: fallback,
                createdAt: now.addingTimeInterval(-2_400),
                status: .active
            ),
            NudgeItem(
                originalRequest: "Submit expenses",
                title: "Submit this week’s expenses",
                detail: "",
                triggers: [context],
                fallbackAt: fallback,
                createdAt: now.addingTimeInterval(-1_800),
                status: .active
            ),
            NudgeItem(
                originalRequest: "Order coffee filters",
                title: "Order coffee filters",
                detail: "",
                triggers: [context],
                fallbackAt: fallback,
                createdAt: now.addingTimeInterval(-900),
                status: .active
            )
        ]
    }

    private static func settledScenarioNudges() -> [NudgeItem] {
        Array(dayScenarioNudges().prefix(2))
    }

    private static func multipleScenarioNudges() -> [NudgeItem] {
        let context = ContextTrigger(
            kind: .productivity,
            identifiers: ["mock.batch"],
            confidence: 1,
            source: .inferred
        )
        let fallback = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
        return [
            NudgeItem(
                originalRequest: "Join design review",
                title: "Join the design review",
                detail: "Starts in 5 minutes",
                priority: .urgent,
                triggers: [context],
                fallbackAt: fallback,
                status: .active,
                canInterruptFocus: true
            ),
            NudgeItem(
                originalRequest: "Send prototype link",
                title: "Send the prototype link to Maya",
                detail: "Slack is active",
                triggers: [context],
                fallbackAt: fallback,
                status: .active
            ),
            NudgeItem(
                originalRequest: "Order coffee filters",
                title: "Order coffee filters",
                detail: "Shopping tab is open",
                triggers: [context],
                fallbackAt: fallback,
                status: .active
            ),
            NudgeItem(
                originalRequest: "Afternoon status",
                title: "Your afternoon is meeting-free",
                detail: "Informational",
                priority: .informational,
                triggers: [context],
                fallbackAt: fallback,
                status: .active
            )
        ]
    }

    private static func focusScenarioNudges() -> [NudgeItem] {
        let context = ContextTrigger(
            kind: .productivity,
            identifiers: ["mock.focus"],
            confidence: 1,
            source: .inferred
        )
        let fallback = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
        return [
            NudgeItem(
                originalRequest: "Message Alex",
                title: "Message Alex about the launch",
                detail: "Held during Focus",
                triggers: [context],
                fallbackAt: fallback,
                status: .deferred,
                surfacedAt: Date.now.addingTimeInterval(-120)
            ),
            NudgeItem(
                originalRequest: "Order coffee filters",
                title: "Order coffee filters",
                detail: "Held during Focus",
                triggers: [context],
                fallbackAt: fallback,
                status: .deferred,
                surfacedAt: Date.now.addingTimeInterval(-60)
            ),
            NudgeItem(
                originalRequest: "Leave for dentist",
                title: "Leave for the dentist",
                detail: "Urgent · appointment at 2:00",
                priority: .urgent,
                triggers: [context],
                fallbackAt: .now,
                status: .active,
                canInterruptFocus: true
            )
        ]
    }

    private static func mockDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}
