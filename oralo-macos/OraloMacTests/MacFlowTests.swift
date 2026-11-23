import Foundation
import AppKit
import Testing
import OraloCore
@testable import OraloMac

@MainActor struct MacFlowTests {
    @Test func nativeTextInputAndImportPersist() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "Quarterly report.txt")
        try "接下来完善 roadmap。".write(to: file, atomically: true, encoding: .utf16)
        let library = MacLibrary(directory: directory.appending(path: "Library"))
        await library.load()
        await library.importFile(file)
        let editor = try #require(library.editor)
        #expect(editor.document.title == "Quarterly report")
        let view = ManuscriptTextView()
        let delegate = ManuscriptEditor.Coordinator(editor: editor)
        view.delegate = delegate
        view.refresh(editor.document)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.insertText("今天，", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "今天，接下来完善 roadmap。")
        #expect(editor.document.text == view.string)
        let committed = editor.document.text
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        view.setMarkedText("pin", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.document.text == committed)
        view.insertText("拼音", replacementRange: view.markedRange())
        #expect(editor.document.text == committed + "拼音")
        #expect(await editor.flush())
        let reopened = MacLibrary(directory: directory.appending(path: "Library"))
        await reopened.load()
        #expect(reopened.editor?.document.text == view.string)
        // TextKit must be allowed to grow past the viewport for long manuscripts.
        let long = ScriptDocument(text: String(repeating: "这是下一句演讲稿。\n", count: 80))
        view.refresh(long)
        view.sizeToFit()
        #expect(view.frame.height > 500)
    }
    @Test func cameraPlacementSurvivesExternalDisplayRemoval() {
        let display = CGRect(x: 0, y: 70, width: 1440, height: 830)
        let camera = FloatingGeometry.nearCamera(size: FloatingGeometry.standard, visible: display)
        #expect(camera.midX == display.midX)
        #expect(camera.maxY == display.maxY - 8)
        let orphan = CGRect(x: -2600, y: 2200, width: 680, height: 280)
        #expect(display.contains(FloatingGeometry.clamp(orphan, to: display)))
        let resized = FloatingGeometry.resize(camera, size: FloatingGeometry.wide, visible: display)
        #expect(resized.maxY == camera.maxY)
        #expect(resized.midX == camera.midX)
        let leftDock = CGRect(x: 80, y: 30, width: 1360, height: 840)
        #expect(FloatingGeometry.nearCamera(size: FloatingGeometry.standard, visible: leftDock, displayCenterX: 720).midX == 720)
    }
    @Test func savedReadingsSurviveEditSaveReopenAndDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MacLibrary(directory: directory)
        await library.load()
        await library.create(text: "接下来继续夯实基础，完善 roadmap。", title: "Test")
        let editor = try #require(library.editor)
        let range = (editor.document.text as NSString).range(of: "roadmap")
        let hint = Pronunciation(span: TextSpan(range), term: "roadmap", reading: "/ˈroʊdˌmæp/", kind: .ipa)
        #expect(await editor.savePronunciation(hint))
        editor.editText(NSRange(location: 0, length: 0), replacement: "今天，")
        #expect(await editor.flush())
        let reopened = MacLibrary(directory: directory)
        await reopened.load()
        let document = try #require(reopened.editor?.document)
        #expect(document.pronunciations.first?.isAnchored(in: document.text) == true)
        #expect(try document.snapshot().pronunciations.values.flatMap { $0 }.count == 1)
        await reopened.deleteCurrent()
        let backup = directory.appending(path: "library.backup.json")
        #expect(String(decoding: try Data(contentsOf: backup), as: UTF8.self).contains("roadmap") == false)
        let primary = directory.appending(path: "library.json")
        try Data("broken".utf8).write(to: primary)
        let afterCorruption = ScriptLibraryRepository(directory: directory)
        #expect(try await afterCorruption.load().documents.isEmpty)
    }
    @Test func build14RecoveryAndStaleCallbackProtection() throws {
        let sample = QuickScript.sample(localization: "zh-Hans")
        let snapshot = try ScriptDocument(text: sample.text).snapshot()
        let session = try MacSpeechSession(snapshot: snapshot)
        defer { session.pause() }
        let request = UUID()
        session.receive(.started(id: request, engine: "test"))
        session.receive(.transcript(id: request, text: snapshot.cues[0].text, isFinal: true, deliveryDelay: 0.2))
        #expect(session.follower.reading.confirmedCharacterCount > 0)
        session.receive(.transcript(id: request, text: "紫色火星山谷中的宇宙旅行者正在漫步", isFinal: true, deliveryDelay: nil))
        #expect(session.currentIndex == 0)
        session.receive(.transcript(id: request, text: snapshot.cues[8].text, isFinal: true, deliveryDelay: 0.2))
        #expect(session.currentIndex == 8)
        session.pause()
        session.receive(.transcript(id: request, text: snapshot.cues[1].text, isFinal: true, deliveryDelay: nil))
        #expect(session.currentIndex == 8)
        #expect(!session.recording)
    }
}
