import SwiftUI

struct CaptureView: View {
    @Bindable var store: NudgeStore
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            inputRow

            if let preview = store.capturePreview {
                confirmation(preview)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Describe the intention. Nudge infers where it will be useful.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .animation(.snappy(duration: 0.22), value: store.capturePreview?.id)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isInputFocused = true
            }
        }
    }

    private var header: some View {
        HStack {
            Label("New Nudge", systemImage: "sparkles")
                .font(.headline)

            Spacer()

            Button(action: store.collapse) {
                Image(systemName: "xmark")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("What should you remember?", text: $store.captureDraft)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .onSubmit(store.createNudgeFromCapture)

            Button(action: store.simulateVoiceCapture) {
                Image(systemName: store.isListening ? "waveform" : "mic.fill")
                    .symbolEffect(.variableColor.iterative, isActive: store.isListening)
            }
            .buttonStyle(.bordered)
            .help("Simulate Voice Capture")

            Button("Add", action: store.createNudgeFromCapture)
                .buttonStyle(.borderedProminent)
                .disabled(store.captureDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.regular)
    }

    private func confirmation(_ item: NudgeItem) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 5) {
                Label(item.contextLabel, systemImage: item.triggers.first?.kind.symbol ?? "sparkles")
                Label("Fallback in \(store.fallbackDays) days", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        }
    }
}
