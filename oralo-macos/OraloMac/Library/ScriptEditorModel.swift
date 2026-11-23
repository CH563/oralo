import Foundation
import Observation
import OraloCore

@MainActor @Observable
final class ScriptEditorModel {
    struct Reveal { let id = UUID(); let range: NSRange }
    var reveal: Reveal?
    var reattachingReading: Pronunciation?
    func revealPassage(_ range: NSRange) { selectedRange = range; reveal = Reveal(range: range) }
    var selectedRange = NSRange(location: 0, length: 0)
    private(set) var document: ScriptDocument
    private(set) var saving = false
    private(set) var dirty = false
    private(set) var history: [ScriptDocument] = []
    var error: String?
    var actionError: String?
    let library: MacLibrary
    private let writeGeneration: UUID
    private let libraryValidity: UUID
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var activeSave: Task<Bool, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastTextEdit = Date.distantPast

    init(document: ScriptDocument, library: MacLibrary) {
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
        } catch { actionError = MacCopy.error(error) }
    }

    func savePronunciation(_ reading: Pronunciation) async -> Bool {
        do {
            var updated = document
            try updated.setPronunciation(reading)
            change { $0 = updated }
            return await flush()
        } catch { actionError = MacCopy.error(error); return false }
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
        actionError = nil
        do {
            var edited = document
            try edited.split(id, at: offset)
            change { $0 = edited }
        } catch { self.actionError = MacCopy.error(error) }
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
        guard libraryValidity == library.validity else { error = MacCopy.error(LocalDataError.staleWriter); return false }
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
                self.error = MacCopy.text("Couldn’t save. Your edits are still on this screen.") + " " + MacCopy.error(error)
                return false
            }
        }
        return true
    }
}
