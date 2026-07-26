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
            Button("New contextual nudge", systemImage: "plus") {
                store.showCapture()
            }
            Button(
                store.isFocusMode ? "End Focus" : "Start Focus",
                systemImage: store.isFocusMode ? "moon.fill" : "moon"
            ) {
                store.setFocusMode(!store.isFocusMode)
            }

            if NudgeRuntime.debugToolsEnabled {
                Divider()

                Text("Debug contexts")
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
                Button("Run 10-second demo", systemImage: "play.fill") {
                    store.runDemo()
                }
                Button("Reset demo", systemImage: "arrow.counterclockwise") {
                    store.resetDemo()
                }
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
                Text("If a useful context never appears, the nudge surfaces automatically after this delay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Capture") {
                LabeledContent("Global shortcut", value: "⌥ Space")
                Text("App activity is matched locally on this Mac. Nudge does not require Accessibility access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                Text("Your nudges and fallback setting are stored locally in Application Support.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 320)
    }
}
