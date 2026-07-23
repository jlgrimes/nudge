import AppKit
import SwiftUI

struct NudgePanelView: View {
    @Bindable var store: NudgeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Group {
                switch store.presentation {
                case .collapsed:
                    CollapsedContent(store: store)
                case .peek:
                    PeekContent(store: store)
                case .expanded:
                    ExpandedContent(store: store)
                case .capture:
                    CaptureView(store: store)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .topTrailing)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelSurface)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .padding(.horizontal, store.presentation == .collapsed ? 0 : 4)
        .padding(.vertical, store.presentation == .collapsed ? 0 : 4)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: store.presentation)
    }

    private var cornerRadius: CGFloat {
        store.presentation == .collapsed ? 14 : 16
    }

    private var panelSurface: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 0.5)
            }
    }
}

private struct CollapsedContent: View {
    @Bindable var store: NudgeStore

    var body: some View {
        if store.activeNudges.isEmpty {
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
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(store.activeNudges) { item in
                NudgeListRow(
                    item: item,
                    store: store,
                    isMuted: item.id != store.activeNudges.last?.id,
                    showsExpandControl: item.id == store.activeNudges.last?.id
                )
                .id(item.id)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 8))
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
        }
    }
}

private struct PeekContent: View {
    @Bindable var store: NudgeStore

    private var latest: NudgeItem? { store.activeNudges.first }

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
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }
}

private struct ExpandedContent: View {
    @Bindable var store: NudgeStore

    var body: some View {
        VStack(spacing: 0) {
            header

            if let recap = store.recapMessage {
                FocusRecap(message: recap)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            if store.activeNudges.isEmpty && store.futureNudges.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    List {
                        Section {
                            ForEach(store.activeNudges) { item in
                                NudgeListRow(
                                    item: item,
                                    store: store,
                                    isMuted: store.focusedNudgeID != nil && store.focusedNudgeID != item.id
                                )
                                .id(item.id)
                                .listRowInsets(.init(top: 0, leading: 6, bottom: 0, trailing: 8))
                                .listRowBackground(
                                    store.focusedNudgeID == item.id
                                        ? Color.accentColor.opacity(0.13)
                                        : Color.clear
                                )
                            }
                        }

                        if !store.futureNudges.isEmpty {
                            Section("Upcoming") {
                                ForEach(store.futureNudges) { item in
                                    NudgeListRow(
                                        item: item,
                                        store: store,
                                        displayedAt: item.fallbackAt,
                                        isMuted: true
                                    )
                                    .id(item.id)
                                    .listRowInsets(.init(top: 0, leading: 6, bottom: 0, trailing: 8))
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.automatic)
                    .onChange(of: store.activeNudges.map(\.id)) { _, ids in
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
        .padding(.horizontal, 14)
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
        .padding(.horizontal, 12)
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
                    .fill(.regularMaterial)
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
