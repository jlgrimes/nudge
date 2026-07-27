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

    enum DebugScenario: String, CaseIterable {
        case day
        case single
        case multiple
        case focus
    }

    private enum CreationSource {
        case quickAdd
        case capture
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
    var quickAddDraft = ""
    var isQuickAddExpanded = false {
        didSet { presentationDidChange?() }
    }
    var fallbackDays = 2
    var isListening = false
    var isInferring = false
    var inferenceErrorMessage: String?
    var lastInferenceProviderID: String?
    var activeDebugScenario: DebugScenario?
    var emphasizedNudgeIDs: Set<UUID> = [] {
        didSet { panelLayoutDidChange?() }
    }
    var surfacedBatchNudgeIDs: Set<UUID> = [] {
        didSet { panelLayoutDidChange?() }
    }
    var emphasisBatchID: UUID? {
        didSet { panelLayoutDidChange?() }
    }

    @ObservationIgnored var presentationDidChange: (() -> Void)?
    @ObservationIgnored var panelLayoutDidChange: (() -> Void)?
    @ObservationIgnored var debugScenarioDidRun: (() -> Void)?
    @ObservationIgnored private let inferenceService: NudgeInferenceService
    @ObservationIgnored private var inferenceTask: Task<Void, Never>?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private var emphasisTask: Task<Void, Never>?

    init(
        seedDemoData: Bool = true,
        inferenceService: NudgeInferenceService = .live
    ) {
        self.nudges = seedDemoData ? Self.demoNudges() : []
        self.inferenceService = inferenceService
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
        isQuickAddExpanded = false
        quickAddDraft = ""
        captureDraft = ""
        capturePreview = nil
        inferenceErrorMessage = nil
        isListening = false
        presentation = .capture
    }

    func showQuickAdd() {
        peekTask?.cancel()
        quickAddDraft = ""
        inferenceErrorMessage = nil
        isQuickAddExpanded = true
    }

    func cancelQuickAdd() {
        quickAddDraft = ""
        inferenceErrorMessage = nil
        isQuickAddExpanded = false
    }

    func createNudgeFromQuickAdd() {
        inferenceTask?.cancel()
        inferenceTask = Task { @MainActor [weak self] in
            await self?.createNudgeFromQuickAddNow()
        }
    }

    func createNudgeFromQuickAddNow() async {
        let request = quickAddDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        await createNudge(from: request, source: .quickAdd)
    }

    func createNudgeFromCapture() {
        inferenceTask?.cancel()
        inferenceTask = Task { @MainActor [weak self] in
            await self?.createNudgeFromCaptureNow()
        }
    }

    func createNudgeFromCaptureNow() async {
        let request = captureDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        await createNudge(from: request, source: .capture)
    }

    func commitCapturePreview() {
        guard let item = capturePreview else { return }
        nudges.append(item)
        capturePreview = nil
        captureDraft = ""
        inferenceErrorMessage = nil
        activeContextLabel = "Saved · waiting for context"
        presentation = .expanded
    }

    func reviseCapturePreview() {
        guard let item = capturePreview else { return }
        captureDraft = item.originalRequest
        capturePreview = nil
        inferenceErrorMessage = nil
        activeContextLabel = "Edit your request"
    }

    private func createNudge(from request: String, source: CreationSource) async {
        guard !isInferring else { return }

        isInferring = true
        inferenceErrorMessage = nil
        let referenceDate = Date.now
        defer { isInferring = false }

        do {
            let response = try await inferenceService.infer(
                text: request,
                fallbackDays: fallbackDays,
                referenceDate: referenceDate
            )
            guard !Task.isCancelled else { return }

            lastInferenceProviderID = response.providerID
            let inference = response.result
            let fallbackAt = inference.fallbackAt
                ?? Calendar.current.date(
                    byAdding: .day,
                    value: fallbackDays,
                    to: referenceDate
                )
                ?? referenceDate

            switch source {
            case .quickAdd:
                let item = makeNudge(
                    request: request,
                    inference: inference,
                    fallbackAt: fallbackAt
                )
                quickAddDraft = ""
                withAnimation(.smooth(duration: 0.28)) {
                    isQuickAddExpanded = false
                    nudges.append(item)
                    if presentation == .peek {
                        presentation = .collapsed
                    }
                }
                activeContextLabel = "Added · waiting for context"

            case .capture:
                capturePreview = makeNudge(
                    request: request,
                    inference: inference,
                    fallbackAt: fallbackAt
                )
                activeContextLabel = "Review inferred nudge"
            }
        } catch is CancellationError {
            return
        } catch {
            inferenceErrorMessage = error.localizedDescription
            activeContextLabel = "Couldn’t understand that nudge"
        }
    }

    private func makeNudge(
        request: String,
        inference: InferenceResult,
        fallbackAt: Date,
        status: NudgeStatus = .pending,
        surfacedAt: Date? = nil
    ) -> NudgeItem {
        NudgeItem(
            originalRequest: request,
            title: inference.title,
            detail: inference.detail,
            priority: inference.priority,
            conditions: inference.conditions,
            fallbackAt: fallbackAt,
            status: status,
            surfacedAt: surfacedAt,
            action: inference.action,
            canInterruptFocus: inference.canInterruptFocus
        )
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
            let matches = item.conditions.contains { $0.matches(event) }
            return matches ? item.id : nil
        }

        guard !matchingIDs.isEmpty else { return }

        withAnimation(.smooth(duration: 0.28)) {
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
        emphasize(activeMatchingIDs)

        if wasExpanded || presentation == .collapsed {
            panelLayoutDidChange?()
        } else {
            showPeekTemporarily()
        }
    }

    func complete(_ id: UUID) {
        guard let index = nudges.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeOut(duration: 0.24)) {
            nudges[index].status = .completed
            removeEmphasis(for: id)
        }
        if activeNudges.isEmpty {
            collapse()
        }
    }

    func dismiss(_ id: UUID) {
        guard let index = nudges.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeOut(duration: 0.24)) {
            nudges[index].status = .dismissed
            removeEmphasis(for: id)
        }
    }

    private func removeEmphasis(for id: UUID) {
        emphasizedNudgeIDs.remove(id)
        surfacedBatchNudgeIDs.remove(id)
        if surfacedBatchNudgeIDs.count < 2 {
            surfacedBatchNudgeIDs = []
            emphasisBatchID = nil
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

        emphasize(deferredIDs)

        if !deferredIDs.isEmpty {
            recapMessage = nil
            activeContextLabel = "While you were away"
            presentation = .collapsed
        } else {
            activeContextLabel = "Context ready"
        }
    }

    func resetDemo() {
        inferenceTask?.cancel()
        demoTask?.cancel()
        peekTask?.cancel()
        emphasisTask?.cancel()
        nudges = Self.demoNudges()
        emphasizedNudgeIDs = []
        surfacedBatchNudgeIDs = []
        emphasisBatchID = nil
        isFocusMode = false
        isInferring = false
        inferenceErrorMessage = nil
        lastInferenceProviderID = nil
        recapMessage = nil
        activeContextLabel = "Context ready"
        captureDraft = ""
        capturePreview = nil
        quickAddDraft = ""
        isQuickAddExpanded = false
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

            demoTask = Task { @MainActor [weak self] in
                guard let self else { return }
                for item in dayNudges.dropFirst() {
                    try? await Task.sleep(for: .milliseconds(900))
                    guard !Task.isCancelled else { return }
                    nudges.append(item)
                    emphasize([item.id])
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
                withAnimation(.smooth(duration: 0.28)) {
                    nudges[index].surfacedAt = .now
                    nudges[index].invocation = .contextual(.messaging)
                    nudges[index].status = .active
                }
                emphasize([nudges[index].id])
                activeContextLabel = "Slack is active · nudge refreshed"
            }

        case .multiple:
            let incomingNudges = Self.multipleScenarioNudges()
            nudges = Self.settledScenarioNudges()
            activeContextLabel = "Timeline · waiting for notifications"
            presentation = .collapsed

            demoTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.28)) {
                    nudges.append(contentsOf: incomingNudges)
                }
                emphasize(incomingNudges.map(\.id))
                activeContextLabel = "\(incomingNudges.count) nudges arrived together"
            }

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
        inferenceTask?.cancel()
        demoTask?.cancel()
        peekTask?.cancel()
        emphasisTask?.cancel()
        activeDebugScenario = scenario
        nudges = []
        emphasizedNudgeIDs = []
        surfacedBatchNudgeIDs = []
        emphasisBatchID = nil
        isFocusMode = false
        isInferring = false
        inferenceErrorMessage = nil
        lastInferenceProviderID = nil
        recapMessage = nil
        captureDraft = ""
        capturePreview = nil
        quickAddDraft = ""
        isQuickAddExpanded = false
        activeContextLabel = "Context ready"
        presentation = .collapsed
    }

    private func emphasize(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }

        emphasisTask?.cancel()
        let incomingIDs = Set(ids)
        let isBatch = incomingIDs.count > 1

        if isBatch {
            emphasizedNudgeIDs = []
            surfacedBatchNudgeIDs = incomingIDs
            emphasisBatchID = UUID()
        } else {
            surfacedBatchNudgeIDs = []
            emphasisBatchID = nil
            emphasizedNudgeIDs = incomingIDs
        }

        emphasisTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }

            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                emphasizedNudgeIDs = []
                surfacedBatchNudgeIDs = []
                emphasisBatchID = nil
            } else if isBatch {
                withAnimation(.smooth(duration: 0.36)) {
                    surfacedBatchNudgeIDs = []
                    emphasisBatchID = nil
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) {
                    emphasizedNudgeIDs = []
                }
            }
        }
    }
}
