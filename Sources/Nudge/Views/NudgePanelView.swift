import AppKit
import SwiftUI

enum NudgePanelLayout {
    static let glassViewportInset: CGFloat = 96
    static let standardContentWidth: CGFloat = 360
    static let captureContentWidth: CGFloat = 408
    static let contentHorizontalPadding: CGFloat = 12
    static let surfaceRightMargin: CGFloat = 18
    static let surfaceTopMargin: CGFloat = 54
}

struct NudgePanelView: View {
    @Bindable var store: NudgeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var displayedBatch: NudgeStore.SurfacedBatch?
    @State private var arrivalPhase: ArrivalPhase = .idle

    private let glassSpacing: CGFloat = 12
    private let surfaceGap: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            GlassEffectContainer(spacing: glassSpacing) {
                VStack(spacing: incomingNudges.isEmpty ? 0 : surfaceGap) {
                    primaryContent
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 44,
                            maxHeight: primarySurfaceHeight(in: proxy.size.height)
                        )
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                        .glassEffectID("nudge-primary-surface", in: glassNamespace)

                    if !incomingNudges.isEmpty, let displayedBatch {
                        IncomingNudgeSurface(
                            items: incomingNudges,
                            batch: displayedBatch,
                            store: store
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: resolvedIncomingHeight(in: proxy.size.height))
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        .glassEffectID(displayedBatch.id, in: glassNamespace)
                        .glassEffectTransition(.materialize)
                        .scaleEffect(arrivalPhase == .absorbing ? 0.985 : 1, anchor: .topTrailing)
                        .offset(y: arrivalPhase == .absorbing ? -8 : 0)
                        .opacity(arrivalPhase == .absorbing ? 0.12 : 1)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .padding(NudgePanelLayout.glassViewportInset)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: store.presentation)
        .task(id: store.surfacedBatch?.id) {
            guard let batch = store.surfacedBatch else { return }
            await present(batch)
        }
    }

    private var cornerRadius: CGFloat {
        store.presentation == .collapsed ? 14 : 16
    }

    @ViewBuilder
    private var primaryContent: some View {
        Group {
            switch store.presentation {
            case .collapsed:
                CollapsedContent(items: settledActiveNudges, store: store)
            case .peek:
                PeekContent(latest: settledActiveNudges.last, store: store)
            case .expanded:
                ExpandedContent(activeNudges: settledActiveNudges, store: store)
            case .capture:
                CaptureView(store: store)
            }
        }
        .transition(.opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var incomingNudges: [NudgeItem] {
        guard let displayedBatch else { return [] }
        let ids = Set(displayedBatch.nudgeIDs)
        return store.activeNudges.filter { ids.contains($0.id) }
    }

    private var settledActiveNudges: [NudgeItem] {
        let incomingIDs = Set(incomingNudges.map(\.id))
        return store.activeNudges.filter { !incomingIDs.contains($0.id) }
    }

    private var desiredIncomingHeight: CGFloat {
        guard !incomingNudges.isEmpty else { return 0 }
        let batchHeaderHeight: CGFloat = incomingNudges.count > 1 ? 30 : 0
        return CGFloat(incomingNudges.count * 40) + batchHeaderHeight + 12
    }

    private func resolvedIncomingHeight(in availableHeight: CGFloat) -> CGFloat {
        min(desiredIncomingHeight, max(0, availableHeight - 44 - surfaceGap))
    }

    private func primarySurfaceHeight(in availableHeight: CGFloat) -> CGFloat {
        guard !incomingNudges.isEmpty else { return availableHeight }
        return max(44, availableHeight - resolvedIncomingHeight(in: availableHeight) - surfaceGap)
    }

    @MainActor
    private func present(_ batch: NudgeStore.SurfacedBatch) async {
        let isGroupedArrival = batch.nudgeIDs.count > 1
        let readableHold: Duration = reduceMotion
            ? .milliseconds(250)
            : (isGroupedArrival ? .milliseconds(1_400) : .seconds(1))
        let absorptionDuration: TimeInterval = isGroupedArrival ? 0.44 : 0.3

        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            displayedBatch = batch
            arrivalPhase = .presenting
        }

        guard await wait(for: readableHold) else { return }

        withAnimation(reduceMotion ? nil : .smooth(duration: absorptionDuration)) {
            arrivalPhase = .absorbing
        }

        guard await wait(
            for: reduceMotion
                ? .milliseconds(50)
                : .milliseconds(Int(absorptionDuration * 1_000))
        ) else { return }

        withAnimation(reduceMotion ? nil : .snappy(duration: 0.36)) {
            displayedBatch = nil
            arrivalPhase = .idle
        }
        store.acknowledgeSurfacedBatch(batch.id)
    }

    private func wait(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

private enum ArrivalPhase {
    case idle
    case presenting
    case absorbing
}

private struct CollapsedContent: View {
    let items: [NudgeItem]
    @Bindable var store: NudgeStore

    var body: some View {
        if items.isEmpty {
            HStack(spacing: 9) {
                Button(action: store.showExpanded) {
                    HStack(spacing: 9) {
                        Image(systemName: store.deferredCount > 0 ? "moon.fill" : "checkmark.circle")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(store.deferredCount > 0 ? Color.indigo : Color.secondary)
                            .frame(width: 20)

                        Text(
                            store.deferredCount > 0
                                ? "\(store.deferredCount) held during Focus"
                                : "All Clear"
                        )
                        .font(.body.weight(.medium))

                        Spacer()

                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        NudgeListRow(
                            item: item,
                            store: store,
                            isMuted: item.id != items.last?.id,
                            showsExpandControl: item.id == items.last?.id
                        )
                        .id(item.id)
                        .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct PeekContent: View {
    let latest: NudgeItem?
    @Bindable var store: NudgeStore

    var body: some View {
        Button(action: store.showExpanded) {
            HStack(spacing: 12) {
                Image(systemName: latest?.priority == .urgent ? "exclamationmark.circle.fill" : "sparkles")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(latest?.priority == .urgent ? .orange : .accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(latest?.title ?? "A nudge is ready")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(latest?.detail ?? store.activeContextLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }
}

private struct ExpandedContent: View {
    let activeNudges: [NudgeItem]
    @Bindable var store: NudgeStore

    var body: some View {
        VStack(spacing: 0) {
            header

            if let recap = store.recapMessage {
                FocusRecap(message: recap)
                    .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
                    .padding(.bottom, 8)
            }

            if activeNudges.isEmpty && store.futureNudges.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(activeNudges) { item in
                                NudgeListRow(
                                    item: item,
                                    store: store,
                                    isMuted: store.focusedNudgeID != nil && store.focusedNudgeID != item.id
                                )
                                .id(item.id)
                                .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
                                .background {
                                    if store.focusedNudgeID == item.id {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.13))
                                    }
                                }
                            }

                            if !store.futureNudges.isEmpty {
                                HStack {
                                    Text("Upcoming")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
                                .padding(.top, 9)
                                .padding(.bottom, 4)

                                ForEach(store.futureNudges) { item in
                                    NudgeListRow(
                                        item: item,
                                        store: store,
                                        displayedAt: item.fallbackAt,
                                        isMuted: true
                                    )
                                    .id(item.id)
                                    .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: activeNudges.map(\.id)) { _, ids in
                        guard let latestID = ids.last else { return }
                        withAnimation(.snappy(duration: 0.3)) {
                            proxy.scrollTo(latestID, anchor: .bottom)
                        }
                    }
                }
            }

            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Nudge")
                .font(.headline)

            Spacer()

            Button {
                store.setFocusMode(!store.isFocusMode)
            } label: {
                Label(
                    store.isFocusMode ? "Focused" : "Focus",
                    systemImage: store.isFocusMode ? "moon.fill" : "moon"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(store.isFocusMode ? .indigo : .accentColor)

            Button(action: store.collapse) {
                Image(systemName: "chevron.right")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help("Collapse")
        }
        .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Label("All Clear", systemImage: "checkmark.circle")
                .font(.headline)
            Text("Nudge will appear when something becomes useful.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Button("New Nudge", systemImage: "plus", action: store.showCapture)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            Spacer()

            Text("⌥ Space")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct IncomingNudgeSurface: View {
    let items: [NudgeItem]
    let batch: NudgeStore.SurfacedBatch
    @Bindable var store: NudgeStore

    var body: some View {
        VStack(spacing: 0) {
            if items.count > 1 {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)

                    Text("\(items.count) nudges arrived together")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
                .frame(height: 30)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        NudgeListRow(item: item, store: store)
                            .id(item.id)
                            .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            items.count == 1
                ? "New nudge"
                : "\(items.count) nudges arrived together"
        )
        .accessibilityIdentifier("incoming-nudge-batch-\(batch.id.uuidString)")
    }
}

private struct NudgeListRow: View {
    let item: NudgeItem
    @Bindable var store: NudgeStore
    var displayedAt: Date? = nil
    var isMuted = false
    var showsExpandControl = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            timelineMarker
                .frame(width: 66, alignment: .trailing)

            ZStack {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.7))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .overlay {
                        Circle()
                            .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 0.5)
                    }
                    .frame(width: 18, height: 18)

                completionButton
            }
            .frame(width: 20)
            .frame(maxHeight: .infinity)

            Text(item.title)
                .font(.body.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(isMuted ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)

            if let url = item.primaryURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.forward")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Open Link")
                .padding(.leading, 5)
            }

            if showsExpandControl {
                Button(action: store.showExpanded) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Show Upcoming and New Nudge")
                .padding(.leading, 5)
            }
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .contain)
    }

    private var completionButton: some View {
        Button {
            store.complete(item.id)
        } label: {
            Image(systemName: "circle")
                .symbolRenderingMode(.hierarchical)
                .font(.body)
                .foregroundStyle(priorityColor)
                .frame(width: 20, height: 20)
                .symbolEffect(.bounce, value: store.focusedNudgeID == item.id)
        }
        .buttonStyle(.borderless)
        .help("Mark Complete")
    }

    @ViewBuilder
    private var timelineMarker: some View {
        switch item.invocation {
        case .temporal:
            Text((displayedAt ?? item.timelineDate).formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        case .contextual(let context):
            HStack(spacing: 3) {
                Image(systemName: context.symbol)
                    .symbolRenderingMode(.hierarchical)

                Text("Opened")
            }
                .font(.caption2.weight(.medium))
                .foregroundStyle(isMuted ? Color.secondary : Color.accentColor)
                .help("Triggered by \(context.label.lowercased())")
        }
    }

    private var priorityColor: Color {
        if isMuted { return .secondary }

        switch item.priority {
        case .urgent: return .orange
        case .actionable: return .accentColor
        case .informational: return .secondary
        }
    }
}

private struct FocusRecap: View {
    let message: String

    var body: some View {
        GroupBox {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("While You Focused", systemImage: "moon.stars.fill")
                .font(.caption.weight(.medium))
        }
    }
}
