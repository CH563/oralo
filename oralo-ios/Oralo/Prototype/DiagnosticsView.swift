import SwiftUI

struct DiagnosticsView: View {
    let model: SpeechPrototypeModel
    @State private var confirmReset = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("What the recognizer heard · memory only") {
                    Text(model.transcript.isEmpty ? AppCopy.text("No transcript yet.") : model.transcript)
                        .textSelection(.enabled)
                    Text("The report below excludes this text and your script.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Mark what you observed") {
                    Button("Wrong jump (+1) · \(model.markedWrongJumps)") { model.markWrongJump() }
                    Button("Missed follow (+1) · \(model.markedMisses)") { model.markMiss() }
                    Text("These are your observations, not automatic accuracy measurements.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Test report") {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(model.report).font(.caption.monospaced()).textSelection(.enabled)
                                .accessibilityIdentifier("diagnostic-report")
                            ShareLink("Share report", item: model.report)
                        }
                    }
                    Button("Reset test", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Test diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Reset counters and return to the first cue?", isPresented: $confirmReset) {
                Button("Reset test", role: .destructive) { model.resetTest(); dismiss() }
            }
        }
    }
}
