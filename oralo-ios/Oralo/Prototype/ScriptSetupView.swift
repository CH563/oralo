import SwiftUI

struct ScriptSetupView: View {
    @Bindable var model: SpeechPrototypeModel
    @State private var text = ""
    @State private var error: String?
    @State private var localeID = "zh-CN"
    @State private var backend: SpeechPrototypeModel.Backend = .automatic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Recognition") {
                    Picker("Language", selection: $localeID) {
                        Text("中文 · Mandarin").tag("zh-CN")
                        Text("English · US").tag("en-US")
                    }
                    Picker("Engine", selection: $backend) {
                        ForEach(SpeechPrototypeModel.Backend.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Text("System uses the new on-device model on iOS 26/27. Compatibility tests the iOS 18 recognition path. Mixed-language accuracy is experimental.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Load sample for selected language") {
                        text = localeID == "zh-CN" ? PrototypeSamples.chinese : PrototypeSamples.english
                    }
                    TextEditor(text: $text).frame(minHeight: 260)
                        .accessibilityLabel("Test script").accessibilityIdentifier("script-editor")
                } header: { Text("Test script") } footer: {
                    Text("Use punctuation or line breaks between sentences. Applying a script resets the test report. Prototype drafts stay in memory and are not saved between launches.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Script & language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        do {
                            try model.applyScript(text)
                            model.localeID = localeID
                            model.backend = backend
                            dismiss()
                        }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            .onAppear { text = model.draft; localeID = model.localeID; backend = model.backend }
        }
    }
}
