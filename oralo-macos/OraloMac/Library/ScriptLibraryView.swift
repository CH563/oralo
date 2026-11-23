import SwiftUI
import AppKit
import OraloCore

struct ScriptLibraryView: View {
    @Bindable var model: MacAppModel
    @Environment(\.colorScheme) private var scheme
    private var documents: [ScriptDocument] {
        let query = model.search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.library.documents.filter {
            query.isEmpty || $0.displayTitle.localizedStandardContains(query) || $0.text.localizedStandardContains(query)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(MacCopy.text("全部讲稿", "All scripts")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(MacCopy.text("\(documents.count) 篇讲稿", "\(documents.count) \(documents.count == 1 ? "script" : "scripts")"))
                    .font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("script-count")
            }
            if documents.isEmpty {
                LibraryEmptyView(model: model, searching: !model.search.isEmpty)
            } else {
                ScrollView {
                    if model.preferences.libraryLayout == .grid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 400), spacing: 20, alignment: .top)], spacing: 20) {
                            ForEach(documents) { document in
                                LibraryDocument(document: document, preferences: model.preferences, grid: true) { Task { await model.open(document) } }
                            }
                        }.padding(2).accessibilityIdentifier("library-grid")
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(documents) { document in
                                LibraryDocument(document: document, preferences: model.preferences, grid: false) { Task { await model.open(document) } }
                            }
                        }.padding(2).accessibilityIdentifier("library-list")
                    }
                }.accessibilityIdentifier("script-collection")
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacStyle.canvas(scheme))
    }
}

struct LibraryLayoutPicker: View {
    @Bindable var preferences: MacPreferences
    var body: some View {
        Picker(MacCopy.text("稿库布局", "Library layout"), selection: $preferences.libraryLayout) {
            Label(MacCopy.text("平铺", "Grid"), systemImage: "square.grid.2x2").tag(MacPreferences.LibraryLayout.grid)
            Label(MacCopy.text("列表", "List"), systemImage: "list.bullet").tag(MacPreferences.LibraryLayout.list)
        }.pickerStyle(.segmented).labelsHidden().labelStyle(.iconOnly).frame(width: 72)
            .accessibilityIdentifier("library-layout")
    }
}

/// Use the macOS search field for native focus, clear-button and keyboard behavior.
struct ScriptSearchField: NSViewRepresentable {
    @Binding var text: String
    var focusRequest: UUID?
    func makeCoordinator() -> Coordinator { Coordinator(text: $text, focusRequest: focusRequest) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = MacCopy.text("搜索讲稿", "Search scripts")
        field.controlSize = .regular
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("script-search")
        field.setAccessibilityLabel(MacCopy.text("搜索标题或正文", "Search titles or text"))
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            field.window?.makeFirstResponder(field)
        }
    }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var focusRequest: UUID?
        init(text: Binding<String>, focusRequest: UUID?) { self.text = text; self.focusRequest = focusRequest }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

private struct LibraryEmptyView: View {
    let model: MacAppModel
    let searching: Bool
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: searching ? "doc.text.magnifyingglass" : "doc.text")
                .font(.system(size: 38, weight: .light)).foregroundStyle(MacStyle.accent)
            Text(searching ? MacCopy.text("没有找到这篇讲稿", "No scripts found") : MacCopy.text("下一句，从这里开始。", "Your next line starts here."))
                .font(.title2.bold())
            Text(searching ? MacCopy.text("试试标题或正文里的其他词。", "Try another word from the title or script.") : MacCopy.text("新建、导入，或从一篇示例开始。", "Create, import, or start with a sample."))
                .foregroundStyle(.secondary)
            if searching {
                Button(MacCopy.text("清除搜索", "Clear search")) { model.search = "" }.oraloActionStyle()
            } else {
                Button(MacCopy.text("试试示例讲稿", "Try the sample script")) { Task { await model.create(sample: true) } }
                    .oraloActionStyle().controlSize(.large).accessibilityIdentifier("sample-script")
                    .disabled(!model.library.loaded)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
    }
}

private struct LibraryDocument: View {
    let document: ScriptDocument
    let preferences: MacPreferences
    let grid: Bool
    let open: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    private var excerpt: String {
        document.text.prefix(300).split(whereSeparator: { $0.isNewline }).joined(separator: " ")
    }
    var body: some View {
        Button(action: open) {
            Group {
                if grid {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "doc.text").font(.title3).foregroundStyle(.secondary)
                            Spacer()
                            Text(document.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(document.displayTitle).font(.system(size: 21, weight: .semibold)).lineLimit(2)
                            .help(document.displayTitle)
                        Text(excerpt.isEmpty ? MacCopy.text("写下你的第一句话…", "Write your first line…") : excerpt)
                            .font(.callout).foregroundStyle(.secondary).lineSpacing(5).lineLimit(2, reservesSpace: true)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Divider().overlay(Color.primary.opacity(0.02))
                        Text(MacCopy.metrics(document.text, preferences: preferences)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }.padding(22).frame(minHeight: 220)
                } else {
                    HStack(spacing: 18) {
                        Image(systemName: "doc.text").font(.title2).foregroundStyle(.secondary).frame(width: 34)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(document.displayTitle).font(.headline).lineLimit(1).help(document.displayTitle)
                            Text(excerpt.isEmpty ? MacCopy.text("尚无正文", "No text yet") : excerpt).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 7) {
                            Text(MacCopy.metrics(document.text, preferences: preferences)).lineLimit(1)
                            Text(document.updatedAt, style: .date)
                        }.font(.caption).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.padding(16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Color.white.opacity(hovering ? 0.08 : 0.045) : Color.white.opacity(hovering ? 1 : 0.8), in: .rect(cornerRadius: grid ? 16 : 8))
            .overlay { RoundedRectangle(cornerRadius: grid ? 16 : 8).strokeBorder(hovering ? Color.primary.opacity(0.2) : Color.primary.opacity(0.07), lineWidth: grid ? 1 : 0) }
            .overlay(alignment: .bottom) { if !grid { Divider().padding(.horizontal, 16) } }
            .contentShape(.rect(cornerRadius: grid ? 16 : 8))
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .accessibilityIdentifier("library-script-\(document.id)")
            .accessibilityLabel(document.displayTitle)
            .accessibilityValue(MacCopy.metrics(document.text, preferences: preferences))
            .accessibilityHint(MacCopy.text("打开讲稿进行编辑或开讲", "Open this script to edit or present"))
    }
}
