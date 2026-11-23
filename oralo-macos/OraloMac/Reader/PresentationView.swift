import SwiftUI

struct PresentationView: View {
    let session: MacSpeechSession
    let windows: PresentationWindows
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var controls = true
    @State private var settings = false
    @State private var overControls = false
    @State private var hideTask: Task<Void, Never>?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MacStyle.canvas(scheme).ignoresSafeArea()
                MacReader(session: session, fontSize: windows.preferences.fontSize, floating: false, dark: scheme == .dark,
                          lineSpacing: windows.preferences.lineSpacing,
                          highlightColor: windows.preferences.floatingHighlight.color(dark: scheme == .dark, custom: windows.preferences.floatingCustomHighlight),
                          alignment: windows.preferences.textAlignment)
                    .scaleEffect(x: windows.preferences.mirror ? -1 : 1, y: 1)
                    .padding(.top, 28)
                VStack {
                    PromptGlassGroup {
                        HStack(alignment: .top) {
                            PromptButton(title: MacCopy.text("结束演讲", "End presentation"), symbol: "chevron.down", identifier: "reader-end", action: windows.finish)
                                .oraloActionStyle().buttonBorderShape(.circle)
                            Spacer(minLength: 16)
                            PromptStatus(session: session).padding(.horizontal, 16).padding(.vertical, 8)
                                .promptControlSurface()
                            Spacer(minLength: 16)
                            PromptButton(title: controls ? MacCopy.text("隐藏操作", "Hide controls") : MacCopy.text("显示操作", "Show controls"),
                                symbol: controls ? "eye.slash" : "eye", identifier: "reader-controls") {
                                hideTask?.cancel(); controls.toggle()
                            }.oraloActionStyle().buttonBorderShape(.circle)
                        }
                    }
                    Spacer()
                    if let error = session.error { SpeechErrorView(session: session, error: error) }
                    ReaderToolbar(session: session, windows: windows, compact: geometry.size.width < 760, settings: $settings)
                        .opacity(controls ? 1 : 0)
                        .allowsHitTesting(controls)
                        .accessibilityHidden(!controls)
                        .onHover { inside in overControls = inside; if !inside { scheduleHide() } }
                }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
            }
        }
        .preferredColorScheme(windows.preferences.colorScheme)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: controls)
        .onContinuousHover { phase in if case .active = phase { reveal() } }
        .onAppear { scheduleHide() }
        .onChange(of: session.busy) { reveal() }
        .onChange(of: settings) { reveal() }
        .onDisappear { hideTask?.cancel() }
    }
    private func reveal() { controls = true; scheduleHide() }
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            if !overControls && !settings && !voiceOver && session.error == nil && (session.recording || session.playing) { controls = false }
        }
    }
}

private struct ReaderToolbar: View {
    let session: MacSpeechSession
    let windows: PresentationWindows
    let compact: Bool
    @Binding var settings: Bool
    var body: some View {
        PromptGlassGroup {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    PromptButton(title: MacCopy.text("上一句", "Back"), symbol: "backward.end", identifier: "reader-back", showsTitle: !compact) {
                        session.select(index: session.currentIndex - 1, reason: .previous)
                    }.disabled(session.currentIndex == 0).keyboardShortcut(.leftArrow, modifiers: [])
                    PromptButton(title: session.busy ? MacCopy.text("暂停", "Pause") : MacCopy.text("继续", "Resume"),
                                 symbol: session.busy ? "pause.fill" : "play.fill", identifier: "reader-toggle", showsTitle: !compact, action: session.toggle)
                        .keyboardShortcut(.space, modifiers: [])
                    PromptButton(title: MacCopy.text("下一句", "Next"), symbol: "forward.end", identifier: "reader-next", showsTitle: !compact) {
                        session.select(index: session.currentIndex + 1, reason: .next)
                    }.disabled(session.currentIndex + 1 == session.snapshot.cues.count).keyboardShortcut(.rightArrow, modifiers: [])
                }.buttonStyle(.borderless).padding(8).promptControlSurface()
                PromptButton(title: MacCopy.text("接稿", "Pick up"), symbol: "arrow.uturn.backward", identifier: "reader-pick-up", showsTitle: true, action: session.pickUp)
                    .oraloActionStyle().controlSize(.large)
                HStack(spacing: 4) {
                    PromptButton(title: MacCopy.text("悬浮提词", "Floating prompt"), symbol: "pip.enter", identifier: "show-floating", action: windows.showFloating)
                    PromptButton(title: MacCopy.text("切换全屏", "Toggle full screen"), symbol: "arrow.up.left.and.arrow.down.right", identifier: "reader-fullscreen", action: windows.toggleFullScreen)
                    PromptButton(title: MacCopy.text("阅读设置", "Reading settings"), symbol: "slider.horizontal.3", identifier: "reader-settings") { settings.toggle() }
                        .popover(isPresented: $settings) { ReadingSettings(preferences: windows.preferences, session: session) }
                }.buttonStyle(.borderless).padding(8).promptControlSurface()
            }.foregroundStyle(.primary)
        }
    }
}

struct SpeechErrorView: View {
    let session: MacSpeechSession
    let error: String
    var body: some View {
        VStack(spacing: 8) {
            Text(error).font(.callout).textSelection(.enabled)
            if session.needsModel {
                Button(MacCopy.text("下载模型并继续", "Download model and resume")) { session.start(downloadModels: true) }
                    .oraloActionStyle()
            }
            Text(MacCopy.text("位置已保留，仍可手动选句。", "Your position is held. Manual selection remains available.")).font(.caption).foregroundStyle(.secondary)
        }.padding(14).frame(maxWidth: 600).background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}

struct ReadingSettings: View {
    @Bindable var preferences: MacPreferences
    @Bindable var session: MacSpeechSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(MacCopy.text("阅读设置", "Reading settings")).font(.headline)
                Spacer()
                PromptButton(title: MacCopy.text("关闭阅读设置", "Close reading settings"), symbol: "xmark", identifier: "close-reading-settings") { dismiss() }
                    .buttonStyle(.borderless)
            }
            PromptModeControl(preferences: preferences, session: session)
            PromptSlider(title: MacCopy.text("字号", "Text size"), valueText: "\(Int(preferences.fontSize)) pt", value: $preferences.fontSize,
                         range: 24...72, step: 2, identifier: "reader-font-size")
            PromptSlider(title: MacCopy.text("行距", "Line spacing"), valueText: "\(Int(preferences.lineSpacing)) pt", value: $preferences.lineSpacing,
                         range: 0...24, step: 1, identifier: "reader-line-spacing")
            FloatingHighlightPicker(preferences: preferences)
            Divider()
            PromptAppearanceControls(preferences: preferences)
            Divider()
            Toggle(MacCopy.text("兼容识别模式", "Compatibility recognition"), isOn: Binding(get: { session.compatibility }, set: {
                preferences.compatibility = $0
                session.compatibility = $0
            })).disabled(session.busy).accessibilityIdentifier("compatibility-recognition")
                .help(MacCopy.text("暂停后可切换识别模式", "Pause listening to change recognition mode"))
        }.padding(20).frame(width: 340).tint(nil)
            .preferredColorScheme(preferences.colorScheme)
    }
}

struct PromptAppearanceControls: View {
    @Bindable var preferences: MacPreferences
    var body: some View {
        HStack {
            ThemePicker(preferences: preferences).fixedSize()
            Spacer(minLength: 8)
            Toggle(MacCopy.text("镜像", "Mirror"), isOn: $preferences.mirror).fixedSize()
                .accessibilityLabel(MacCopy.text("水平镜像", "Mirror text")).accessibilityIdentifier("mirror-text")
        }.controlSize(.small)
    }
}

struct ThemePicker: View {
    @Bindable var preferences: MacPreferences
    var body: some View {
        Picker(MacCopy.text("外观", "Appearance"), selection: $preferences.theme) {
            Text(MacCopy.text("跟随系统", "System")).tag(MacPreferences.Theme.system)
            Text(MacCopy.text("浅色", "Light")).tag(MacPreferences.Theme.light)
            Text(MacCopy.text("深色", "Dark")).tag(MacPreferences.Theme.dark)
        }.accessibilityIdentifier("theme-picker")
    }
}
