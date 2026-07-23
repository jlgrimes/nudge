import SwiftUI

struct CaptureView: View {
    @Bindable var store: NudgeStore
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ask Nudge", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button(action: store.collapse) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(.primary.opacity(0.07), in: .circle)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 9) {
                TextField("What should you remember?", text: $store.captureDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isInputFocused)
                    .onSubmit(store.createNudgeFromCapture)

                Button(action: store.simulateVoiceCapture) {
                    Image(systemName: store.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .symbolEffect(.variableColor.iterative, isActive: store.isListening)
                        .frame(width: 32, height: 32)
                        .background(
                            store.isListening ? Color.red.opacity(0.16) : Color.primary.opacity(0.07),
                            in: .circle
                        )
                }
                .buttonStyle(.plain)
                .help("Simulate voice capture")

                Button(action: store.createNudgeFromCapture) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor, in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(store.captureDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(store.captureDraft.isEmpty ? 0.45 : 1)
            }
            .padding(.leading, 13)
            .padding(.trailing, 6)
            .frame(height: 46)
            .background(.primary.opacity(0.065), in: .capsule)

            if let preview = store.capturePreview {
                confirmation(preview)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Say the intention. Nudge infers the right context.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 3)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.white.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.17), radius: 18, y: 8)
        }
        .animation(.smooth(duration: 0.25), value: store.capturePreview?.id)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isInputFocused = true
            }
        }
    }

    private func confirmation(_ item: NudgeItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("I’ll nudge you \(item.detail.lowercased()).")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                if let trigger = item.triggers.first {
                    Label(trigger.kind.label, systemImage: trigger.kind.symbol)
                        .contextChip()
                    Text("\(Int(trigger.confidence * 100))% match")
                        .contextChip()
                }
                Text("Fallback · \(store.fallbackDays)d")
                    .contextChip()
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.09), in: .rect(cornerRadius: 14))
    }
}

private extension View {
    func contextChip() -> some View {
        font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(.primary.opacity(0.055), in: .capsule)
    }
}
