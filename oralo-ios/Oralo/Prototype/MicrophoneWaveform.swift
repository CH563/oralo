import SwiftUI

/// A small history of actual microphone levels, never an independently looping animation.
struct MicrophoneWaveform: View {
    let levels: [Float]
    let isRecording: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(isRecording ? Color(red: 0.52, green: 0.66, blue: 1) : Color.secondary.opacity(0.5))
                    .frame(width: 2, height: height(for: levels[index]))
            }
        }
        .frame(width: 90, height: 18)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .modifier(OraloGlassSurface())
        .animation(reduceMotion ? nil : .linear(duration: 0.1), value: levels)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone input")
        .accessibilityValue(AppCopy.text(isRecording ? ((levels.last ?? 0) > 0.2 ? "Sound detected" : "Quiet") : "Paused"))
        .accessibilityIdentifier("microphone-waveform")
    }

    private func height(for level: Float) -> CGFloat {
        guard isRecording else { return 2 }
        // Suppress the noise-floor visually; retain the measured dynamics above it.
        let amplitude = min(1, max(0, Double(level) - 0.15) / 0.65)
        return 2 + 16 * amplitude
    }
}
