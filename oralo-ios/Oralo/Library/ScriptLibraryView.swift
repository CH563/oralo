import OraloCore
import SwiftUI
import UniformTypeIdentifiers

struct ScriptLibraryView: View {
    @State private var library = ScriptLibraryStore()
    @State private var path: [UUID] = []
    @State private var importing = false
    @State private var pasting = false
    @State private var deleting: ScriptDocument?
    @State private var query = ""
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency

    private var filtered: [ScriptDocument] {
        query.isEmpty ? library.documents : library.documents.filter {
            $0.title.localizedStandardContains(query) || $0.text.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    brand
                    if let notice = library.recoveryNotice {
                        Label(notice, systemImage: "arrow.counterclockwise.circle")
                            .font(.callout).padding().background(.yellow.opacity(0.12), in: .rect(cornerRadius: 16))
                    }
                    if library.loading { ProgressView("Opening your scripts…").frame(maxWidth: .infinity) }
                    else if !library.loaded {
                        ContentUnavailableView {
                            Label("Library unavailable", systemImage: "externaldrive.badge.exclamationmark")
                        } description: { Text(library.error ?? "Your saved files have not been changed.") }
                        actions: { Button("Retry") { Task { await library.load() } }.buttonStyle(.borderedProminent) }
                    } else if library.documents.isEmpty { emptyLibrary }
                    else if filtered.isEmpty { ContentUnavailableView.search(text: query) }
                    else {
                        Text("YOUR SCRIPTS · \(filtered.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        LazyVStack(spacing: 14) {
                            ForEach(filtered) { document in
                                Button { path.append(document.id) } label: { scriptCard(document) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("script-\(document.displayTitle)")
                                    .contextMenu {
                                        Button("Edit / Rename", systemImage: "pencil") { path.append(document.id) }
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
            .searchable(text: $query, prompt: "Find a script")
            .safeAreaInset(edge: .bottom) { dock }
            .navigationDestination(for: UUID.self) { id in
                if let document = library.documents.first(where: { $0.id == id }) {
                    ScriptEditorView(document: document, library: library)
                } else { ContentUnavailableView("Script unavailable", systemImage: "doc") }
            }
            .sheet(isPresented: $pasting) { pasteSheet }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { Task { if let doc = await library.importFile(url) { path.append(doc.id) } } }
                case .failure(let error): library.error = error.localizedDescription
                }
            }
            .confirmationDialog("Delete this script?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                if let deleting {
                    Button("Delete “\(deleting.displayTitle)”", role: .destructive) {
                        Task { await library.delete(deleting); self.deleting = nil }
                    }
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("The saved script, its pronunciations, rehearsal records and historical versions will be removed from this iPhone.") }
            .alert("Couldn’t complete that", isPresented: Binding(get: { library.loaded && !pasting && library.error != nil }, set: { if !$0 { library.error = nil } })) {
                Button("OK", role: .cancel) { library.error = nil }
            } message: { Text(library.error ?? "") }
            .task { await library.load() }
        }.tint(.accentColor)
    }

    private var brand: some View {
        HStack(spacing: 16) {
            Image("BrandMark").resizable().scaledToFit().frame(width: 60, height: 60)
                .clipShape(.rect(cornerRadius: 15)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Your words. Your pace.").font(.title3.weight(.semibold))
                Text("Ready when you are.").font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 12)
    }

    private var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(Color.accentColor)
            Text("Make room for your next talk.").font(.title2.bold())
            Text("Write a draft, paste your notes, or import a text file. Your scripts are saved on this iPhone.")
                .foregroundStyle(.secondary)
            Button("Try a quarterly report") {
                create(text: PrototypeSamples.chinese, title: "Quarterly report")
            }.buttonStyle(.bordered).accessibilityIdentifier("sample-script")
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }

    private func scriptCard(_ document: ScriptDocument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(document.displayTitle).font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                Spacer(minLength: 12)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            Text(document.text.isEmpty ? "An idea starts here…" : document.text)
                .font(.body).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
            HStack {
                Label("\(document.segments.count) sentences", systemImage: "text.alignleft")
                Spacer()
                Text(document.updatedAt, format: .dateTime.month(.abbreviated).day())
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
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

    private func create(text: String = "", title: String = "Untitled script") {
        Task { if let document = await library.create(text: text, title: title) { path.append(document.id) } }
    }

    private func beginImport() {
        #if DEBUG
        // A local provider fixture for repeatable UI tests. The production picker has no bypass.
        if ProcessInfo.processInfo.arguments.contains("--ui-import-fixture"),
           ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-library=") }) {
            let url = URL.temporaryDirectory.appendingPathComponent("Imported report.md")
            do {
                try Data("# Quarterly report\nRevenue grew 18%.\nNext, improve delivery quality.".utf8).write(to: url, options: .atomic)
                Task { if let doc = await library.importFile(url) { path.append(doc.id) } }
            } catch { library.error = error.localizedDescription }
            return
        }
        #endif
        importing = true
    }

    private var pasteSheet: some View {
        PasteScriptView(error: library.error) { text, title in
            if let document = await library.create(text: text, title: title) {
                pasting = false; path.append(document.id)
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
