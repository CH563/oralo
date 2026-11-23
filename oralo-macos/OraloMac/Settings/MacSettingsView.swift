import AppKit
import SwiftUI
import OraloCore

struct MacSettingsView: View {
    let model: MacAppModel
    @State private var confirmation: DataAction?
    @State private var license = false
    @State private var copied = false
    enum DataAction { case rehearsals, all, reading }
    private var preferences: MacPreferences { model.preferences }
    var body: some View {
        TabView {
            general.tabItem { Label(MacCopy.text("通用", "General"), systemImage: "gearshape") }
            reading.tabItem { Label(MacCopy.text("阅读", "Reading"), systemImage: "textformat.size") }
            data.tabItem { Label(MacCopy.text("本机数据", "Local data"), systemImage: "internaldrive") }
            about.tabItem { Label(MacCopy.text("隐私与开源", "Privacy & source"), systemImage: "hand.raised") }
        }.padding(12).frame(width: 640, height: 600).oraloActionStyle()
            .preferredColorScheme(preferences.colorScheme)
            .sheet(isPresented: $license) { LicenseView() }
            .alert(confirmationTitle, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
                Button(MacCopy.text("取消", "Cancel"), role: .cancel) { confirmation = nil }
                Button(confirmation == .reading ? MacCopy.text("恢复默认", "Reset") : MacCopy.text("删除", "Delete"), role: .destructive) {
                    guard let action = confirmation else { return }; confirmation = nil
                    Task {
                        if action == .reading { preferences.resetReading() }
                        else { await model.removeData(action == .all ? .all : .rehearsals) }
                    }
                }.disabled(confirmation == .all ? !model.canEraseData : !model.canManageData)
            } message: { Text(confirmationMessage) }
    }
    private var general: some View {
        Form {
            Section {
                ThemePicker(preferences: preferences)
                Toggle(MacCopy.text("启动时显示欢迎页", "Show welcome at launch"), isOn: Binding(get: { preferences.showWelcome }, set: { preferences.showWelcome = $0 }))
                LabeledContent(MacCopy.text("界面语言", "Interface language"), value: MacCopy.text("跟随 macOS 的应用语言", "Follows the macOS app language"))
                Text(MacCopy.text("可在系统设置 → 通用 → 语言与地区中为 Oralo 选择简体中文、繁体中文或英语。", "Choose English, Simplified Chinese or Traditional Chinese for Oralo in System Settings → General → Language & Region."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(MacCopy.text("快捷键", "Keyboard shortcuts")) {
                LabeledContent(MacCopy.text("新建 / 导入 / 保存", "New / Import / Save"), value: "⌘N / ⌘O / ⌘S")
                LabeledContent(MacCopy.text("搜索 / 返回稿库", "Find / Show library"), value: "⌘F / ⇧⌘L")
                LabeledContent(MacCopy.text("开讲 / 排练", "Present / Rehearse"), value: "⌘↩ / ⇧⌘R")
                LabeledContent(MacCopy.text("导出纯文本", "Export plain text"), value: "⇧⌘E")
                LabeledContent(MacCopy.text("演讲暂停 / 上一句 / 下一句", "Pause / Back / Next in reader"), value: "Space / ← / →")
            }
        }.formStyle(.grouped)
    }
    private var reading: some View {
        Form {
            Section(MacCopy.text("默认开讲方式", "Starting preferences")) {
                Picker(MacCopy.text("新稿语言", "New script language"), selection: Binding(get: { preferences.defaultLocale }, set: { preferences.defaultLocale = $0 })) {
                    Text(MacCopy.text("普通话", "Mandarin")).tag("zh-CN")
                    Text("English (US)").tag("en-US")
                }
                Picker(MacCopy.text("演讲页默认模式", "Default reader mode"), selection: Binding(get: { preferences.startingMode }, set: {
                    preferences.startingMode = $0
                    if $0 != .fixed { preferences.followsVoice = $0 == .voice }
                })) {
                    ForEach(PromptMode.allCases) { Text($0.title).tag($0) }
                }
                Picker(MacCopy.text("悬浮窗默认模式", "Default floating mode"), selection: Binding(get: { preferences.floatingMode }, set: { preferences.floatingMode = $0 })) {
                    ForEach(PromptMode.allCases) { Text($0.title).tag($0) }
                }
                PaceSpeedControl(preferences: preferences, session: model.windows.session)
            }
            Section(MacCopy.text("预计时长与定速语速", "Duration estimates & paced reading")) {
                rate(MacCopy.text("中文：\(Int(preferences.chineseRate)) 字 / 分钟", "Chinese: \(Int(preferences.chineseRate)) characters / min"), value: Binding(get: { preferences.chineseRate }, set: { preferences.chineseRate = $0 }), range: 160...320)
                rate(MacCopy.text("英文：\(Int(preferences.englishRate)) 词 / 分钟", "English: \(Int(preferences.englishRate)) words / min"), value: Binding(get: { preferences.englishRate }, set: { preferences.englishRate = $0 }), range: 100...220)
                Text(MacCopy.text("预计时长不包含自由发挥或额外停顿；语音跟随始终按实际说话节奏。", "Estimates exclude improvisation and extra pauses. Voice following uses your actual speaking pace."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ManuscriptAlignmentPicker(preferences: preferences)
                Button(MacCopy.text("恢复阅读默认值…", "Reset reading preferences…")) { confirmation = .reading }.disabled(!model.canManageData)
            }
        }.formStyle(.grouped)
    }
    private var data: some View {
        Form {
            Section(MacCopy.text("仅保存在这台 Mac", "Stored on this Mac")) {
                LabeledContent(MacCopy.text("讲稿", "Scripts"), value: "\(model.library.documents.count)")
                LabeledContent(MacCopy.text("注音", "Readings"), value: "\(model.library.documents.reduce(0) { $0 + $1.pronunciations.count })")
                LabeledContent(MacCopy.text("排练记录", "Rehearsals"), value: "\(model.rehearsals.records.filter { $0.kind == .rehearsal }.count)")
                LabeledContent(MacCopy.text("演讲记录", "Presentations"), value: "\(model.rehearsals.records.filter { $0.kind == .presentation }.count)")
                LabeledContent(MacCopy.text("历史讲稿快照", "Script snapshots"), value: "\(model.rehearsals.snapshots.count)")
            }
            Section {
                Button(MacCopy.text("清除排练记录…", "Clear rehearsals…"), role: .destructive) { confirmation = .rehearsals }.disabled(!model.canManageData)
                Button(MacCopy.text("删除全部本机数据…", "Delete all local data…"), role: .destructive) { confirmation = .all }.disabled(!model.canEraseData)
            }
            if !model.canManageData {
                Text(MacCopy.text("请先结束演讲并关闭准备检查，再管理本机数据。", "End the session and close readiness before managing local data."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if model.library.removalBlocked || !model.library.loaded {
                Button(MacCopy.text("重试完成数据操作", "Retry pending data operation")) { Task { await model.library.load() } }
            }
            if let error = model.library.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Text(MacCopy.text("会同步清理应用内恢复副本。你导出的文件、系统备份和 Apple 管理的语音模型不在清理范围内。", "App recovery copies are cleaned too. Exported files, system backups and Apple-managed speech models are outside this cleanup."))
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
    private var about: some View {
        Form {
            Section {
                Text("Oralo").font(.title2.bold())
                Text("AI Teleprompter, at Your Pace").foregroundStyle(.secondary)
                LabeledContent(MacCopy.text("版本", "Version"), value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
            }
            Section(MacCopy.text("你的内容留在本机", "Your content stays local")) {
                Text(MacCopy.text("无需账号、无广告、无分析追踪。稿件、注音、偏好和排练记录保存在本机，不上传到 Oralo 服务器。", "No account, ads or analytics. Scripts, readings, preferences and session records stay on this Mac, with no upload to an Oralo server."))
                Text(MacCopy.text("仅使用设备端语音识别。音频与完整转写只在识别时短暂处理，不写入文件；复盘只保留稿件快照、时间和操作线索。", "Speech recognition is on-device. Audio and full transcripts are processed transiently, never written to files. Review stores script snapshots, timing and action cues."))
                Text(MacCopy.text("首次下载 Apple 语音模型需要网络。打开官网和支持链接由浏览器处理。共享整个屏幕时可能包含悬浮窗。", "Downloading Apple speech models requires a connection. Web links open in your browser. Whole-screen sharing may include the floating prompt."))
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Link(MacCopy.text("官网", "Website"), destination: URL(string: "https://oralo.fun")!)
                    Link(MacCopy.text("隐私", "Privacy"), destination: URL(string: "https://oralo.fun/privacy")!)
                    Link("GitHub", destination: URL(string: "https://github.com/CH563/oralo")!)
                    Button(MacCopy.text("开源许可", "Licenses")) { license = true }
                }
                Link(MacCopy.text("反馈与支持", "Feedback & support"), destination: URL(string: "mailto:wonderful563@gmail.com")!)
                Button(copied ? MacCopy.text("已复制环境信息", "Environment details copied") : MacCopy.text("复制支持信息", "Copy support details")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("Oralo macOS \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nRecognition: \(preferences.compatibility ? "compatibility" : "automatic")\nLanguage: \(preferences.defaultLocale)\n", forType: .string)
                    copied = true
                }
            }
        }.formStyle(.grouped)
    }
    private func rate(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) { Text(title); Slider(value: value, in: range, step: 10) { Text(title) }.labelsHidden() }
    }
    private var confirmationTitle: String {
        switch confirmation {
        case .all: MacCopy.text("删除全部本机数据？", "Delete all local data?")
        case .rehearsals: MacCopy.text("清除全部排练记录？", "Clear all rehearsals?")
        default: MacCopy.text("恢复阅读默认值？", "Reset reading preferences?")
        }
    }
    private var confirmationMessage: String {
        switch confirmation {
        case .all: MacCopy.text("将删除讲稿、初稿、注音、所有排练和演讲记录、历史快照与应用恢复副本，同时重置偏好。此操作不能撤销。", "Deletes scripts, initial drafts, readings, all session records, snapshots and app recovery copies, and resets preferences. This cannot be undone.")
        case .rehearsals: MacCopy.text("删除排练记录及不再被引用的快照和副本，保留讲稿、注音和正式演讲记录。此操作不能撤销。", "Deletes rehearsal records and unreferenced snapshots/copies. Scripts, readings and presentation records stay. This cannot be undone.")
        default: MacCopy.text("重置字号、行距、颜色、透明度、对齐、镜像、悬浮位置、开讲方式与语速。保留稿件和历史记录。", "Resets reading appearance, floating position, prompt modes and pace. Scripts and history stay.")
        }
    }
}

private struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss
    private var notices: String {
        ["Oralo-MIT-LICENSE", "CMUDict-LICENSE", "CMUDict-IPA-LICENSE", "IPA-Dict-LICENSE"].compactMap { name in
            Bundle.main.url(forResource: name, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }.joined(separator: "\n\n────────\n\n")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(MacCopy.text("开源许可", "Open-source licenses")).font(.title2.bold()); Spacer(); Button(MacCopy.text("完成", "Done")) { dismiss() }.keyboardShortcut(.cancelAction) }
            ScrollView { Text(notices).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(24).frame(width: 620, height: 560)
    }
}
