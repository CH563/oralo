import SwiftUI

/// Glass belongs to the controls; the reader keeps its existing TextKit layout.
struct PromptGlassGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else { content }
    }
}

extension View {
    @ViewBuilder func promptControlSurface() -> some View {
        if #available(macOS 26, *) { self.glassEffect(.regular, in: .capsule) }
        else { self.background(.regularMaterial, in: .capsule) }
    }
}

struct PromptButton: View {
    let title: String
    let symbol: String
    let identifier: String
    var showsTitle = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).frame(width: 18)
                if showsTitle { Text(title).fixedSize() }
            }.frame(minWidth: 26, minHeight: 28)
                .padding(.horizontal, showsTitle ? 6 : 0)
                .contentShape(.rect)
        }
        .accessibilityLabel(title).accessibilityIdentifier(identifier).help(title)
    }
}

struct PromptStatus: View {
    let session: MacSpeechSession
    var compact = false
    private var shortStatus: String {
        if session.preparing { return MacCopy.text("准备中", "Preparing") }
        if session.playing { return session.mode.title }
        if !session.recording { return MacCopy.text("已暂停", "Paused") }
        if session.follower.session.mode == .holding { return MacCopy.text("自由发挥", "Off script") }
        return MacCopy.text("正在聆听", "Listening")
    }
    var body: some View {
        Group {
            if compact {
                HStack(spacing: 8) {
                    SoundWave(levels: Array(session.levels.suffix(13)), active: session.recording)
                    Text(shortStatus).font(.caption).lineLimit(1)
                        .accessibilityIdentifier("speech-status")
                }
            } else {
                VStack(spacing: 1) {
                    SoundWave(levels: session.levels, active: session.recording)
                    HStack(spacing: 6) {
                        Text("\(session.currentIndex + 1) / \(session.snapshot.cues.count)").monospacedDigit()
                        if let recorder = session.recorder {
                            Text(recorder.kind == .rehearsal ? MacCopy.text("排练", "Rehearsal") : MacCopy.text("演讲", "Presentation"))
                            TimelineView(.periodic(from: .now, by: 1)) { _ in Text(MacCopy.duration(recorder.duration())).monospacedDigit() }
                        }
                        Text("·")
                        Text(session.status).lineLimit(1)
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }.help(session.status)
    }
}

struct PromptSlider: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let identifier: String
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                Spacer(minLength: 16)
                Text(valueText).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            }
            Slider(value: $value, in: range, step: step) { Text(title) }
                .labelsHidden().accessibilityIdentifier(identifier)
                .accessibilityValue(valueText)
        }
    }
}
