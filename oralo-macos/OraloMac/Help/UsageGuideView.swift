import SwiftUI

/// Local, read-only guidance. Opening it never changes capture, cue position or preferences.
struct UsageGuideButton: View {
    @Environment(\.openWindow) private var openWindow
    var compact = true
    var body: some View {
        Button { openWindow(id: "usage-guide") } label: {
            if compact {
                Image(systemName: "lightbulb")
            } else {
                Label(MacCopy.text("使用指南", "How to use Oralo"), systemImage: "lightbulb")
            }
        }
        .help(MacCopy.text("使用指南与会议技巧", "Getting started and meeting tips"))
        .accessibilityLabel(MacCopy.text("使用指南与会议技巧", "Getting started and meeting tips"))
        .accessibilityIdentifier("open-usage-guide")
    }
}

struct UsageGuideCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(MacCopy.text("Oralo 使用指南", "Oralo User Guide"), systemImage: "lightbulb") {
                openWindow(id: "usage-guide")
            }.keyboardShortcut("?", modifiers: .command)
        }
    }
}

struct UsageGuideView: View {
    let preferences: MacPreferences
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.colorScheme) private var scheme
    @State private var page = Page.basics
    private enum Page: String, CaseIterable, Identifiable {
        case basics, meetings
        var id: Self { self }
        var title: String {
            switch self {
            case .basics: MacCopy.text("快速上手", "Getting started")
            case .meetings: MacCopy.text("视频会议与投屏", "Meetings & sharing")
            }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb").font(.system(size: 24, weight: .medium))
                        .foregroundStyle(MacStyle.accent).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(MacCopy.text("自然地讲，从容地分享。", "Speak naturally. Share confidently."))
                            .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        Text(MacCopy.text("让 Oralo 留住你的下一句。", "Keep your next line close."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Picker(MacCopy.text("指南内容", "Guide topic"), selection: $page) {
                    ForEach(Page.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("guide-topic")
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if page == .basics { basics } else { meetings }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.id(page).accessibilityIdentifier("guide-content")
            Divider()
            HStack {
                Text(MacCopy.text("随时从顶部灯泡或「帮助」菜单打开。", "Reopen from the lightbulb or the Help menu."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 20)
                Button(MacCopy.text("完成", "Done")) { dismissWindow(id: "usage-guide") }
                    .keyboardShortcut(.cancelAction).fixedSize().accessibilityIdentifier("close-usage-guide")
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(minWidth: 580, idealWidth: 660, minHeight: 520, idealHeight: 660)
        .background(MacStyle.canvas(scheme))
        .preferredColorScheme(preferences.colorScheme)
        .oraloActionStyle()
    }
    private var basics: some View {
        VStack(alignment: .leading, spacing: 24) {
            GuideStep(number: 1, title: MacCopy.text("准备你的讲稿", "Prepare your script"),
                detail: MacCopy.text("新建、导入 TXT / Markdown，或用示例稿开始。选中词语后，右键添加拼音或英文音标，并试听原词。", "Create a script, import TXT / Markdown, or try a sample. Select a word and right-click to add pinyin or IPA and hear its pronunciation."))
            GuideStep(number: 2, title: MacCopy.text("选好开讲方式", "Choose how to prompt"),
                detail: MacCopy.text("点「开讲」检查语言、语音模型和麦克风。语音模式跟随你的节奏；手动或定速模式无需开麦。", "Choose Start speaking to check the language, speech model and microphone. Voice mode follows your pace; Manual and Paced keep the microphone off."))
            GuideStep(number: 3, title: MacCopy.text("自由发挥，也能接回", "Go off script. Find your place."),
                detail: MacCopy.text("顺着高亮自然地讲。临场发挥后，继续读稿件中的内容；需要手动定位时，点击对应句子，或用「接稿」从当前句重新开始。", "Speak along with the highlight. After an aside, continue with your script. To choose a place yourself, click a sentence or use Pick up to restart the current cue."))
            GuideStep(number: 4, title: MacCopy.text("排练一次，更有底气", "Rehearse for confidence"),
                detail: MacCopy.text("从「讲稿工具」开始排练。结束后查看用时和复盘线索，回到原句修改，或检查是否需要注音。", "Start a rehearsal from Script tools. Review timing and cues afterward, return to a passage to edit, or check whether it needs a pronunciation hint."))
            Divider()
            HStack(spacing: 20) {
                shortcut("Space", MacCopy.text("演讲暂停 / 继续", "Pause / resume in reader"))
                shortcut("←  →", MacCopy.text("上一句 / 下一句", "Previous / next cue"))
                shortcut("⌘ ,", MacCopy.text("设置", "Settings"))
            }
            Button {
                page = .meetings
            } label: {
                Label(MacCopy.text("看看视频会议怎么用", "Using Oralo in a video call"), systemImage: "arrow.right")
            }.controlSize(.large)
        }
    }
    private var meetings: some View {
        VStack(alignment: .leading, spacing: 22) {
            GuideStep(number: 1, title: MacCopy.text("把提词放在摄像头附近", "Keep the prompt near your camera"),
                detail: MacCopy.text("加入腾讯会议、钉钉等会议后，在 Oralo 选择「悬浮开讲」。点摄像头图标靠近镜头，调好窗口尺寸、字号和背景透明度。", "Join your call, then choose Float near camera in Oralo. Use the camera button to position the prompt, and adjust its size, text and background transparency."))
            GuideStep(number: 2, title: MacCopy.text("共享要展示的应用窗口", "Share the window you want to present"),
                detail: MacCopy.text("在会议软件的「共享屏幕」或「投屏」中，选择「窗口 / 应用窗口」，再选具体的 PPT、Keynote 或浏览器窗口。保留 Oralo 在你自己的屏幕上。", "In your meeting app’s Share screen or Cast dialog, choose Window / App window, then your PowerPoint, Keynote or browser window. Keep Oralo on your own display."))
            DingTalkSharingExample()
            GuideStep(number: 3, title: MacCopy.text("确认对方看到的画面", "Check what your audience sees"),
                detail: MacCopy.text("开始共享后检查预览，或用另一台设备确认只有演示内容。PPT 放映可能打开新窗口，切换后再确认共享的是放映窗口。", "Check the sharing preview or another device to confirm it shows only your presentation. A slideshow may open a new window; confirm that this is the window being shared."))
            GuideStep(number: 4, title: MacCopy.text("确认声音，再自然地讲", "Check your audio, then speak naturally"),
                detail: MacCopy.text("语音跟随时保留 Oralo 的麦克风权限，并确认会议里已解除静音。先说一句，请对方确认人声；若收音不可用，可切换手动或定速继续提词。", "For voice following, allow Oralo’s microphone access and unmute yourself in the meeting. Say a sentence and confirm the other person can hear you. If capture is unavailable, continue in Manual or Paced mode."))
            sharingNote
            DisclosureGroup(MacCopy.text("腾讯会议的小提示", "A tip for Tencent Meeting")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(MacCopy.text("「视频流畅度优先」会关闭应用窗口过滤。需要让提词留在自己屏幕时，关闭此选项，并重新检查共享预览。", "“Prioritize video smoothness” turns off app-window filtering. Turn it off when keeping your prompt private, then check the sharing preview again."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Link(MacCopy.text("腾讯会议官方共享说明 ↗", "Tencent Meeting’s sharing guide ↗"), destination: URL(string: "https://meeting.tencent.com/support/topic/374/index.html")!)
                        .font(.callout)
                }.padding(.top, 10)
            }
        }
    }
    private var sharingNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.on.rectangle").font(.title3).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(MacCopy.text("共享范围决定别人能看到什么", "What you share determines what others see")).font(.headline)
                Text(MacCopy.text("共享整个桌面或做屏幕镜像时，提词窗可能一起可见。透明度只改变本机阅读效果，不会自动隐藏共享中的提词。投屏也请选「应用窗口」，并以实际预览为准。", "Sharing the whole desktop or mirroring your display can include the prompt. Transparency changes its appearance, not its capture visibility. For casting too, choose App window and check the actual preview."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 16))
    }
    private func shortcut(_ keys: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(keys).font(.system(.callout, design: .monospaced).weight(.medium))
            Text(title).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GuideStep: View {
    let number: Int
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number, format: .number).font(.callout.weight(.semibold)).monospacedDigit()
                .frame(width: 28, height: 28).background(.quaternary.opacity(0.55), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A vector example derived from the supplied casting choices, not a captured desktop.
private struct DingTalkSharingExample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(MacCopy.text("钉钉投屏示例", "DingTalk casting example")).font(.subheadline.weight(.semibold))
            HStack(alignment: .top, spacing: 10) {
                choice(MacCopy.text("扩展屏", "Extended display"), symbol: "display.2", selected: false)
                choice(MacCopy.text("桌面", "Desktop"), symbol: "desktopcomputer", selected: false)
                choice(MacCopy.text("应用窗口", "App window"), symbol: "macwindow.on.rectangle", selected: true)
            }
            HStack(spacing: 10) {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(MacStyle.accent).accessibilityHidden(true)
                Text(MacCopy.text("选择要分享的 PPT 或浏览器 → 开始投屏", "Choose your slides or browser → Start casting"))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(16).background(.background.opacity(0.6), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.07)) }
    }
    private func choice(_ title: String, symbol: String, selected: Bool) -> some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(MacStyle.accent).opacity(selected ? 1 : 0)
            }.font(.caption).accessibilityHidden(true)
            Image(systemName: symbol).font(.system(size: 25, weight: .regular)).accessibilityHidden(true)
            Text(title).font(.callout.weight(selected ? .semibold : .regular)).multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity).padding(12)
            .background(selected ? MacStyle.accent.opacity(0.09) : Color.primary.opacity(0.03), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? MacStyle.accent.opacity(0.65) : Color.clear, lineWidth: 1.5) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(selected ? MacCopy.text("推荐的投屏范围", "Recommended casting scope") : MacCopy.text("投屏选项示意", "Example casting option"))
    }
}
