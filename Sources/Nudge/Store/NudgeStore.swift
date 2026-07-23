import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class NudgeStore {
    enum Presentation: Equatable {
        case collapsed
        case peek
        case expanded
        case capture
    }

    static let shared = NudgeStore()

    var nudges: [NudgeItem]
    var presentation: Presentation = .collapsed {
        didSet { presentationDidChange?() }
    }
    var isFocusMode = false
    var activeContextLabel = "Context ready"
    var recapMessage: String?
    var captureDraft = ""
    var capturePreview: NudgeItem?
    var fallbackDays = 2
    var isListening = false

    @ObservationIgnored var presentationDidChange: (() -> Void)?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    @ObservationIgnored private var demoTask: Task<Void, Never>?

    init(seedDemoData: Bool = true) {
        self.nudges = seedDemoData ? Self.demoNudges() : []
    }

    var activeNudges: [NudgeItem] {
        nudges
            .filter { $0.status == .active }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return priorityRank(lhs.priority) < priorityRank(rhs.priority)
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    var deferredCount: Int {
        nudges.filter { $0.status == .deferred }.count
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

        let matchingIDs = nudges.compactMap { item -> UUID? in
            guard item.status == .pending else { return nil }
            let matches = item.triggers.contains { ContextInferenceEngine.matches(event, trigger: $0) }
            return matches ? item.id : nil
        }

        guard !matchingIDs.isEmpty else { return }

        for id in matchingIDs {
            guard let index = nudges.firstIndex(where: { $0.id == id }) else { continue }
            if isFocusMode && !nudges[index].canInterruptFocus {
                nudges[index].status = .deferred
            } else {
                nudges[index].status = .active
            }
        }

        guard matchingIDs.contains(where: { id in
            nudges.first(where: { $0.id == id })?.status == .active
        }) else { return }

        showPeekTemporarily()
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
        for id in deferredIDs {
            if let index = nudges.firstIndex(where: { $0.id == id }) {
                nudges[index].status = .active
            }
        }

        if !deferredIDs.isEmpty {
            let titles = deferredIDs.compactMap { id in
                nudges.first(where: { $0.id == id })?.title
            }
            recapMessage = shortRecap(for: titles)
            activeContextLabel = "Focus complete"
            presentation = .expanded
        } else {
            activeContextLabel = "Context ready"
        }
    }

    func resetDemo() {
        demoTask?.cancel()
        peekTask?.cancel()
        nudges = Self.demoNudges()
        isFocusMode = false
        recapMessage = nil
        activeContextLabel = "Context ready"
        captureDraft = ""
        capturePreview = nil
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

    private func showPeekTemporarily() {
        peekTask?.cancel()
        presentation = .peek
        peekTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled, presentation == .peek else { return }
            presentation = .collapsed
        }
    }

    private func shortRecap(for titles: [String]) -> String {
        guard let first = titles.first else { return "Nothing needs your attention." }
        if titles.count == 1 { return first }
        return "\(first) · \(titles.count - 1) more"
    }

    private func priorityRank(_ priority: NudgePriority) -> Int {
        switch priority {
        case .urgent: 0
        case .actionable: 1
        case .informational: 2
        }
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
}
