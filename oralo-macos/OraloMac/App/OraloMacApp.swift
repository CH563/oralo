import AppKit
import SwiftUI
import Observation
import OraloCore

@MainActor @Observable
final class MacAppModel {
    enum WorkspaceRoute { case welcome, library, editor }
    let library: MacLibrary
    let preferences: MacPreferences
    let windows: PresentationWindows
    var error: String?
    var route: WorkspaceRoute = .welcome
    var search = ""
    var searchFocus = UUID()
    var confirmingDeletion = false
    var startRequest: StartRequest?
    var showingHistory = false
    var historyScriptID: UUID?
    var reviewID: UUID?
    var tool: EditorTool?
    var reviewContext: ReviewContext?
    var passageNotice: String?
    var rehearsals: RehearsalStore { library.rehearsals }
    var canManageData: Bool { library.loaded && !library.working && !library.removalBlocked && !rehearsals.working && startRequest == nil && windows.session == nil && windows.closingTask == nil && rehearsals.activeSessions.isEmpty }
    var canEraseData: Bool { !library.working && !library.removalBlocked && !rehearsals.working && startRequest == nil && windows.session == nil && windows.closingTask == nil && rehearsals.activeSessions.isEmpty }
    struct ReviewContext { let recordID: UUID; let cueID: UUID }

    init() {
        var directory = URL.applicationSupportDirectory.appending(path: "OraloMac/Library", directoryHint: .isDirectory)
        var defaults = UserDefaults.standard
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-library=") }),
           let id = UUID(uuidString: String(argument.dropFirst("--ui-library=".count))) {
            directory = URL.applicationSupportDirectory.appending(path: "OraloMacUITests/\(id.uuidString)")
            defaults = UserDefaults(suiteName: "com.ch563.oralo.mac.tests.\(id.uuidString)") ?? .standard
        }
        #endif
        preferences = MacPreferences(defaults: defaults)
        library = MacLibrary(directory: directory, preferences: preferences)
        windows = PresentationWindows(preferences: preferences)
        route = preferences.showWelcome ? .welcome : .library
        windows.onFinished = { [weak self] recorder in
            guard let self, let record = recorder.record else { return }
            self.reviewID = record.id; self.historyScriptID = record.scriptID
            self.error = recorder.saveError
            // Finishing a floating prompt must not activate Oralo over a meeting.
            guard NSApp.isActive else { return }
            self.showingHistory = true
            NSApp.windows.first(where: { $0.identifier?.rawValue == "workspace" })?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    func showLibrary() async {
        guard !library.working, await library.editor?.flush() != false else { return }
        route = .library
    }
    func open(_ document: ScriptDocument) async {
        if library.editor?.document.id != document.id { reviewContext = nil; passageNotice = nil }
        await library.select(document)
        if library.editor?.document.id == document.id { route = .editor }
    }
    func create(sample: Bool = false) async {
        let previous = library.editor?.document.id
        if sample { await library.createSample() } else { await library.create(localeID: preferences.defaultLocale) }
        if let current = library.editor?.document.id, current != previous { route = .editor; reviewContext = nil; passageNotice = nil }
    }
    func start(floating: Bool = false, rehearsal: Bool = false) async {
        if windows.session != nil { if floating { windows.showFloating() } else { windows.showReader() }; return }
        if let recorder = windows.lastRecorder, recorder.saveError != nil {
            await recorder.flush()
            guard recorder.saveError == nil else { error = recorder.saveError; return }
            error = nil
        }
        guard windows.closingTask == nil, rehearsals.loaded, let editor = library.editor, !library.working else { return }
        guard await editor.flush(finalizeOriginal: true) else { return }
        do {
            _ = try editor.document.snapshot()
            startRequest = StartRequest(document: editor.document, floating: floating,
                kind: rehearsal ? .rehearsal : .presentation,
                initialMode: floating ? preferences.floatingMode : preferences.startingMode)
        } catch { self.error = MacCopy.error(error) }
    }
    func launch(_ request: StartRequest, mode: PromptMode) async {
        guard windows.session == nil, windows.closingTask == nil, !library.working,
              let current = library.documents.first(where: { $0.id == request.document.id }),
              current.revision == request.document.revision else { startRequest = nil; return }
        do {
            let snapshot = try current.snapshot()
            let recorder = RehearsalRecorder(document: current, kind: request.kind, input: mode == .voice ? .voice : .manual, store: rehearsals)
            let session: MacSpeechSession
            do { session = try MacSpeechSession(snapshot: snapshot, document: current, mode: mode, preferences: preferences, recorder: recorder) }
            catch { await recorder.finish(completed: false); throw error }
            if request.floating { preferences.floatingMode = mode } else { preferences.startingMode = mode }
            if mode != .fixed { preferences.followsVoice = mode == .voice }
            startRequest = nil
            // Allow the preparation sheet to dismiss before presenting another window.
            await Task.yield()
            windows.begin(session, floating: request.floating)
        } catch { self.error = MacCopy.error(error) }
    }
    func showHistory(scriptID: UUID? = nil) {
        historyScriptID = scriptID; reviewID = nil; showingHistory = true
    }
    func editReviewedPassage(record: RehearsalRecord, cueID: UUID, pronunciation: Bool = false) async {
        guard let snapshot = rehearsals.snapshots[record.snapshotID],
              let document = library.documents.first(where: { $0.id == record.scriptID }) else {
            error = MacCopy.text("原讲稿已删除。", "The original script has been deleted."); return
        }
        showingHistory = false
        await open(document)
        guard library.editor?.document.id == document.id else { return }
        if let current = library.editor?.document, let span = snapshot.editRange(cueID: cueID, in: current) {
            library.editor?.revealPassage(span.nsRange); passageNotice = nil
        } else {
            passageNotice = MacCopy.text("这段原句已修改或无法唯一定位。请在当前讲稿中手动查找。", "This passage changed or is ambiguous. Locate it manually in the current script.")
        }
        reviewContext = pronunciation ? ReviewContext(recordID: record.id, cueID: cueID) : nil
    }
    func completeReadingReview(_ status: PronunciationReview.Status, reading: Pronunciation? = nil) async {
        guard let context = reviewContext,
              let record = rehearsals.records.first(where: { $0.id == context.recordID }),
              let document = library.editor?.document, document.id == record.scriptID else { return }
        if status == .added, let reading {
            guard let range = rehearsals.snapshots[record.snapshotID]?.editRange(cueID: context.cueID, in: document)?.nsRange,
                  let selected = reading.span?.nsRange, NSIntersectionRange(range, selected) == selected else {
                passageNotice = MacCopy.text("注音已保存。当前文字与历史片段不再完全对应，请手动确认复盘结果。", "The reading was saved. This text no longer maps exactly to the historical passage; confirm the review manually.")
                return
            }
        }
        let result = PronunciationReview(cueID: context.cueID, span: reading?.span, pronunciationID: reading?.id, status: status)
        if await rehearsals.setPronunciationReview(result, cueID: context.cueID, recordID: context.recordID) {
            reviewContext = nil; passageNotice = nil
        } else { error = rehearsals.error }
    }
    func removeData(_ operation: LocalDataRemoval.Operation) async {
        guard operation == .all ? canEraseData : canManageData else { return }
        windows.discardFinishedRecorder()
        await library.remove(operation)
        if library.loaded { if operation != .rehearsals { route = .library }; search = ""; reviewContext = nil; passageNotice = nil; reviewID = nil; error = nil }
    }
    func exportText() {
        guard let editor = library.editor else { return }
        let document = editor.document
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = document.displayTitle.replacingOccurrences(of: "/", with: "-") + ".txt"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { try document.text.write(to: url, atomically: true, encoding: .utf8) }
            catch { self?.error = MacCopy.error(error) }
        }
    }
    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]; panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                let previous = self.library.editor?.document.id
                await self.library.importFile(url)
                if let current = self.library.editor?.document.id, current != previous { self.route = .editor }
            }
        }
    }
}

@main struct OraloMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    @State private var model = MacAppModel()
    var body: some Scene {
        Window("Oralo", id: "workspace") {
            WorkspaceView(model: model)
                .preferredColorScheme(model.preferences.colorScheme)
                .task { delegate.model = model; await model.library.load() }
        }
        .defaultSize(width: 1160, height: 780)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            UsageGuideCommands()
            CommandGroup(replacing: .newItem) {
                Button(MacCopy.text("新建讲稿", "New script")) { Task { await model.create() } }.keyboardShortcut("n")
                    .disabled(!model.library.loaded || model.library.working)
                Button(MacCopy.text("导入文本…", "Import text…"), action: model.importFile).keyboardShortcut("o")
                    .disabled(!model.library.loaded || model.library.working)
            }
            CommandGroup(replacing: .saveItem) {
                Button(MacCopy.text("保存", "Save")) { Task { _ = await model.library.editor?.flush() } }.keyboardShortcut("s")
                    .disabled(model.route != .editor)
            }
            CommandGroup(after: .saveItem) {
                Button(MacCopy.text("导出纯文本…", "Export plain text…"), action: model.exportText)
                    .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.route != .editor)
                Button(MacCopy.text("删除讲稿…", "Delete script…"), role: .destructive) { model.confirmingDeletion = true }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.route != .editor || model.windows.session != nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(MacCopy.text("撤销讲稿修改", "Undo script edit")) { model.library.editor?.undo() }.keyboardShortcut("z")
                    .disabled(model.library.editor?.history.isEmpty != false)
            }
            CommandMenu(MacCopy.text("演讲", "Present")) {
                Button(MacCopy.text("开始演讲", "Start speaking")) { Task { await model.start() } }.keyboardShortcut(.return, modifiers: [.command])
                Button(MacCopy.text("悬浮提词", "Floating prompt")) {
                    if model.windows.session != nil { model.windows.showFloating() }
                    else { Task { await model.start(floating: true) } }
                }
                Button(MacCopy.text("开始排练", "Start rehearsal")) { Task { await model.start(rehearsal: true) } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button(MacCopy.text("排练与演讲记录", "Rehearsal and presentation history")) { model.showHistory() }
                Divider()
                Button(MacCopy.text("结束演讲", "End presentation"), action: model.windows.finish)
            }
            CommandMenu(MacCopy.text("稿库", "Library")) {
                Button(MacCopy.text("返回稿库", "Show scripts")) { Task { await model.showLibrary() } }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button(MacCopy.text("显示欢迎页", "Show welcome")) {
                    Task { if await model.library.editor?.flush() != false { model.route = .welcome } }
                }
                Divider()
                Button(MacCopy.text("搜索讲稿", "Find a script")) { model.searchFocus = UUID() }
                    .keyboardShortcut("f").disabled(model.route == .welcome)
                Picker(MacCopy.text("显示方式", "View as"), selection: Binding(get: { model.preferences.libraryLayout }, set: { model.preferences.libraryLayout = $0 })) {
                    Text(MacCopy.text("平铺", "Grid")).tag(MacPreferences.LibraryLayout.grid)
                    Text(MacCopy.text("列表", "List")).tag(MacPreferences.LibraryLayout.list)
                }
                Button(MacCopy.text("示例讲稿", "Create sample script")) { Task { await model.create(sample: true) } }
                    .disabled(!model.library.loaded || model.library.working)
            }
        }
        Window(MacCopy.text("Oralo 使用指南", "Oralo User Guide"), id: "usage-guide") {
            UsageGuideView(preferences: model.preferences)
        }
        .defaultSize(width: 660, height: 660)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        Settings {
            MacSettingsView(model: model)
        }
        MenuBarExtra {
            if let session = model.windows.session {
                Text(session.status)
                Button(session.busy ? MacCopy.text("暂停", "Pause") : MacCopy.text("继续", "Resume"), action: session.toggle)
                Button(MacCopy.text("靠近摄像头", "Move near camera"), action: model.windows.nearCamera)
                Button(MacCopy.text("返回演讲页", "Return to reader"), action: model.windows.showReader)
                Button(MacCopy.text("结束提词", "End session"), action: model.windows.finish)
            } else {
                Text(MacCopy.text("麦克风未启用", "Microphone is off"))
                Button(MacCopy.text("查看复盘记录", "View session history")) {
                    model.showingHistory = true
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.identifier?.rawValue == "workspace" })?.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            UsageGuideButton(compact: false)
            Button(MacCopy.text("打开 Oralo", "Open Oralo")) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.identifier?.rawValue == "workspace" })?.makeKeyAndOrderFront(nil)
            }
        } label: {
            Image(nsImage: MacBrand.menuBarImage)
                .renderingMode(.template).accessibilityLabel("Oralo")
        }
    }
}

@MainActor private enum MacBrand {
    static let menuBarImage: NSImage = {
        let size = NSSize(width: 18, height: 18)
        guard let url = Bundle.main.url(forResource: "MenuBarMark", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else { return NSImage(size: size) }
        // Size the template itself so the native status item uses the same scale.
        image.size = size
        image.isTemplate = true
        return image
    }()
}

@MainActor final class MacAppDelegate: NSObject, NSApplicationDelegate {
    var model: MacAppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        model.windows.end(completed: false, review: false)
        Task {
            await model.windows.closingTask?.value
            await model.windows.lastRecorder?.flush()
            let saved = await model.library.editor?.flush() != false && model.windows.lastRecorder?.saveError == nil
            if !saved {
                let alert = NSAlert()
                alert.messageText = MacCopy.text("本机数据尚未保存", "Your local changes are not saved")
                alert.informativeText = model.library.editor?.error ?? model.windows.lastRecorder?.saveError ?? ""
                alert.addButton(withTitle: MacCopy.text("返回编辑", "Return to editor"))
                alert.runModal()
            }
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}
