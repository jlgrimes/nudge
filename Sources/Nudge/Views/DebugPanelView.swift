import SwiftUI

struct DebugPanelView: View {
    @Bindable var store: NudgeStore

    var body: some View {
        HStack(spacing: 8) {
            Label("Scenarios", systemImage: "wrench.and.screwdriver")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)

            Divider()
                .frame(height: 26)

            scenarioButton(
                "Day Stream",
                systemImage: "clock",
                scenario: .day
            )
            scenarioButton(
                "Single Notification",
                systemImage: "bell",
                scenario: .single
            )
            scenarioButton(
                "Multiple Notifications",
                systemImage: "square.stack.3d.up",
                scenario: .multiple
            )
            scenarioButton(
                "Focus Mode",
                systemImage: "moon",
                scenario: .focus
            )
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 0.5)
                }
        }
        .clipShape(.rect(cornerRadius: 14))
        .padding(4)
    }

    @ViewBuilder
    private func scenarioButton(
        _ title: String,
        systemImage: String,
        scenario: NudgeStore.DebugScenario
    ) -> some View {
        let action = { store.runDebugScenario(scenario) }

        if store.activeDebugScenario == scenario {
            Button(title, systemImage: systemImage, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        } else {
            Button(title, systemImage: systemImage, action: action)
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
    }
}
