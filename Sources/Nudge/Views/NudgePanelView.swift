import AppKit
import SwiftUI

struct NudgePanelView: View {
    @Bindable var store: NudgeStore

    var body: some View {
        Group {
            switch store.presentation {
            case .collapsed:
                CollapsedBubble(store: store)
            case .peek:
                PeekView(store: store)
            case .expanded:
                ExpandedNudgeList(store: store)
            case .capture:
                CaptureView(store: store)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
        .padding(6)
        .animation(.smooth(duration: 0.28), value: store.presentation)
        .animation(.easeOut(duration: 0.2), value: store.activeNudges.count)
    }
}

private struct CollapsedBubble: View {
    @Bindable var store: NudgeStore

    var body: some View {
        Button(action: store.showExpanded) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: store.isFocusMode ? "moon.fill" : "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 58, height: 58)
                    .contentShape(Circle())
                    .background(.regularMaterial, in: .circle)
                    .background(
                        (store.isFocusMode ? Color.indigo : Color.accentColor).opacity(0.14),
                        in: .circle
                    )
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 5)

                if store.bubbleCount > 0 {
                    Text("\(store.bubbleCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(store.isFocusMode ? Color.indigo : Color.accentColor, in: .circle)
                        .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1.5))
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Nudge, \(store.bubbleCount) items")
    }
}

private struct PeekView: View {
    @Bindable var store: NudgeStore

    private var latest: NudgeItem? { store.activeNudges.first }

    var body: some View {
        Button(action: store.showExpanded) {
            HStack(spacing: 13) {
                Image(systemName: latest?.priority == .urgent ? "exclamationmark" : "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(latest?.priority == .urgent ? .orange : .primary)
                    .frame(width: 42, height: 42)
                    .background(.primary.opacity(0.08), in: .circle)

                VStack(alignment: .leading, spacing: 4) {
                    Text(latest?.title ?? "A nudge is ready")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(latest?.detail ?? store.activeContextLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 17)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .background(.regularMaterial, in: .rect(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct ExpandedNudgeList: View {
    @Bindable var store: NudgeStore

    var body: some View {
        VStack(spacing: 0) {
            header

            if let recap = store.recapMessage {
                RecapView(message: recap)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            ScrollView {
                LazyVStack(spacing: 9) {
                    if store.activeNudges.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.activeNudges) { item in
                            NudgeRow(item: item, store: store)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            footer
        }
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.17), radius: 18, y: 8)
        }
        .clipShape(.rect(cornerRadius: 28))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(.primary.opacity(0.07), in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                Text("Nudge")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(store.activeContextLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                store.setFocusMode(!store.isFocusMode)
            } label: {
                Image(systemName: store.isFocusMode ? "moon.fill" : "moon")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.isFocusMode ? Color.indigo : Color.primary)
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.07), in: .circle)
            }
            .buttonStyle(.plain)
            .help(store.isFocusMode ? "End Focus" : "Start Focus")

            Button(action: store.collapse) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.07), in: .circle)
            }
            .buttonStyle(.plain)
            .help("Collapse")
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text("All clear")
                .font(.system(size: 14, weight: .semibold))
            Text("Nudge will surface something when it becomes useful.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: store.showCapture) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add a nudge")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 13)
                .frame(height: 32)
                .background(Color.accentColor.opacity(0.15), in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 4) {
                Text("⌥")
                Text("Space")
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.primary.opacity(0.06), in: .rect(cornerRadius: 6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }
}

private struct NudgeRow: View {
    let item: NudgeItem
    @Bindable var store: NudgeStore

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button {
                store.complete(item.id)
            } label: {
                Image(systemName: item.priority == .informational ? "info.circle" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(priorityColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.priority == .informational ? "Information" : "Complete")

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(2)

                Text(item.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Label(item.contextLabel, systemImage: item.triggers.first?.kind.symbol ?? "sparkles")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 21)
                    .background(.primary.opacity(0.055), in: .capsule)
            }

            Spacer(minLength: 4)

            if let url = item.primaryURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(.primary.opacity(0.065), in: .circle)
                }
                .buttonStyle(.plain)
                .help("Open link")
            }
        }
        .padding(12)
        .background(.primary.opacity(0.052), in: .rect(cornerRadius: 16))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(priorityColor)
                .frame(width: 3, height: 28)
                .padding(.leading, 2)
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

private struct RecapView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text("While you focused")
                    .font(.system(size: 11, weight: .bold))
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(11)
        .background(Color.indigo.opacity(0.1), in: .rect(cornerRadius: 14))
    }
}
