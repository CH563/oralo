import OraloCore
import SwiftUI
import UniformTypeIdentifiers

struct ScriptLibraryView: View {
    @State private var library = ScriptLibraryStore()
    @State private var path: [UUID] = []
    @State private var settingsVisible = false
    @State private var importing = false
    @State private var pasting = false
    @State private var deleting: ScriptDocument?
    @State private var query = ""
    @State private var selectedEditor: ScriptEditorModel?
    @State private var switchingScript = false
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency

    private var filtered: [ScriptDocument] {
        query.isEmpty ? library.documents : library.documents.filter {
            $0.title.localizedStandardContains(query) || $0.text.localizedStandardContains(query)
        }
    }

    var body: some View {
        Group {
            if isPad {
                NavigationSplitView(preferredCompactColumn: $preferredColumn) {
                    sidebar.navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
                } detail: {
                    NavigationStack {
                        if let selectedEditor {
                            ScriptEditorView(editor: selectedEditor, embedded: true)
                                .id(selectedEditor.document.id)
                        } else {
                            ContentUnavailableView {
                                Label(AppCopy.bilingual("准备好，再开讲", "Your next talk starts here"), systemImage: "doc.text")
                            } description: {
                                Text(AppCopy.bilingual("选择一篇讲稿，或新建你的下一次分享。", "Choose a script or create your next talk."))
                            }
                            .background(OraloStyle.canvas)
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path: $path) {
                    phoneLibrary.navigationDestination(for: UUID.self) { id in
                        if let document = library.documents.first(where: { $0.id == id }) {
                            ScriptEditorHost(document: document, library: library)
                        } else { ContentUnavailableView("Script unavailable", systemImage: "doc") }
                    }
                }
            }
        }
        .sheet(isPresented: $library.floatingVisible) { FloatingPromptView(controller: library.floating) }
        .sheet(isPresented: $settingsVisible) { SettingsView(library: library) }
            .sheet(isPresented: $pasting) { pasteSheet }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { Task { if let doc = await library.importFile(url) { open(doc) } } }
                case .failure(let error): library.error = AppCopy.error(error)
                }
            }
            .confirmationDialog("Delete this script?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                if let deleting {
                    Button("Delete “\(deleting.localizedTitle)”", role: .destructive) {
                        Task { await library.delete(deleting); self.deleting = nil }
                    }
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("The saved script, its pronunciations, rehearsal records and historical versions will be removed from this device.") }
            .alert("Couldn’t complete that", isPresented: Binding(get: { library.loaded && !pasting && library.error != nil }, set: { if !$0 { library.error = nil } })) {
                Button("OK", role: .cancel) { library.error = nil }
            } message: { Text(library.error ?? "") }
            .task { await library.load() }
        .onChange(of: library.documents.map(\.id)) { _, ids in
            if let selectedEditor, !ids.contains(selectedEditor.document.id) {
                self.selectedEditor = nil; preferredColumn = .sidebar
            }
        }
        .tint(.accentColor)
    }

    private var phoneLibrary: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    brand
                    if let notice = library.recoveryNotice {
                        Label(AppCopy.text(notice), systemImage: "arrow.counterclockwise.circle")
                            .font(.callout).padding().background(.yellow.opacity(0.12), in: .rect(cornerRadius: 16))
                    }
                    if library.loading { ProgressView("Opening your scripts…").frame(maxWidth: .infinity) }
                    else if !library.loaded {
                        ContentUnavailableView {
                            Label("Library unavailable", systemImage: "externaldrive.badge.exclamationmark")
                        } description: { Text(library.error ?? AppCopy.text("Your saved files have not been changed.")) }
                        actions: { Button("Retry") { Task { await library.load() } }.buttonStyle(.borderedProminent) }
                    } else if library.documents.isEmpty { emptyLibrary }
                    else if filtered.isEmpty { ContentUnavailableView.search(text: query) }
                    else {
                        Text("YOUR SCRIPTS · \(filtered.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        LazyVStack(spacing: 14) {
                            ForEach(filtered) { document in
                                Button { open(document) } label: { scriptCard(document) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("script-\(document.localizedTitle)")
                                    .contextMenu {
                                        Button("Edit / Rename", systemImage: "pencil") { open(document) }
                                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = document }
                                    }
                            }
                        }
                    }
                }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
            }
            .background(OraloStyle.canvas)
            .navigationTitle("Oralo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settingsVisible = true } label: {
                        Image(systemName: "gearshape").font(.system(size: 20, weight: .medium))
                            .frame(width: 44, height: 44).contentShape(.rect)
                    }
                    .accessibilityLabel("Settings").accessibilityIdentifier("settings")
                }
            }
            .searchable(text: $query, prompt: "Find a script")
            .safeAreaInset(edge: .bottom) { dock }
    }

    private var sidebar: some View {
        List {
            if let notice = library.recoveryNotice { Text(AppCopy.text(notice)).font(.footnote).foregroundStyle(.orange) }
            if library.loading { ProgressView("Opening your scripts…") }
            else if !library.loaded {
                Text(library.error ?? AppCopy.text("Library unavailable")).foregroundStyle(.secondary)
                Button("Retry") { Task { await library.load() } }
            } else if library.documents.isEmpty { emptyLibrary.listRowBackground(Color.clear) }
            else if filtered.isEmpty { ContentUnavailableView.search(text: query) }
            ForEach(filtered) { document in
                Button { open(document) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.localizedTitle).font(.headline).lineLimit(2).foregroundStyle(.primary)
                        Text(document.updatedAt, format: .dateTime.month(.abbreviated).day())
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(selectedEditor?.document.id == document.id ? OraloStyle.readingAccent.opacity(0.16) : Color.clear)
                )
                .accessibilityIdentifier("script-\(document.localizedTitle)")
                .accessibilityAddTraits(selectedEditor?.document.id == document.id ? .isSelected : [])
                .contextMenu {
                    Button("Edit / Rename", systemImage: "pencil") { open(document) }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = document }
                }
            }
        }
        .disabled(switchingScript)
        .listStyle(.sidebar).scrollContentBackground(.hidden).background(OraloStyle.canvas)
        .navigationTitle(AppCopy.text("Scripts")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape") { settingsVisible = true }.accessibilityIdentifier("settings")
        } }
        .searchable(text: $query, prompt: "Find a script")
        .safeAreaInset(edge: .bottom) { dock }
    }

    private func open(_ document: ScriptDocument) {
        guard isPad else { path.append(document.id); return }
        guard !switchingScript else { return }
        if selectedEditor?.document.id == document.id { preferredColumn = .detail; return }
        switchingScript = true
        Task {
            defer { switchingScript = false }
            if let selectedEditor, !(await selectedEditor.flush(finalizeOriginal: true)) {
                library.error = selectedEditor.error
                return
            }
            guard let saved = library.documents.first(where: { $0.id == document.id }) else { return }
            selectedEditor = ScriptEditorModel(document: saved, library: library)
            preferredColumn = .detail
        }
    }

    private var brand: some View {
        HStack(spacing: 16) {
            Image("BrandMark").resizable().scaledToFit().frame(width: 60, height: 60)
                .clipShape(.rect(cornerRadius: 15)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Your words. Your pace.").font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text("Ready when you are.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 12)
    }

    private var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(Color.accentColor)
            Text("Make room for your next talk.").font(.title2.bold())
            Text("Write a draft, paste your notes, or import a text file. Your scripts are saved on this device.")
                .foregroundStyle(.secondary)
            Button("Try a quarterly report") {
                let sample = QuickScript.sample(localization: Bundle.main.preferredLocalizations.first ?? "en")
                create(text: sample.text, title: sample.title, localeID: sample.localeID)
            }.buttonStyle(.bordered).accessibilityIdentifier("sample-script")
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }

    private func scriptCard(_ document: ScriptDocument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(document.localizedTitle).font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                Spacer(minLength: 12)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            Text(document.text.isEmpty ? AppCopy.text("An idea starts here…") : document.text)
                .font(.body).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
            ScriptMetricsView(text: document.text)
            Text(document.updatedAt, format: .dateTime.month(.abbreviated).day())
                .font(.caption2).foregroundStyle(.tertiary)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
            .contentShape(.rect)
    }

    private var dock: some View {
        Group {
            if #available(iOS 26, *), !reducedTransparency {
                newScriptMenu.buttonStyle(.glassProminent)
            } else {
                newScriptMenu
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.accentColor, in: .capsule)
            }
        }
        .buttonBorderShape(.capsule)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 10)
        .disabled(!library.loaded || library.working)
    }

    private var newScriptMenu: some View {
        Menu {
            Button("Blank script", systemImage: "square.and.pencil") { create() }
                .accessibilityIdentifier("new-script")
            Button("Paste text", systemImage: "doc.on.clipboard") { library.error = nil; pasting = true }
                .accessibilityIdentifier("paste-script")
            Button("Import file", systemImage: "square.and.arrow.down") { beginImport() }
                .accessibilityIdentifier("import-script")
        } label: {
            Label(library.working ? "Working…" : "New script", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 24)
                .frame(minHeight: 44)
        }
        .accessibilityIdentifier("new-script-menu")
    }

    private func create(text: String = "", title: String = "Untitled script", localeID: String? = nil) {
        Task { if let document = await library.create(text: text, title: title, localeID: localeID) { open(document) } }
    }

    private func beginImport() {
        #if DEBUG
        // A local provider fixture for repeatable UI tests. The production picker has no bypass.
        if ProcessInfo.processInfo.arguments.contains("--ui-import-fixture"),
           ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-library=") }) {
            let url = URL.temporaryDirectory.appendingPathComponent("Imported report.md")
            do {
                try Data("# Quarterly report\nRevenue grew 18%.\nNext, improve delivery quality.".utf8).write(to: url, options: .atomic)
                Task { if let doc = await library.importFile(url) { open(doc) } }
            } catch { library.error = AppCopy.error(error) }
            return
        }
        #endif
        importing = true
    }

    private var pasteSheet: some View {
        PasteScriptView(error: library.error) { text, title in
            if let document = await library.create(text: text, title: title) {
                pasting = false; open(document)
            }
        }
    }
}

private struct PasteScriptView: View {
    let error: String?
    let importText: (String, String) async -> Void
    @State private var text = ""
    @State private var title = ""
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Script title", text: $title).accessibilityIdentifier("paste-title")
                Section {
                    TextEditor(text: $text).frame(height: 260).accessibilityIdentifier("paste-text")
                } header: { Text("Your text") } footer: {
                    Text("Paste into the editor using the keyboard or touch menu. We only read what you paste here.")
                }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle("Paste a script").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { working = true; Task { await importText(text, title); working = false } }
                        .disabled(working || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("add-pasted-script")
                }
            }
        }.interactiveDismissDisabled(working)
    }
}
