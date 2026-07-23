import AppKit
import SwiftUI

enum NudgePanelLayout {
    static let glassViewportInset: CGFloat = 96
    static let standardContentWidth: CGFloat = 360
    static let captureContentWidth: CGFloat = 408
    static let contentHorizontalPadding: CGFloat = 12
    static let surfaceCornerRadius: CGFloat = 16
    static let focusCornerRadius: CGFloat = 12
    static let surfaceVerticalPadding: CGFloat = 6
    static let timelineMarkerWidth: CGFloat = 56
    static let timelineMarkerSpacing: CGFloat = 7
    static let surfaceRightMargin: CGFloat = 18
    static let surfaceTopMargin: CGFloat = 54
}

struct NudgePanelView: View {
    @Bindable var store: NudgeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            primaryContent
                .frame(
                    maxWidth: .infinity,
                    minHeight: 44,
                    maxHeight: proxy.size.height
                )
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: NudgePanelLayout.surfaceCornerRadius)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .padding(NudgePanelLayout.glassViewportInset)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: store.presentation)
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
                            isMuted: true,
                            showsExpandControl: item.id == items.last?.id
                        )
                        .id(item.id)
                        .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
                        .transition(.push(from: .bottom))
                    }
                }
                .padding(.vertical, NudgePanelLayout.surfaceVerticalPadding)
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.32),
                    value: items.map(\.id)
                )
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
                                    isMuted: true
                                )
                                .id(item.id)
                                .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
                                .transition(.push(from: .bottom))
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
                        .animation(
                            reduceMotion ? nil : .snappy(duration: 0.32),
                            value: activeNudges.map(\.id)
                        )
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

private struct NudgeListRow: View {
    let item: NudgeItem
    @Bindable var store: NudgeStore
    var displayedAt: Date? = nil
    var isMuted = false
    var showsExpandControl = false
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            timelineMarker
                .frame(width: NudgePanelLayout.timelineMarkerWidth, alignment: .trailing)
                .padding(.trailing, NudgePanelLayout.timelineMarkerSpacing)

            ZStack {
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

            titleLabel
                .lineLimit(2)
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
        .contentShape(.rect)
        .background {
            RoundedRectangle(cornerRadius: NudgePanelLayout.focusCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(isMuted && isHovered ? 0.055 : 0))
        }
        .onHover { hovering in
            guard isMuted else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var titleLabel: some View {
        if isMuted {
            ZStack(alignment: .leading) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 0 : 1)

                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
        } else {
            Text(item.title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
        }
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
