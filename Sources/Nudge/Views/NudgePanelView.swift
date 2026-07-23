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
        .padding(4)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: store.presentation)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.activeNudges.count)
    }

    private var cornerRadius: CGFloat {
        store.presentation == .collapsed ? 28 : 16
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
        Button(action: store.showExpanded) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: store.isFocusMode ? "moon.fill" : "sparkles")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(store.isFocusMode ? Color.indigo : Color.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if store.bubbleCount > 0 {
                    Text("\(store.bubbleCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(store.isFocusMode ? Color.indigo : Color.accentColor, in: .circle)
                        .padding(3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Open Nudge, \(store.bubbleCount) items")
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

            if store.activeNudges.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    List(store.activeNudges) { item in
                        NudgeListRow(item: item, store: store)
                            .id(item.id)
                            .listRowInsets(.init(top: 9, leading: 12, bottom: 9, trailing: 12))
                            .listRowBackground(Color.clear)
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
            VStack(alignment: .leading, spacing: 1) {
                Text("Nudge")
                    .font(.headline)
                Text(store.activeContextLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

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
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct NudgeListRow: View {
    let item: NudgeItem
    @Bindable var store: NudgeStore

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.complete(item.id)
            } label: {
                Image(systemName: leadingSymbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.body)
                    .foregroundStyle(priorityColor)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.priority == .informational ? "Information" : "Complete")

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Text(item.timelineDate.formatted(date: .omitted, time: .shortened))
                        .monospacedDigit()
                    Text("·")
                    Label(item.contextLabel, systemImage: item.triggers.first?.kind.symbol ?? "sparkles")
                        .labelStyle(.titleAndIcon)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

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
        }
    }

    private var leadingSymbol: String {
        switch item.priority {
        case .urgent: "exclamationmark.circle.fill"
        case .actionable: "circle"
        case .informational: "info.circle"
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .urgent: .orange
        case .actionable: .accentColor
        case .informational: .secondary
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
