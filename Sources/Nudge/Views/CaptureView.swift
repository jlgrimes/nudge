import SwiftUI

struct CaptureView: View {
    @Bindable var store: NudgeStore
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let preview = store.capturePreview {
                review(preview)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                inputRow

                if let errorMessage = store.inferenceErrorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, NudgePanelLayout.contentHorizontalPadding)
        .padding(.vertical, 14)
        .animation(.snappy(duration: 0.22), value: store.capturePreview?.id)
        .animation(.easeOut(duration: 0.16), value: store.inferenceErrorMessage)
        .onAppear {
            focusInputAfterLayout()
        }
        .onChange(of: store.capturePreview?.id) { _, previewID in
            if previewID == nil {
                focusInputAfterLayout()
            } else {
                isInputFocused = false
            }
        }
    }

    private var header: some View {
        HStack {
            Label(
                store.capturePreview == nil ? "New Nudge" : "Review Nudge",
                systemImage: "sparkles"
            )
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
                        .frame(minWidth: 38)
                } else {
                    Text("Review")
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

    private func review(_ item: NudgeItem) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Label(item.contextLabel, systemImage: item.conditions.first?.kind.symbol ?? "sparkles")

                if item.action != .none {
                    Label(item.action.label, systemImage: item.action.symbol)
                }

                Label(
                    "Fallback \(item.fallbackAt.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "clock"
                )

                Divider()

                HStack {
                    Button("Edit Request", action: store.reviseCapturePreview)
                        .buttonStyle(.bordered)

                    Spacer()

                    Button("Save Nudge", action: store.commitCapturePreview)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Confirm what Nudge understood", systemImage: "checkmark.bubble")
                .font(.caption.weight(.medium))
        }
    }

    private func focusInputAfterLayout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isInputFocused = true
        }
    }
}
