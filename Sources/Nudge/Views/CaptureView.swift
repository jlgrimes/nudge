import SwiftUI

struct CaptureView: View {
    @Bindable var store: NudgeStore
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            inputRow

            if let errorMessage = store.inferenceErrorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            if let preview = store.capturePreview {
                confirmation(preview)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
        .padding(.vertical, 14)
        .animation(.snappy(duration: 0.22), value: store.capturePreview?.id)
        .animation(.easeOut(duration: 0.16), value: store.inferenceErrorMessage)
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
                .disabled(store.isInferring)
                .onSubmit(store.createNudgeFromCapture)

            if NudgeRuntime.debugToolsEnabled {
                Button(action: store.simulateVoiceCapture) {
                    Image(systemName: store.isListening ? "waveform" : "mic.fill")
                        .symbolEffect(.variableColor.iterative, isActive: store.isListening)
                }
                .buttonStyle(.bordered)
                .help("Simulate Voice Capture")
            }

            Button(action: store.createNudgeFromCapture) {
                if store.isInferring {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 26)
                } else {
                    Text("Add")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                store.isInferring
                    || store.captureDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.regular)
    }

    private func confirmation(_ item: NudgeItem) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 5) {
                Label(item.contextLabel, systemImage: item.triggers.first?.kind.symbol ?? "sparkles")
                Label(
                    "Fallback \(item.fallbackAt.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "clock"
                )
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
