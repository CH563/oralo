import SwiftUI
import AppKit

struct FloatingPromptView: View {
    let session: MacSpeechSession
    let windows: PresentationWindows
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var hovering = false
    @State private var errorVisible = false
    private var controlsVisible: Bool { hovering || windows.floatingSettingsVisible || errorVisible || !session.recording || voiceOver }
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 22)
                .fill(MacStyle.canvas(scheme).opacity(reduceTransparency ? 1 : 1 - windows.preferences.transparency))
                .allowsHitTesting(false)
            if !reduceTransparency {
                PanelBackdrop(dark: scheme == .dark)
                    .opacity(1 - windows.preferences.transparency)
                    .allowsHitTesting(false)
            }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    PromptButton(title: MacCopy.text("靠近摄像头", "Move near camera"), symbol: "web.camera", identifier: "floating-near-camera", action: windows.nearCamera)
                        .opacity(controlsVisible ? 1 : 0).allowsHitTesting(controlsVisible).accessibilityHidden(!controlsVisible)
                    Spacer(minLength: 0)
                    PromptStatus(session: session, compact: true)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .overlay { PanelDragHandle() }
                        .help(MacCopy.text("拖动此处移动窗口", "Drag here to move the window"))
                    Spacer(minLength: 0)
                    PromptButton(title: MacCopy.text("调整悬浮窗", "Adjust floating prompt"), symbol: "slider.horizontal.3", identifier: "floating-settings", action: windows.toggleFloatingSettings)
                        .opacity(controlsVisible ? 1 : 0).allowsHitTesting(controlsVisible).accessibilityHidden(!controlsVisible)
                }.buttonStyle(.borderless).padding(.horizontal, 12).padding(.top, 6)
                MacReader(session: session, fontSize: windows.preferences.floatingFontSize, floating: true, dark: scheme == .dark,
                          lineSpacing: windows.preferences.floatingLineSpacing,
                          highlightColor: windows.preferences.floatingHighlight.color(dark: scheme == .dark, custom: windows.preferences.floatingCustomHighlight),
                          alignment: windows.preferences.textAlignment)
                    .scaleEffect(x: windows.preferences.mirror ? -1 : 1, y: 1)
                HStack(spacing: 10) {
                    PromptButton(title: session.busy ? MacCopy.text("暂停收音", "Pause listening") : MacCopy.text("继续收音", "Resume listening"),
                                 symbol: session.busy ? "pause.fill" : "play.fill", identifier: "floating-toggle", action: session.toggle)
                    PromptButton(title: MacCopy.text("从当前句接稿", "Pick up from this sentence"), symbol: "arrow.uturn.backward", identifier: "floating-pick-up", action: session.pickUp)
                    Divider().frame(height: 16)
                    PromptButton(title: MacCopy.text("返回演讲页", "Return to reader"), symbol: "pip.exit", identifier: "return-reader", action: windows.showReader)
                    PromptButton(title: MacCopy.text("结束收音并关闭", "End session and close"), symbol: "xmark", identifier: "floating-end", action: windows.finish)
                    if session.error != nil {
                        PromptButton(title: MacCopy.text("查看收音问题", "Audio needs attention"), symbol: "exclamationmark.triangle", identifier: "floating-audio-issue") { errorVisible.toggle() }
                            .foregroundStyle(.orange)
                            .popover(isPresented: $errorVisible) {
                                if let error = session.error { SpeechErrorView(session: session, error: error).frame(width: 330) }
                            }
                    }
                }
                .buttonStyle(.borderless).frame(height: 36)
                .opacity(controlsVisible ? 1 : 0).allowsHitTesting(controlsVisible).accessibilityHidden(!controlsVisible)
                .padding(.bottom, 6)
            }
            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(width: 28, height: 28).contentShape(.rect)
                .overlay { PanelDragHandle(resize: true) }
                .help(MacCopy.text("拖动角落调整大小", "Drag the corner to resize"))
                .accessibilityLabel(MacCopy.text("调整窗口大小", "Resize window"))
                .accessibilityIdentifier("floating-resize")
        }
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            FloatingHoverRegion { inside in if hovering != inside { hovering = inside } }
        }
        .foregroundStyle(.primary).tint(nil)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: controlsVisible)
        .preferredColorScheme(windows.preferences.colorScheme)
    }
}

/// SwiftUI hover tracking can stop when a nonactivating panel's app is inactive.
/// AppKit activeAlways tracking keeps controls reachable without activating Oralo.
private struct FloatingHoverRegion: NSViewRepresentable {
    let changed: (Bool) -> Void
    func makeNSView(context: Context) -> FloatingTrackingView { FloatingTrackingView(changed: changed) }
    func updateNSView(_ view: FloatingTrackingView, context: Context) { view.changed = changed }
}

private final class FloatingTrackingView: NSView {
    var changed: (Bool) -> Void
    private var tracking: NSTrackingArea?
    init(changed: @escaping (Bool) -> Void) { self.changed = changed; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("Use init(changed:)") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        Task { @MainActor [weak self] in
            guard let self, let window, window.isVisible else { return }
            let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            changed(bounds.contains(point))
        }
    }
    override func mouseEntered(with event: NSEvent) { changed(true) }
    override func mouseMoved(with event: NSEvent) { changed(true) }
    override func mouseExited(with event: NSEvent) { changed(false) }
}

/// The native glass is a background sibling, so its opacity never fades text or controls.
private struct PanelBackdrop: NSViewRepresentable {
    let dark: Bool
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26, *) {
            let view = NSGlassEffectView()
            view.style = .regular; view.cornerRadius = 22
            return view
        }
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow; view.material = .hudWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}

struct FloatingSettings: View {
    let windows: PresentationWindows
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        @Bindable var preferences = windows.preferences
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(MacCopy.text("调整悬浮窗", "Floating controls")).font(.headline)
                Spacer()
                PromptButton(title: MacCopy.text("关闭悬浮设置", "Close floating controls"), symbol: "xmark", identifier: "close-floating-settings", action: windows.hideFloatingSettings)
                    .buttonStyle(.borderless)
            }
            if let session = windows.session { PromptModeControl(preferences: preferences, session: session, floating: true) }
            FloatingPositionControls(windows: windows)
            HStack(spacing: 8) {
                Text(MacCopy.text("尺寸", "Size")).fixedSize()
                Picker(MacCopy.text("窗口尺寸", "Window size"), selection: Binding(get: { windows.sizePreset }, set: { preset in
                    if let preset { windows.resize(preset.size) }
                })) {
                    ForEach(FloatingSizePreset.allCases) { preset in
                        Text(preset.title).tag(Optional(preset)).accessibilityIdentifier("size-\(preset.rawValue)")
                    }
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
                Text("\(Int(windows.floatingFrame.width)) × \(Int(windows.floatingFrame.height))")
                    .monospacedDigit().foregroundStyle(.secondary).font(.caption).fixedSize()
                    .accessibilityIdentifier("floating-dimensions")
            }
            Divider()
            PromptSlider(title: MacCopy.text("背景透明度", "Background transparency"), valueText: "\(Int((preferences.transparency * 100).rounded()))%",
                         value: $preferences.transparency, range: 0...0.8, step: 0.05, identifier: "background-transparency")
                .disabled(reduceTransparency)
                .help(reduceTransparency ? MacCopy.text("系统已开启降低透明度", "Reduce Transparency is enabled in System Settings") : "")
            PromptSlider(title: MacCopy.text("字号", "Text size"), valueText: "\(Int(preferences.floatingFontSize)) pt",
                         value: $preferences.floatingFontSize, range: 18...48, step: 1, identifier: "floating-font-size")
            PromptSlider(title: MacCopy.text("行距", "Line spacing"), valueText: "\(Int(preferences.floatingLineSpacing)) pt",
                         value: $preferences.floatingLineSpacing, range: 0...24, step: 1, identifier: "floating-line-spacing")
            FloatingHighlightPicker(preferences: preferences)
            Divider()
            PromptAppearanceControls(preferences: preferences)
        }.padding(20).frame(width: 340).fixedSize(horizontal: false, vertical: true)
            .oraloGlass().clipShape(.rect(cornerRadius: 20))
            .tint(nil).preferredColorScheme(windows.preferences.colorScheme)
    }
}

private struct FloatingPositionControls: View {
    let windows: PresentationWindows
    var body: some View {
        HStack(spacing: 6) {
            Text(MacCopy.text("位置", "Position"))
            Spacer(minLength: 8)
            positionButton(MacCopy.text("靠近摄像头", "Move near camera"), symbol: "web.camera", identifier: "near-camera", action: windows.nearCamera)
            ForEach(FloatingCorner.allCases) { corner in
                positionButton(corner.title, symbol: corner.symbol, identifier: "position-\(corner.rawValue)") { windows.move(to: corner) }
            }
        }.oraloActionStyle().controlSize(.small)
    }
    private func positionButton(_ title: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(.primary).frame(width: 20, height: 26)
        }.accessibilityLabel(title).accessibilityIdentifier(identifier).help(title)
    }
}
