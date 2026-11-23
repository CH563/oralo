import SwiftUI
import OraloCore

struct WorkspaceView: View {
    let model: MacAppModel
    @Environment(\.colorScheme) private var scheme
    @State private var selection: ReadingSelection?


    var body: some View {
        Group {
            switch model.route {
            case .welcome: MacWelcomeView(model: model)
            case .library: ScriptLibraryView(model: model)
            case .editor:
                NavigationSplitView {
                    EditorSidebar(model: model)
                        .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
                } detail: {
                    if let editor = model.library.editor {
                        EditorPane(editor: editor, model: model, selection: $selection)
                            .id(editor.document.id)
                    }
                }
                .navigationSplitViewStyle(.balanced)

            }
        }
        .navigationTitle(model.route == .editor ? MacCopy.text("备稿", "Prepare") : model.route == .library ? MacCopy.text("稿库", "Scripts") : "Oralo")
        .toolbar {
            if model.route == .editor {
                ToolbarItem(placement: .navigation) {
                    Button { Task { await model.showLibrary() } } label: {
                        Label(MacCopy.text("返回稿库", "All scripts"), systemImage: "chevron.left")
                    }.accessibilityIdentifier("back-to-library").help(MacCopy.text("返回稿库", "All scripts"))
                }
            }
            if model.route != .welcome {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { Task { await model.create() } } label: { Label(MacCopy.text("新建讲稿", "New script"), systemImage: "square.and.pencil") }
                        .accessibilityIdentifier("new-script").help(MacCopy.text("新建讲稿（⌘N）", "New script (⌘N)"))
                        .disabled(!model.library.loaded)
                    Button(action: model.importFile) { Label(MacCopy.text("导入", "Import"), systemImage: "tray.and.arrow.down") }
                        .accessibilityIdentifier("import-script").help(MacCopy.text("导入文本（⌘O）", "Import text (⌘O)"))
                }
            }
            if model.route == .library {
                ToolbarItem(placement: .primaryAction) { LibraryLayoutPicker(preferences: model.preferences) }
                ToolbarItem(placement: .primaryAction) {
                    ScriptSearchField(text: Binding(get: { model.search }, set: { model.search = $0 }), focusRequest: model.searchFocus)
                        .frame(width: 230)
                }
            }
            if model.route == .editor {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { Task { await model.start() } } label: { Label(MacCopy.text("开讲", "Start speaking"), systemImage: "play") }
                        .help(MacCopy.text("开始演讲（⌘↩）", "Start speaking (⌘↩)"))
                        .accessibilityIdentifier("start-speaking")
                        .disabled(model.library.editor?.document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                    Button { Task { await model.start(floating: true) } } label: { Label(MacCopy.text("悬浮开讲", "Float near camera"), systemImage: "pip.enter") }
                        .help(MacCopy.text("悬浮开讲", "Float near camera")).accessibilityIdentifier("start-floating")
                        .disabled(model.library.editor?.document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                    Menu {
                        Button(MacCopy.text("开始排练", "Start rehearsal")) { Task { await model.start(rehearsal: true) } }
                        Button(MacCopy.text("本稿记录", "Script history")) { model.showHistory(scriptID: model.library.editor?.document.id) }
                        Divider()
                        ForEach(EditorTool.allCases) { tool in Button(tool.title) { model.tool = tool } }
                        Button(MacCopy.text("导出纯文本…", "Export plain text…"), action: model.exportText)
                    } label: { Label(MacCopy.text("讲稿工具", "Script tools"), systemImage: "ellipsis.circle") }
                        .help(MacCopy.text("排练、注音与分句", "Rehearsal, readings and sentence layout"))
                    Button(role: .destructive) { model.confirmingDeletion = true } label: { Label(MacCopy.text("删除讲稿", "Delete script"), systemImage: "trash") }
                        .help(MacCopy.text("删除当前讲稿", "Delete current script"))
                        .disabled(model.windows.session != nil)
                }
            }
            ToolbarItem(placement: .primaryAction) { UsageGuideButton() }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(MacStyle.canvas(scheme))
        .disabled(model.library.working)
        .sheet(item: $selection) { selection in
            if let editor = model.library.editor {
                ReadingSheet(editor: editor, selection: selection, willPlay: { model.windows.session?.pause() }, didSave: { reading in
                    Task { await model.completeReadingReview(.added, reading: reading) }
                })
            }
        }
        .sheet(item: Binding(get: { model.startRequest }, set: { model.startRequest = $0 })) { ReadinessView(request: $0, model: model) }
        .sheet(isPresented: Binding(get: { model.showingHistory }, set: { model.showingHistory = $0 })) { RehearsalHistoryView(model: model) }
        .sheet(item: Binding(get: { model.tool }, set: { model.tool = $0 })) { tool in
            if let editor = model.library.editor { EditorToolsView(tool: tool, editor: editor, model: model) }
        }
        .alert(MacCopy.text("删除这篇讲稿？", "Delete this script?"), isPresented: Binding(get: { model.confirmingDeletion }, set: { model.confirmingDeletion = $0 })) {
            Button(MacCopy.text("删除", "Delete"), role: .destructive) {
                Task {
                    let deletingID = model.library.editor?.document.id
                    if let deletingID { await model.removeData(.script(deletingID)) }
                    if !model.library.documents.contains(where: { $0.id == deletingID }) { model.route = .library }
                }
            }
            Button(MacCopy.text("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(MacCopy.text("本机稿件、注音、排练与演讲记录、历史快照和恢复副本会一并删除。", "The script, readings, session history, snapshots and recovery copies will be removed."))
        }
        .safeAreaInset(edge: .bottom) {
            if let message = model.error ?? model.library.editor?.error ?? model.library.error ?? model.library.recoveryNotice {
                HStack {
                    Text(message).font(.callout).textSelection(.enabled)
                    if !model.library.loaded || model.library.removalBlocked {
                        Button(MacCopy.text("重试", "Retry")) { Task { await model.library.load() } }.oraloActionStyle()
                    }
                }.padding(12).frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
    }
}

private struct EditorSidebar: View {
    let model: MacAppModel
    @State private var search = ""
    private var documents: [ScriptDocument] {
        model.library.documents.filter { search.isEmpty || $0.displayTitle.localizedStandardContains(search) || $0.text.localizedStandardContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(MacCopy.text("讲稿", "Scripts")).font(.title3.bold()).padding(.horizontal, 8)
            ScriptSearchField(text: $search, focusRequest: model.searchFocus).frame(height: 28)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(documents) { document in
                        Button { Task { await model.open(document) } } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(document.displayTitle).font(.headline).lineLimit(2)
                                Text(MacCopy.metrics(document.text, preferences: model.preferences)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(model.library.editor?.document.id == document.id ? MacStyle.accent.opacity(0.14) : .clear, in: .rect(cornerRadius: 16))
                                .contentShape(.rect(cornerRadius: 16))
                        }.buttonStyle(.plain).accessibilityIdentifier("script-\(document.id)")
                    }
                    if documents.isEmpty { Text(MacCopy.text("没有匹配的讲稿", "No matching scripts")).foregroundStyle(.secondary).padding() }
                }
            }
        }.padding(14).padding(.top, 8)
    }
}
