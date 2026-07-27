import Foundation

enum NudgeRuntime {
    static var debugToolsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--debug-scenarios")
            || ProcessInfo.processInfo.environment["NUDGE_DEBUG_PANEL"] == "1"
    }
}

@MainActor
final class NudgeRuntimeController {
    private let store: NudgeStore
    private let persistence: NudgePersistence
    private let maintenanceInterval: Duration
    private var maintenanceTask: Task<Void, Never>?
    private var fallbackPeekTask: Task<Void, Never>?
    private var lastSavedSnapshot: NudgeSnapshot?

    init(
        store: NudgeStore,
        persistence: NudgePersistence = .live,
        maintenanceInterval: Duration = .seconds(1),
        startsAutomatically: Bool = true
    ) {
        self.store = store
        self.persistence = persistence
        self.maintenanceInterval = maintenanceInterval

        if let snapshot = persistence.load() {
            store.nudges = snapshot.nudges
            store.fallbackDays = snapshot.fallbackDays
            store.isFocusMode = snapshot.isFocusMode
            lastSavedSnapshot = snapshot
        } else {
            // The POC seeded fake reminders in the singleton. A normal launch starts
            // with the user's data instead, or an empty timeline on first run.
            store.nudges = []
            store.fallbackDays = 2
            store.isFocusMode = false
        }

        runMaintenance()

        if startsAutomatically {
            startMaintenanceLoop()
        }
    }

    func runMaintenance(now: Date = .now) {
        surfaceDueFallbacks(now: now)
        saveIfNeeded()
    }

    func flush() {
        saveIfNeeded(force: true)
    }

    private func startMaintenanceLoop() {
        maintenanceTask?.cancel()
        let interval = maintenanceInterval

        maintenanceTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                runMaintenance()
            }
        }
    }

    private func surfaceDueFallbacks(now: Date) {
        let dueIDs = store.nudges.compactMap { item -> UUID? in
            guard item.status == .pending, item.fallbackAt <= now else { return nil }
            return item.id
        }

        guard !dueIDs.isEmpty else { return }

        var activeCount = 0
        for (offset, id) in dueIDs.enumerated() {
            guard let index = store.nudges.firstIndex(where: { $0.id == id }) else { continue }

            store.nudges[index].surfacedAt = now.addingTimeInterval(Double(offset) * 0.001)
            store.nudges[index].invocation = .temporal

            if store.isFocusMode && !store.nudges[index].canInterruptFocus {
                store.nudges[index].status = .deferred
            } else {
                store.nudges[index].status = .active
                activeCount += 1
            }
        }

        if activeCount > 0 {
            store.activeContextLabel = activeCount == 1
                ? "Fallback reminder"
                : "\(activeCount) fallback reminders"
            showFallbackPeekIfAppropriate()
        } else {
            store.activeContextLabel = "Focus mode · nudges held quietly"
        }
    }

    private func showFallbackPeekIfAppropriate() {
        guard store.presentation == .collapsed else { return }

        store.presentation = .peek
        fallbackPeekTask?.cancel()
        fallbackPeekTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard
                let self,
                !Task.isCancelled,
                store.presentation == .peek
            else { return }
            store.collapse()
        }
    }

    private func saveIfNeeded(force: Bool = false) {
        let snapshot = NudgeSnapshot(
            nudges: store.nudges,
            fallbackDays: store.fallbackDays,
            isFocusMode: store.isFocusMode
        )

        guard force || snapshot != lastSavedSnapshot else { return }

        do {
            try persistence.save(snapshot)
            lastSavedSnapshot = snapshot
        } catch {
            NSLog("Nudge could not save its state: %@", error.localizedDescription)
        }
    }
}
