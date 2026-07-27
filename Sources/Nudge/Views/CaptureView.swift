import SwiftUI

struct CaptureView: View {
    @Bindable var store: NudgeStore
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Label(item.contextLabel, systemImage: item.conditions.first?.kind.symbol ?? "sparkles")
                .lineLimit(1)

            if item.action != .none {
                Label(item.action.label, systemImage: item.action.symbol)
                    .lineLimit(1)
            }

            Label(
                "Fallback \(item.fallbackAt.formatted(date: .abbreviated, time: .shortened))",
                systemImage: "clock"
            )
            .lineLimit(1)

            if let providerLabel {
                Label(providerLabel, systemImage: "brain.head.profile")
                    .lineLimit(1)
            }

            Divider()

            HStack {
                Button("Edit Request", action: store.reviseCapturePreview)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Spacer()

                Button("Save Nudge", action: store.commitCapturePreview)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var providerLabel: String? {
        switch store.lastInferenceProviderID {
        case "apple-intelligence-on-device":
            "Interpreted by Apple Intelligence"
        case "mock-rule-based":
            "Interpreted by the local parser"
        case .some(let providerID):
            "Interpreted by \(providerID)"
        case nil:
            nil
        }
    }

    private func focusInputAfterLayout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isInputFocused = true
        }
    }
}
