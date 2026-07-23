import AppKit
import SwiftUI

enum NudgePanelLayout {
    static let glassViewportInset: CGFloat = 96
    static let standardContentWidth: CGFloat = 360
    static let captureContentWidth: CGFloat = 408
    static let contentHorizontalPadding: CGFloat = 12
    static let surfaceCornerRadius: CGFloat = 16
    static let focusCornerRadius: CGFloat = 12
    static let surfaceTopPadding: CGFloat = 6
    static let surfaceBottomPadding: CGFloat = 4
    static let glassSurfaceSpacing: CGFloat = 10
    static let quickAddHeight: CGFloat = 44
    static let rowOuterHorizontalPadding: CGFloat = 8
    static let rowInnerHorizontalPadding: CGFloat = 12
    static let timelineMarkerWidth: CGFloat = 72
    static let timelineMarkerSpacing: CGFloat = 7
    static let surfaceRightMargin: CGFloat = 18
    static let surfaceTopMargin: CGFloat = 54
}

struct NudgePanelView: View {
    @Bindable var store: NudgeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let showsQuickAdd = store.presentation != .capture
            let quickAddSpace = showsQuickAdd
                ? NudgePanelLayout.quickAddHeight + NudgePanelLayout.glassSurfaceSpacing
                : 0

            GlassEffectContainer(spacing: NudgePanelLayout.glassSurfaceSpacing) {
                VStack(alignment: .trailing, spacing: NudgePanelLayout.glassSurfaceSpacing) {
                    primaryContent
                        .frame(maxWidth: .infinity)
                        .frame(height: max(44, proxy.size.height - quickAddSpace))
                        .glassEffect(
                            .regular,
                            in: .rect(cornerRadius: NudgePanelLayout.surfaceCornerRadius)
                        )

                    if showsQuickAdd {
                        QuickAddGlassControl(store: store)
                            .frame(
                                width: store.isQuickAddExpanded
                                    ? proxy.size.width
                                    : NudgePanelLayout.quickAddHeight,
                                height: NudgePanelLayout.quickAddHeight
                            )
                            .glassEffect(.regular, in: .capsule)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .padding(NudgePanelLayout.glassViewportInset)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: store.presentation)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: store.isQuickAddExpanded)
    }

    @ViewBuilder
    private var primaryContent: some View {
        Group {
            switch store.presentation {
            case .collapsed:
                CollapsedContent(items: store.activeNudges, store: store)
            case .peek:
                PeekContent(latest: store.activeNudges.last, store: store)
            case .expanded:
                ExpandedContent(activeNudges: store.activeNudges, store: store)
            case .capture:
                CaptureView(store: store)
            }
        }
        .transition(.opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QuickAddGlassControl: View {
    @Bindable var store: NudgeStore
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Group {
            if store.isQuickAddExpanded {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("Remind me to", text: $store.quickAddDraft)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .onSubmit(store.createNudgeFromQuickAdd)

                    Button(action: store.cancelQuickAdd) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel")
                }
                .padding(.horizontal, 13)
            } else {
                Button(action: store.showQuickAdd) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Add Nudge")
                .accessibilityLabel("Add Nudge")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.isQuickAddExpanded) { _, isExpanded in
            guard isExpanded else {
                isInputFocused = false
                return
            }
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
        .onExitCommand(perform: store.cancelQuickAdd)
    }
}

private struct CollapsedContent: View {
    let items: [NudgeItem]
    @Bindable var store: NudgeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .padding(.horizontal, NudgePanelLayout.rowOuterHorizontalPadding)
                        .transition(rowTransition)
                    }
                }
                .padding(.top, NudgePanelLayout.surfaceTopPadding)
                .padding(.bottom, NudgePanelLayout.surfaceBottomPadding)
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.28),
                    value: items.map(\.id)
                )
            }
            .scrollIndicators(.never)
        }
    }

    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                                    isMuted: item.id != activeNudges.last?.id
                                )
                                .id(item.id)
                                .padding(.horizontal, NudgePanelLayout.rowOuterHorizontalPadding)
                                .transition(rowTransition)
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
                                    .padding(.horizontal, NudgePanelLayout.rowOuterHorizontalPadding)
                                }
                            }
                        }
                        .animation(
                            reduceMotion ? nil : .smooth(duration: 0.28),
                            value: activeNudges.map(\.id)
                        )
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: activeNudges.map(\.id)) { _, ids in
                        guard let latestID = ids.last else { return }
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                            proxy.scrollTo(latestID, anchor: .bottom)
                        }
                    }
                }
            }

        }
    }

    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
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

}

private struct NudgeListRow: View {
    let item: NudgeItem
    @Bindable var store: NudgeStore
    var displayedAt: Date? = nil
    var isMuted = false
    var showsExpandControl = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isCompleting = false
    @State private var emphasisPulse = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: beginCompletion) {
                HStack(alignment: .center, spacing: 0) {
                    timelineMarker
                        .frame(
                            width: NudgePanelLayout.timelineMarkerWidth,
                            height: 40,
                            alignment: .center
                        )
                        .padding(.trailing, NudgePanelLayout.timelineMarkerSpacing)

                    titleLabel
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)

                    if trailingActionWidth > 0 {
                        Color.clear
                            .frame(width: trailingActionWidth, height: 20)
                    }
                }
                .padding(.horizontal, NudgePanelLayout.rowInnerHorizontalPadding)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Mark Complete")
            .accessibilityLabel("Complete \(item.title)")

            trailingActions
                .padding(.trailing, NudgePanelLayout.rowInnerHorizontalPadding)
        }
        .frame(minHeight: 40)
        .contentShape(.rect)
        .background {
            RoundedRectangle(cornerRadius: NudgePanelLayout.focusCornerRadius, style: .continuous)
                .fill(rowBackgroundColor)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: isEmphasized)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
        .onAppear(perform: pulseIfNeeded)
        .onChange(of: isEmphasized) { _, emphasized in
            if emphasized { pulseIfNeeded() }
        }
    }

    @ViewBuilder
    private var titleLabel: some View {
        Group {
            if isMuted && !isEmphasized {
                ZStack(alignment: .leading) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .opacity(isHovered ? 0 : 1)

                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .opacity(isHovered ? 1 : 0)
                        .accessibilityHidden(true)
                }
            } else {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
        .overlay {
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.primary.opacity(0.72))
                    .frame(width: proxy.size.width, height: 1.5)
                    .scaleEffect(x: isCompleting ? 1 : 0, anchor: .leading)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .allowsHitTesting(false)
        }
        .opacity(isCompleting ? 0.66 : 1)
    }

    @ViewBuilder
    private var trailingActions: some View {
        HStack(spacing: 5) {
            if let url = item.primaryURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.forward")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Open Link")
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
            }
        }
        .padding(.leading, trailingActionWidth > 0 ? 5 : 0)
    }

    private var trailingActionWidth: CGFloat {
        let linkWidth: CGFloat = item.primaryURL == nil ? 0 : 25
        let expandWidth: CGFloat = showsExpandControl ? 21 : 0
        return linkWidth + expandWidth
    }

    private func beginCompletion() {
        guard !isCompleting else { return }

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.26)) {
            isCompleting = true
        }

        Task { @MainActor in
            try? await Task.sleep(
                for: reduceMotion ? .milliseconds(80) : .milliseconds(320)
            )
            guard !Task.isCancelled else { return }
            store.complete(item.id)
        }
    }

    private var timelineMarker: some View {
        HStack(alignment: .center, spacing: 7) {
            Group {
                switch item.invocation {
                case .temporal:
                    Image(systemName: "clock")
                        .foregroundStyle(
                            isEmphasized ? Color.primary : Color.primary.opacity(0.35)
                        )
                case .contextual(let context):
                    Image(systemName: context.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isEmphasized ? Color.primary : Color.secondary)
                        .help("Triggered by \(context.label.lowercased())")
                }
            }
            .frame(width: 13, alignment: .leading)
            .symbolEffect(.pulse.wholeSymbol, value: emphasisPulse)
            .symbolEffectsRemoved(reduceMotion)

            Text((displayedAt ?? item.timelineDate).formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isEmphasized ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .font(.caption2.weight(.medium))
    }

    private var rowBackgroundColor: Color {
        return Color.primary.opacity(isHovered || isCompleting ? 0.055 : 0)
    }

    private var isEmphasized: Bool {
        store.emphasizedNudgeIDs.contains(item.id)
    }

    private func pulseIfNeeded() {
        guard isEmphasized, !reduceMotion else { return }
        emphasisPulse += 1
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
