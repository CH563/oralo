import AppKit
import Observation
import OraloCore

@MainActor @Observable
final class MacLibrary {
    let repository: ScriptLibraryRepository
    let rehearsals: RehearsalStore
    let removal: LocalDataRemoval
    let preferences: MacPreferences
    private(set) var removalBlocked = false
    private(set) var documents: [ScriptDocument] = []
    private(set) var loaded = false
    private(set) var working = false
    private(set) var generation = UUID()
    private(set) var validity = UUID()
    var editor: ScriptEditorModel?
    var error: String?
    var recoveryNotice: String?
    init(directory: URL, preferences: MacPreferences? = nil) {
        self.preferences = preferences ?? MacPreferences()
        repository = ScriptLibraryRepository(directory: directory)
        rehearsals = RehearsalStore(directory: directory.appending(path: "Rehearsals", directoryHint: .isDirectory))
        removal = LocalDataRemoval(directory: directory, scripts: repository, rehearsals: rehearsals.repository)
    }
    func load() async {
        if loaded && !rehearsals.activeSessions.isEmpty { return }
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            if let pending = try await removal.pending() {
                try await removal.prepare(pending)
                if pending == .all { preferences.resetAll() }
                try await removal.finish()
                validity = UUID(); editor = nil
            }
            removalBlocked = false
            let result = try await repository.load()
            documents = result.documents.sorted { $0.updatedAt > $1.updatedAt }
            generation = await repository.generation()
            await rehearsals.reload(liveScriptIDs: Set(documents.map(\.id)))
            guard rehearsals.loaded else { error = rehearsals.error; loaded = false; return }
            loaded = true; error = nil
            recoveryNotice = nil
            if result.recoveredFromBackup { recoveryNotice = MacCopy.text("已恢复最近可读的副本，请检查最新修改。", "Recovered the last readable backup. Check your latest edits.") }
            if editor == nil, let first = documents.first { editor = ScriptEditorModel(document: first, library: self) }
        } catch { self.error = MacCopy.error(error) }
    }
    func accept(_ document: ScriptDocument, validity expected: UUID? = nil) {
        guard expected == nil || expected == validity else { return }
        documents.removeAll { $0.id == document.id }
        documents.insert(document, at: 0)
    }
    func select(_ document: ScriptDocument) async {
        guard !working, document.id != editor?.document.id else { return }
        working = true
        defer { working = false }
        guard await editor?.flush() != false else { return }
        guard let latest = documents.first(where: { $0.id == document.id }) else { return }
        editor = ScriptEditorModel(document: latest, library: self)
    }
    func create(text: String = "", title: String? = nil, localeID: String? = nil) async {
        guard loaded, !working else { return }
        working = true
        defer { working = false }
        guard await editor?.flush() != false else { return }
        do {
            let document = ScriptDocument(title: title ?? MacCopy.text("未命名讲稿", "Untitled script"), text: text,
                localeID: localeID ?? preferences.defaultLocale)
            let saved = try await repository.save(document, generation: generation)
            accept(saved); editor = ScriptEditorModel(document: saved, library: self)
        } catch { self.error = MacCopy.error(error) }
    }
    func createSample() async {
        let sample = QuickScript.sample(localization: MacCopy.sampleLanguage)
        await create(text: sample.text, title: sample.title, localeID: sample.localeID)
    }
    func importFile(_ url: URL) async {
        do {
            let text = try await MacFileReader().read(url)
            await create(text: text, title: url.deletingPathExtension().lastPathComponent)
        } catch { self.error = MacCopy.error(error) }
    }
    func deleteCurrent() async {
        guard let editor else { return }
        await remove(.script(editor.document.id))
    }
    func remove(_ operation: LocalDataRemoval.Operation) async {
        guard !working, !rehearsals.working, rehearsals.activeSessions.isEmpty else { return }
        working = true
        guard await editor?.flush() != false else { working = false; return }
        let selectedID = editor?.document.id
        let revision: Int?
        if case .script(let id) = operation { revision = documents.first(where: { $0.id == id })?.revision } else { revision = nil }
        validity = UUID(); editor = nil
        do {
            try await removal.prepare(operation, revision: revision)
            if operation == .all { preferences.resetAll() }
            try await removal.finish()
            removalBlocked = false; loaded = false
        } catch {
            self.error = MacCopy.error(error); removalBlocked = true; loaded = false
        }
        working = false
        if !removalBlocked {
            await load()
            if let selectedID, let selected = documents.first(where: { $0.id == selectedID }) { await select(selected) }
        }
    }

}

private actor MacFileReader {
    func read(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try PlainTextImport.read(url)
    }
}
