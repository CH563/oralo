import Foundation
import Observation
import OraloCore

@MainActor @Observable
final class ScriptLibraryStore {
    let repository: ScriptLibraryRepository
    let rehearsals: RehearsalStore
    let preferences = ReadingPreferencesStore.shared
    let floating = FloatingPromptController()
    var floatingVisible = false
    let removal: LocalDataRemoval
    private(set) var generation = UUID()
    private(set) var validity = UUID()
    var canRemoveData: Bool { !working && !loading && rehearsals.activeSessions.isEmpty }
    private(set) var documents: [ScriptDocument] = []
    private(set) var loaded = false
    private(set) var loading = false
    private(set) var working = false
    var error: String?
    var recoveryNotice: String?

    init() {
        var directory = URL.applicationSupportDirectory.appending(path: "Oralo/Library", directoryHint: .isDirectory)
        #if DEBUG
        if let sandbox = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-library=") }) {
            let name = sandbox.replacingOccurrences(of: "--ui-library=", with: "")
            if UUID(uuidString: name) != nil { directory = URL.applicationSupportDirectory.appending(path: "OraloUITests/\(name)") }
        }
        #endif
        repository = ScriptLibraryRepository(directory: directory)
        rehearsals = RehearsalStore(directory: directory.appending(path: "Rehearsals", directoryHint: .isDirectory))
        removal = LocalDataRemoval(directory: directory, scripts: repository, rehearsals: rehearsals.repository)
    }

    func load() async {
        guard !loading, !working else { return }
        loading = true
        defer { loading = false }
        do {
            if let pending = try await removal.pending() {
                floating.removeData(pending)
                try await removal.prepare(pending)
                if pending == .all { preferences.clearAll() }
                try await removal.finish()
            }
            generation = await repository.generation()
            let result = try await repository.load()
            documents = result.documents.sorted { $0.updatedAt > $1.updatedAt }
            #if DEBUG
            if documents.isEmpty, !ReadingPreferencesStore.defaults.bool(forKey: "ui.fixture.seeded"), ProcessInfo.processInfo.arguments.contains("--ui-pronunciation-fixture"),
               ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-library=") }) {
                var sample = ScriptDocument(title: "Reading rehearsal", text: "roadmap\n夯实\nmilestone\n本季度收入增长18%，交付周期缩短到12天。\n接下来继续夯实基础，完善 roadmap，明确每个 milestone。\n把计划变成客户看得见的改变。")
                if ProcessInfo.processInfo.arguments.contains("--ui-pronunciation-seeded") {
                    for (term, reading, kind) in [("roadmap", "/ˈɹoʊdˌmæp/", Pronunciation.Kind.ipa), ("夯实", "hāng shí", .pinyin), ("milestone", "/ˈmaɪɫˌstoʊn/", .ipa)] {
                        let range = (sample.text as NSString).range(of: term)
                        try sample.setPronunciation(Pronunciation(span: TextSpan(range), term: term, reading: reading,
                            kind: kind, referenceReading: reading, source: "UI fixture"))
                    }
                }
                documents = [try await repository.save(sample)]
            }
            if documents.isEmpty, !ReadingPreferencesStore.defaults.bool(forKey: "ui.fixture.seeded"), ProcessInfo.processInfo.arguments.contains("--ui-rehearsal-fixture"),
               ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-library=") }) {
                var sample = ScriptDocument(title: "Quarterly report", text: PrototypeSamples.chinese)
                for (term, reading, kind) in [("夯实", "hāng shí", Pronunciation.Kind.pinyin), ("roadmap", "/ˈroʊdˌmæp/", .ipa), ("milestone", "/ˈmaɪlˌstoʊn/", .ipa)] {
                    let range = (sample.text as NSString).range(of: term)
                    try sample.setPronunciation(Pronunciation(span: TextSpan(range), term: term, reading: reading, kind: kind, referenceReading: reading, source: "UI fixture"))
                }
                documents = [try await repository.save(sample)]
            }
            if !documents.isEmpty { ReadingPreferencesStore.defaults.set(true, forKey: "ui.fixture.seeded") }
            #endif
            floating.prune(liveIDs: Set(documents.map(\.id)))
            loaded = true; error = nil
            await rehearsals.load(liveScriptIDs: Set(documents.map(\.id)))
            if result.recoveredFromBackup {
                recoveryNotice = "Recovered the last readable backup. Check your latest edits. The unreadable file has been kept for recovery."
            }
        } catch { self.error = AppCopy.error(error) }
    }

    func accept(_ document: ScriptDocument, validity expected: UUID? = nil) {
        guard expected == nil || expected == validity else { return }
        documents.removeAll { $0.id == document.id }
        documents.insert(document, at: 0)
    }

    func create(text: String = "", title: String = "", localeID: String? = nil) async -> ScriptDocument? {
        guard loaded, !working else { return nil }
        working = true
        defer { working = false }
        do {
            let saved = try await repository.save(ScriptDocument(title: title, text: text, localeID: localeID ?? preferences.value.localeID), generation: generation)
            accept(saved); return saved
        } catch { self.error = AppCopy.error(error); return nil }
    }

    func importFile(_ url: URL) async -> ScriptDocument? {
        guard loaded, !working else { return nil }
        working = true
        defer { working = false }
        do {
            let text = try await ScriptFileReader.shared.read(url)
            let saved = try await repository.save(ScriptDocument(title: url.deletingPathExtension().lastPathComponent, text: text, localeID: preferences.value.localeID), generation: generation)
            accept(saved); return saved
        } catch { self.error = AppCopy.error(error); return nil }
    }

    func openFloating(_ document: ScriptDocument) {
        let lease = validity
        floating.prepare(document) { [weak self] in
            guard let self else { return false }
            return self.loaded && self.validity == lease && self.documents.contains { $0.id == document.id }
        }
        floating.didReturn = { [weak self] _ in self?.floatingVisible = true }
        floatingVisible = true
    }

    func delete(_ document: ScriptDocument) async {
        _ = await removeData(.script(document.id), revision: document.revision)
    }
    @discardableResult func removeData(_ operation: LocalDataRemoval.Operation, revision: Int? = nil) async -> Bool {
        guard canRemoveData else { return false }
        working = true; validity = UUID(); error = nil
        defer { working = false }
        do {
            floating.removeData(operation)
            if operation == .all { floatingVisible = false }
            try await removal.prepare(operation, revision: revision)
            if operation == .all { preferences.reset() }
            try await removal.finish()
            generation = await repository.generation()
            documents = try await repository.load().documents.sorted { $0.updatedAt > $1.updatedAt }
            await rehearsals.reload(liveScriptIDs: Set(documents.map(\.id)))
            guard rehearsals.error == nil else { error = rehearsals.error; return false }
            recoveryNotice = nil; loaded = true
            if operation == .all { preferences.clearAll() }
            return true
        } catch {
            self.error = AppCopy.error(error)
            loaded = false // Keep partial deletion behind a retry; never call it an empty library.
            return false
        }
    }

}

/// Files providers may block while downloading. Coordinate reads off the UI actor.
private actor ScriptFileReader {
    static let shared = ScriptFileReader()
    func read(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<String, Error> = .failure(ScriptLibraryError.unsupportedText)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result { try PlainTextImport.read(coordinated) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}

@MainActor @Observable
final class ScriptEditorModel {
    private(set) var document: ScriptDocument
    private(set) var saving = false
    private(set) var dirty = false
    private(set) var history: [ScriptDocument] = []
    var error: String?
    var actionError: String?
    let library: ScriptLibraryStore
    private let writeGeneration: UUID
    private let libraryValidity: UUID
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var activeSave: Task<Bool, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastTextEdit = Date.distantPast

    init(document: ScriptDocument, library: ScriptLibraryStore) {
        self.document = document; self.library = library
        writeGeneration = library.generation; libraryValidity = library.validity
    }

    func changeText(_ text: String) {
        guard text != document.text else { return }
        let record = Date().timeIntervalSince(lastTextEdit) > 1
        change(recordUndo: record) { $0.replaceText(text) }
        lastTextEdit = .now
    }

    func editText(_ range: NSRange, replacement: String) {
        do {
            var updated = document
            try updated.applyTextEdit(range, replacement: replacement)
            let record = Date().timeIntervalSince(lastTextEdit) > 1
            change(recordUndo: record) { $0 = updated }
            lastTextEdit = .now
        } catch { actionError = AppCopy.error(error) }
    }

    func savePronunciation(_ reading: Pronunciation) async -> Bool {
        do {
            var updated = document
            try updated.setPronunciation(reading)
            change { $0 = updated }
            return await flush()
        } catch { actionError = AppCopy.error(error); return false }
    }

    func change(recordUndo: Bool = true, _ operation: (inout ScriptDocument) -> Void) {
        let old = document
        operation(&document)
        guard old != document else { return }
        if recordUndo { history.append(old); if history.count > 30 { history.removeFirst() } }
        lastTextEdit = .distantPast
        didEdit()
    }

    func split(_ id: UUID, at offset: Int) {
        do {
            var edited = document
            try edited.split(id, at: offset)
            change { $0 = edited }
        } catch { self.actionError = AppCopy.error(error) }
    }

    func undo() {
        guard var previous = history.popLast() else { return }
        previous.adoptSaveMetadata(from: document)
        document = previous
        lastTextEdit = .distantPast
        didEdit()
    }

    private func didEdit() {
        dirty = true; generation += 1; error = nil
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            _ = await self?.flush()
        }
    }

    /// Drain writes before leaving or starting. An older save cannot overwrite newer edits.
    func flush(finalizeOriginal: Bool = false) async -> Bool {
        debounce?.cancel(); debounce = nil
        guard libraryValidity == library.validity else { error = AppCopy.error(LocalDataError.staleWriter); return false }
        if finalizeOriginal, document.originalText == nil {
            let old = document
            document.captureOriginalIfNeeded()
            if old != document { dirty = true; generation += 1 }
        }
        if let activeSave {
            let succeeded = await activeSave.value
            return succeeded && dirty ? await flush() : succeeded
        }
        guard dirty else { return error == nil }
        let task = Task { await persistPendingEdits() }
        activeSave = task
        let succeeded = await task.value
        return succeeded && dirty ? await flush() : succeeded
    }

    private func persistPendingEdits() async -> Bool {
        saving = true
        defer { activeSave = nil; saving = false }
        while dirty {
            let snapshot = document, savedGeneration = generation
            do {
                let saved = try await library.repository.save(snapshot, generation: writeGeneration)
                library.accept(saved, validity: libraryValidity)
                if generation == savedGeneration { document = saved; dirty = false }
                else { document.adoptSaveMetadata(from: saved) }
                error = nil
            } catch {
                self.error = AppCopy.text("Couldn’t save. Your edits are still on this screen.") + " " + AppCopy.error(error)
                return false
            }
        }
        return true
    }
}
