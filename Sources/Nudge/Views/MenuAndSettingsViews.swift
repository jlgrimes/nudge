import AppKit
import SwiftUI

struct NudgeMenuView: View {
    @Bindable var store: NudgeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nudge")
                        .font(.headline)
                    Text("\(store.activeNudges.count) active · \(store.pendingCount) waiting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title3)
            }

            Divider()

            Button("Show Nudge", systemImage: "rectangle.on.rectangle") {
                store.showExpanded()
            }
            Button("Add a nudge…", systemImage: "plus") {
                store.showCapture()
            }
            Button(
                store.isFocusMode ? "End Focus" : "Start Focus",
                systemImage: store.isFocusMode ? "moon.fill" : "moon"
            ) {
                store.setFocusMode(!store.isFocusMode)
            }

            Divider()

            Text("Simulate context")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Button("Slack becomes active", systemImage: "message.fill") {
                store.receive(context: .slack)
            }
            Button("Visit amazon.com", systemImage: "cart.fill") {
                store.receive(context: .amazon)
            }
            Button("Urgent calendar event", systemImage: "calendar.badge.exclamationmark") {
                store.receive(context: .calendar)
            }

            Divider()

            Button("Run 10-second demo", systemImage: "play.fill") {
                store.runDemo()
            }
            Button("Reset demo", systemImage: "arrow.counterclockwise") {
                store.resetDemo()
            }

            Divider()

            SettingsLink {
                Text("Settings…")
            }
            Button("Quit Nudge", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 260)
    }
}

struct NudgeSettingsView: View {
    @Bindable var store: NudgeStore

    var body: some View {
        Form {
            Section("Fallback") {
                Stepper("Remind after \(store.fallbackDays) days", value: $store.fallbackDays, in: 1...7)
                Text("If no useful context appears, Nudge falls back to an ordinary reminder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Capture") {
                LabeledContent("Global shortcut", value: "⌥ Space")
                Text("Voice transcription and contextual events are mocked in this prototype.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 260)
    }
}
