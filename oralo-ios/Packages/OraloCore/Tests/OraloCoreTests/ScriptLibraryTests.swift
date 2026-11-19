import Foundation
import Synchronization
import Testing
@testable import OraloCore

struct ScriptLibraryTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("oralo-library-\(UUID().uuidString)")
    }

    @Test func savedScriptsSurviveRelaunchAndDeletion() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScriptLibraryRepository(directory: directory)
        #expect(try await repository.load().documents.isEmpty)
        let first = try await repository.save(ScriptDocument(title: "Quarterly report", text: "今天汇报。\n下一步改善交付。"))
        var edited = first
        edited.title = "Renamed"
        edited.localeID = "en-US"
        edited.replaceText("今天汇报。\n下一步守住质量。")
        let saved = try await repository.save(edited)
        #expect(saved.revision == 2)
        let reopened = try await ScriptLibraryRepository(directory: directory).load().documents
        #expect(reopened == [saved])
        #expect(reopened[0].originalText == first.text)
        #expect(reopened[0].segments.first?.id == first.segments.first?.id)
        try await repository.delete(id: saved.id, revision: saved.revision)
        #expect(try await ScriptLibraryRepository(directory: directory).load().documents.isEmpty)
    }

    @Test func concurrentStaleEditsCannotOverwriteOrResurrectDeletedScript() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScriptLibraryRepository(directory: directory)
        let first = try await repository.save(ScriptDocument(text: "A saved talk."))
        var newer = first; newer.title = "New title"
        let latest = try await repository.save(newer)
        await #expect(throws: ScriptLibraryError.conflict) { try await repository.save(first) }
        await #expect(throws: ScriptLibraryError.conflict) { try await repository.delete(id: first.id, revision: first.revision) }
        try await repository.delete(id: latest.id, revision: latest.revision)
        await #expect(throws: ScriptLibraryError.conflict) { try await repository.save(latest) }
    }

    @Test func autosaveDoesNotTrimTitleBeingTyped() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScriptLibraryRepository(directory: directory)
        var document = try await repository.save(ScriptDocument(title: "Board ", text: "A talk."))
        #expect(document.title == "Board ")
        document.title += "report"
        #expect(try await repository.save(document).displayTitle == "Board report")
        #expect(ScriptDocument(title: "  ").displayTitle == "Untitled script")
    }

    @Test func damagedPrimaryRecoversValidatedBackupAndKeepsDamagedBytes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScriptLibraryRepository(directory: directory)
        let first = try await repository.save(ScriptDocument(text: "A complete talk."))
        var latest = first; latest.title = "Latest title"
        _ = try await repository.save(latest)
        try Data("{broken".utf8).write(to: directory.appendingPathComponent("library.json"))
        let result = try await ScriptLibraryRepository(directory: directory).load()
        #expect(result.recoveredFromBackup)
        #expect(result.documents == [first])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix("unreadable-") })
        #expect(try await ScriptLibraryRepository(directory: directory).load().documents == [first])
    }

    @Test func unknownSchemaNeverRollsBackToOldBackupOrOverwritesFiles() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScriptLibraryRepository(directory: directory)
        _ = try await repository.save(ScriptDocument(text: "A talk."))
        let future = Data("{\"schemaVersion\":99,\"documents\":[]}".utf8)
        let primary = directory.appendingPathComponent("library.json")
        try future.write(to: primary)
        let reopened = ScriptLibraryRepository(directory: directory)
        await #expect(throws: ScriptLibraryError.newerVersion) { try await reopened.load() }
        await #expect(throws: ScriptLibraryError.newerVersion) { try await reopened.save(ScriptDocument(text: "New")) }
        #expect(try Data(contentsOf: primary) == future)
    }

    @Test func writeFailureKeepsLastSavedDiskAndMemoryState() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let failWrites = Mutex(false)
        let repository = ScriptLibraryRepository(directory: directory) { data, url in
            if url.lastPathComponent == "library.json", failWrites.withLock({ $0 }) { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        let first = try await repository.save(ScriptDocument(text: "Keep this text."))
        let primary = directory.appendingPathComponent("library.json")
        let originalBytes = try Data(contentsOf: primary)
        failWrites.withLock { $0 = true }
        var edited = first; edited.replaceText("A new draft.")
        await #expect(throws: CocoaError.self) { try await repository.save(edited) }
        #expect(try Data(contentsOf: primary) == originalBytes)
        #expect(try await repository.load().documents == [first])
        #expect(try await ScriptLibraryRepository(directory: directory).load().documents == [first])
        failWrites.withLock { $0 = false }
        #expect(try await repository.save(edited).text == "A new draft.")
    }

    @Test func bothCorruptCopiesBlockMutations() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["library.json", "library.backup.json"] { try Data("broken".utf8).write(to: directory.appendingPathComponent(name)) }
        let repository = ScriptLibraryRepository(directory: directory)
        await #expect(throws: ScriptLibraryError.corruptLibrary) { try await repository.save(ScriptDocument(text: "New")) }
        #expect(try String(contentsOf: directory.appendingPathComponent("library.json"), encoding: .utf8) == "broken")
    }

    @Test func oversizedDraftIsSavedInFullButCannotStartUntilSplit() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = String(repeating: "稿", count: 450)
        let repository = ScriptLibraryRepository(directory: directory)
        var saved = try await repository.save(ScriptDocument(text: text))
        #expect(throws: ScriptLibraryError.speakingLimit) { try saved.snapshot() }
        try saved.split(saved.segments[0].id, at: 200)
        let final = try await repository.save(saved)
        #expect(try final.snapshot().cues.count == 2)
        #expect(try await ScriptLibraryRepository(directory: directory).load().documents[0].originalText == text)
    }
}

struct ScriptDocumentTests {
    @Test(arguments: ["roadmap", "夯实基础", "👨‍👩‍👦é中文", "some words", "🇨🇳🇺🇸你好"])
    func splitMergePreservesExactGraphemes(text: String) throws {
        var document = ScriptDocument(text: text)
        let id = document.segments[0].id
        document.togglePause(id)
        try document.split(id, at: 1)
        #expect(document.segments.map(\.text).joined() == text)
        #expect(document.segments[0].id == id)
        #expect(document.segments.last?.pauseAfter == true)
        document.mergeWithNext(id)
        #expect(document.segments[0].text == text)
        #expect(document.segments[0].pauseAfter)
        #expect(document.originalText == text)
    }

    @Test func mergePreservesOriginalSpacingAndLineBreaks() {
        let text = "First sentence.  Second sentence.\r\nThird sentence."
        var document = ScriptDocument(text: text)
        while document.segments.count > 1 { document.mergeWithNext(document.segments[0].id) }
        #expect(document.segments[0].text == text)
    }

    @Test func snapshotIsImmutableAndKeepsStableCueIDsWithoutPauseTokens() throws {
        var document = ScriptDocument(text: "今天汇报团队进展。\n接下来改善交付质量。")
        document.togglePause(document.segments[0].id)
        let snapshot = try document.snapshot()
        document.replaceText("已经改成另外一篇稿。")
        #expect(snapshot.cues[0].text == "今天汇报团队进展。")
        #expect(snapshot.pauseAfter.contains(snapshot.cues[0].id))
        var engine = try FollowEngine(cues: snapshot.cues)
        engine.resume()
        engine.ingest("接下来改善交付质量", isFinal: true, token: engine.session.contextToken, sequence: 1)
        #expect(engine.session.currentIndex == 1)
        #expect(!snapshot.cues[0].text.contains("⏸"))
    }

    @Test func unchangedRepeatedSentencesKeepDistinctIdentities() {
        var document = ScriptDocument(text: "重复句。\n重复句。\n结论。")
        let ids = document.segments.map(\.id)
        document.replaceText("开场白。\n重复句。\n重复句。\n结论。")
        #expect(Array(document.segments.dropFirst().map(\.id)) == ids)
        #expect(Set(document.segments.map(\.id)).count == 4)
    }

    @Test func emptyDraftCanBeEditedButNotSpoken() {
        var draft = ScriptDocument()
        #expect(throws: ScriptLibraryError.emptyScript) { try draft.snapshot() }
        draft.replaceText("My first talk.")
        draft.captureOriginalIfNeeded()
        draft.replaceText("My revised talk.")
        draft.captureOriginalIfNeeded()
        #expect(draft.originalText == "My first talk.")
    }

    @Test func undoKeepsCapturedOriginalAndLatestSaveRevision() async throws {
        var document = ScriptDocument()
        document.replaceText("First complete draft.")
        var undoState = document
        document.captureOriginalIfNeeded()
        document.revision = 7
        document.replaceText("Revised text.")
        undoState.adoptSaveMetadata(from: document)
        #expect(undoState.originalText == "First complete draft.")
        #expect(undoState.revision == 7)
        #expect(undoState.text == "First complete draft.")
    }
}

struct PlainTextImportTests {
    @Test(arguments: [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian])
    func importsUnicodeAndKeepsMarkdownAndWhitespace(encoding: String.Encoding) throws {
        let text = "# 题目\r\n\n正文 roadmap 👨‍👩‍👦\n"
        let bom: [UInt8] = encoding == .utf8 ? [0xEF, 0xBB, 0xBF] : encoding == .utf16LittleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]
        let data = Data(bom) + (try #require(text.data(using: encoding)))
        #expect(try PlainTextImport.decode(data, filename: "演讲.MD") == text)
    }

    @Test func rejectsUnsupportedBinaryAndOversizeInputWithoutTruncating() {
        #expect(throws: ScriptLibraryError.unsupportedFile) { try PlainTextImport.decode(Data(), filename: "talk.pdf") }
        #expect(throws: ScriptLibraryError.unsupportedText) { try PlainTextImport.decode(Data([0, 1, 2, 3]), filename: "talk.txt") }
        #expect(throws: ScriptLibraryError.unsupportedText) { try PlainTextImport.decode(Data([0x80, 0xFF, 0x44]), filename: "talk.txt") }
        #expect(throws: ScriptLibraryError.fileTooLarge) { try PlainTextImport.decode(Data(repeating: 65, count: PlainTextImport.maximumBytes + 1), filename: "talk.txt") }
    }

    @Test func fileReadIsBoundedAndNeverModifiesSource() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("  重要数据 18%\n\n结论  ".utf8)
        try data.write(to: url)
        #expect(try PlainTextImport.read(url) == String(decoding: data, as: UTF8.self))
        #expect(try Data(contentsOf: url) == data)
    }
}
