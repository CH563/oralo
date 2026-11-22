import OraloCore
import SwiftUI

struct SettingsView: View {
    let library: ScriptLibraryStore
    private var preferences: ReadingPreferencesStore { library.preferences }
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ReadingPreferencePreview(preferences: preferences.value)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    LabeledContent("Text size") { Text(Int(preferences.value.fontSize), format: .number).monospacedDigit().accessibilityIdentifier("reading-size-value") }
                    Slider(value: Binding(get: { preferences.value.fontSize }, set: { value in preferences.update { $0.fontSize = value } }), in: 26...48, step: 1) {
                        Text("Text size")
                    } minimumValueLabel: { Image(systemName: "textformat.size.smaller").accessibilityHidden(true) }
                    maximumValueLabel: { Image(systemName: "textformat.size.larger").accessibilityHidden(true) }
                        .accessibilityValue("\(Int(preferences.value.fontSize))")
                        .accessibilityIdentifier("reading-size")
                    Picker("Presentation appearance", selection: Binding(get: { preferences.value.appearance }, set: { value in preferences.update { $0.appearance = value } })) {
                        Text("System").tag(ReadingPreferences.Appearance.system)
                        Text("Light").tag(ReadingPreferences.Appearance.light)
                        Text("Dark").tag(ReadingPreferences.Appearance.dark)
                    }.accessibilityIdentifier("reading-appearance")
                } header: { Text("Reading") } footer: { Text("Changes apply to your next talk. Text also respects your system accessibility size.") }
                Section {
                    Toggle("Follow my voice by default", isOn: Binding(get: { preferences.value.followsVoice }, set: { value in preferences.update { $0.followsVoice = value } }))
                        .accessibilityIdentifier("default-follow")
                    Picker("Default speech language", selection: Binding(get: { preferences.value.localeID }, set: { value in preferences.update { $0.localeID = value } })) {
                        Text("Mandarin").tag("zh-CN")
                        Text("English (US)").tag("en-US")
                    }.accessibilityIdentifier("default-language")
                } header: { Text("Before your next talk") } footer: { Text("The language default applies to new scripts. Existing scripts keep their language. Microphone access is only requested when you check or start voice following.") }
                Section {
                    NavigationLink { SpeakingEstimateSettings() } label: {
                        Label(AppCopy.bilingual("预计演讲时长", "Speaking estimate"), systemImage: "clock")
                    }.accessibilityIdentifier("estimate-settings")
                    NavigationLink { LocalDataView(library: library) } label: { Label("On-device data", systemImage: "internaldrive") }.accessibilityIdentifier("data-settings")
                    NavigationLink { PrivacyAndSourceView() } label: { Label("Privacy & open source", systemImage: "hand.raised") }.accessibilityIdentifier("privacy-settings")
                }
                Section {
                    Button("Restore reading defaults") { confirmReset = true }.accessibilityIdentifier("reset-reading")
                } footer: {
                    Text("Oralo · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                }
            }
            .scrollContentBackground(.hidden).background(OraloStyle.canvas)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("close-settings") } }
            .confirmationDialog("Restore reading defaults?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Restore defaults") { preferences.reset() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Your scripts, pronunciations and records will stay.") }
        }.tint(OraloStyle.readingAccent)
    }
}

private struct ReadingPreferencePreview: View {
    let preferences: ReadingPreferences
    @Environment(\.colorScheme) private var systemAppearance
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    private static let sample: ScriptSnapshot? = {
        var document = ScriptDocument(text: "夯实基础，完善 roadmap。")
        for (term, reading, kind) in [("夯实", "hāng shí", Pronunciation.Kind.pinyin), ("roadmap", "/ˈroʊdˌmæp/", .ipa)] {
            let span = TextSpan((document.text as NSString).range(of: term))
            try? document.setPronunciation(Pronunciation(span: span, term: term, reading: reading, kind: kind))
        }
        return try? document.snapshot()
    }()
    var body: some View {
        if let sample = Self.sample {
            ScriptReader(cues: sample.cues, recognizedIndex: 0, confirmedCharacters: 2,
                         position: ReadingCursor.Position(cueIndex: 0, characterCount: 2),
                         fontSize: preferences.fontSize * scale, presenting: false, controlsVisible: false,
                         reduceMotion: true, pronunciations: sample.pronunciations, select: { _ in }, revealControls: {})
                .frame(height: typeSize.isAccessibilitySize ? 360 : 215)
                .allowsHitTesting(false)
                .background(OraloStyle.canvas)
                .environment(\.colorScheme, preferences.appearance.colorScheme ?? systemAppearance)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Reading preview: 夯实, hāng shí; roadmap, /ˈroʊdˌmæp/."))
                .accessibilityIdentifier("reading-preference-preview")
        }
    }
}

struct LocalDataView: View {
    let library: ScriptLibraryStore
    @State private var operation: LocalDataRemoval.Operation?
    @State private var confirmRemoval = false
    @State private var completed: LocalDataRemoval.Operation?
    private var rehearsalCount: Int { library.rehearsals.records.filter { $0.kind == .rehearsal }.count }
    private var presentationCount: Int { library.rehearsals.records.filter { $0.kind == .presentation }.count }
    private var known: Bool { library.loaded && library.rehearsals.loaded }
    var body: some View {
        Form {
            Section {
                count("Scripts", library.documents.count, id: "data-script-count")
                count("Pronunciations", library.documents.reduce(0) { $0 + $1.pronunciations.count }, id: "data-pronunciation-count")
                count("Rehearsals", rehearsalCount, id: "data-rehearsal-count")
                count("Presentations", presentationCount, id: "data-presentation-count")
            } footer: { Text("Scripts, pronunciation notes, records and recovery copies are stored on this device.") }
            if let error = library.error ?? library.rehearsals.error {
                Section {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange).accessibilityIdentifier("data-error")
                    Button("Retry") { Task { await library.load() } }.disabled(library.working)
                } footer: { Text("Removal may be unfinished. Retry before making further changes.") }
            }
            if let completed { Section { Label(completed == .all ? "All local data deleted" : "Rehearsal history cleared", systemImage: "checkmark.circle").accessibilityIdentifier("data-cleared") } }
            Section {
                Button("Clear rehearsal history", role: .destructive) { completed = nil; operation = .rehearsals; confirmRemoval = true }
                    .disabled(!known || rehearsalCount == 0 || !library.canRemoveData).accessibilityIdentifier("clear-rehearsals")
            } footer: { Text("Keeps scripts, pronunciations, presentation records and reading preferences. Shared snapshots stay while another record uses them.") }
            Section {
                Button("Delete all local data", role: .destructive) { completed = nil; operation = .all; confirmRemoval = true }
                    .disabled(!library.canRemoveData).accessibilityIdentifier("clear-all-data")
            } footer: { Text("Deletes scripts, originals, pronunciations, all records, snapshots, recovery copies and app preferences. It does not delete exported files or system device backups.") }
            Section("Export a script") {
                Text("Use Export text in the script menu. Plain text does not include pronunciations or records and is not a complete backup.")
            }
            if library.working { ProgressView("Finishing data removal…").accessibilityIdentifier("data-removal-progress") }
        }
        .scrollContentBackground(.hidden).background(OraloStyle.canvas)
        .navigationTitle("On-device data").navigationBarTitleDisplayMode(.inline)
        .alert(operation == .all ? "Delete all local data?" : "Clear rehearsal history?",
                            isPresented: $confirmRemoval, presenting: operation) { (choice: LocalDataRemoval.Operation) in
                Button(choice == .all ? "Delete all data" : "Clear rehearsals", role: .destructive) {
                    self.operation = nil
                    Task { if await library.removeData(choice) { completed = choice } }
                }.accessibilityIdentifier("confirm-data-removal")
            Button("Cancel", role: .cancel) { self.operation = nil }.accessibilityIdentifier("cancel-data-removal")
        } message: { operation in
            Text(verbatim: removalMessage(operation))
        }
        .interactiveDismissDisabled(library.working)
    }
    private func removalMessage(_ operation: LocalDataRemoval.Operation) -> String {
        if operation == .all {
            let explanation = AppCopy.text("This removes all app-managed data from this device, including recovery copies and preferences. This cannot be undone. Text exports do not include pronunciation notes.")
            guard known else { return explanation }
            let counts = String(format: AppCopy.text("%lld scripts, %lld pronunciations, %lld session records."),
                                library.documents.count, library.documents.reduce(0) { $0 + $1.pronunciations.count }, library.rehearsals.records.count)
            return counts + "\n\n" + explanation
        }
        return String(format: AppCopy.text("This removes %lld rehearsal records and snapshots no longer in use. Scripts, pronunciation notes and presentation records stay. This cannot be undone."), rehearsalCount)
    }
    private func count(_ title: LocalizedStringKey, _ number: Int, id: String) -> some View {
        LabeledContent(title) { Text(known ? number.formatted() : "—").monospacedDigit().accessibilityIdentifier(id) }
    }
}

struct PrivacyAndSourceView: View {
    var body: some View {
        List {
            Section("On your device") {
                Text("Your scripts and rehearsal records are stored on your device. Oralo does not upload scripts or microphone audio to a developer-operated server.")
                Text("Local storage includes scripts, originals, pronunciation notes, records, historical snapshots and recovery copies. You can manage them in On-device data.")
            }
            Section("Speech & network access") {
                Text("Speech following uses Apple's on-device recognition. The app does not save recordings or full transcripts. If recognition is unavailable, manual reading remains available.")
                Text("System speech models, voices and files chosen from cloud providers may require downloads. Oralo has no account system, advertising SDK or analytics SDK.")
            }
            Section("Your choices") {
                Text("Diagnostic reports are shared only when you choose. They contain performance counters, system details and event metadata, not your script, pronunciation notes or full transcript.")
                Text("App data may be included in system device backups. Removing data in Oralo does not erase those backups or copies you exported elsewhere.")
            }
            Section("Pronunciation sources") {
                Text("Chinese: Apple's transliteration, editable by you. English: bundled ipa-dict US IPA. Playback uses a system voice to read the original word, not your edited IPA. Pronunciations never play automatically while presenting.")
                NavigationLink("Pronunciation licenses") { LicenseTextView(title: "Pronunciation licenses", names: ["Pronunciation-Credits", "IPA-Dict-LICENSE", "CMUDict-IPA-LICENSE", "CMUDict-LICENSE"]) }.accessibilityIdentifier("pronunciation-licenses")
            }
            Section("Open source") {
                if let url = URL(string: "https://github.com/CH563/oralo") {
                    Link(destination: url) { Label("View source on GitHub", systemImage: "arrow.up.right") }
                        .accessibilityIdentifier("open-source-link")
                }
                NavigationLink("MIT License") { LicenseTextView(title: "MIT License", names: ["Oralo-MIT-LICENSE"]) }.accessibilityIdentifier("mit-license")
            }
        }.scrollContentBackground(.hidden).background(OraloStyle.canvas)
            .navigationTitle("Privacy & open source").navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseTextView: View {
    let title: LocalizedStringKey
    let names: [String]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(names, id: \.self) { name in
                    if let url = Bundle.main.url(forResource: name, withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) {
                        Text(verbatim: text).font(.footnote).textSelection(.enabled)
                    } else { Text("License text is unavailable.").foregroundStyle(.secondary) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }.background(OraloStyle.canvas).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
