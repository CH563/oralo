import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class PresentationWindows: NSObject, NSWindowDelegate {
    var onFinished: ((RehearsalRecorder) -> Void)?
    private(set) var closingTask: Task<Void, Never>?
    private(set) var lastRecorder: RehearsalRecorder?
    private(set) var session: MacSpeechSession?
    private(set) var floatingVisible = false
    private(set) var floatingSettingsVisible = false
    let preferences: MacPreferences
    private(set) var floatingFrame = CGRect(origin: .zero, size: FloatingGeometry.standard)
    var sizePreset: FloatingSizePreset? {
        FloatingSizePreset.allCases.first { abs($0.size.width - floatingFrame.width) < 1 && abs($0.size.height - floatingFrame.height) < 1 }
    }
    @ObservationIgnored private var readerWindow: NSWindow?
    @ObservationIgnored private var panel: PromptPanel?
    @ObservationIgnored private var settingsPanel: PromptPanel?
    @ObservationIgnored private var switching = false
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    init(preferences: MacPreferences) {
        self.preferences = preferences
        super.init()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.keepVisible() }
            }
    }
    func begin(_ session: MacSpeechSession, floating: Bool) {
        guard self.session == nil, closingTask == nil else { return }
        self.session = session
        session.compatibility = preferences.compatibility
        if floating { showFloating() } else { showReader() }
        session.start()
    }
    func showReader() {
        guard let session else { return }
        hideFloatingSettings()
        switching = true; panel?.orderOut(nil); floatingVisible = false; switching = false
        if readerWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1040, height: 720),
                styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = session.snapshot.title
            window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false; window.delegate = self
            window.minSize = CGSize(width: 600, height: 420)
            window.identifier = NSUserInterfaceItemIdentifier("presentation-window")
            window.setAccessibilityIdentifier("presentation-window")
            window.contentView = NSHostingView(rootView: PresentationView(session: session, windows: self))
            window.center(); readerWindow = window
        }
        readerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func showFloating() {
        guard let session else { return }
        switching = true; readerWindow?.orderOut(nil); switching = false
        if panel == nil {
            let window = PromptPanel(contentRect: CGRect(origin: .zero, size: FloatingGeometry.standard),
                styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = MacCopy.text("Oralo 悬浮提词", "Oralo floating prompt")
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
            window.level = .floating; window.isFloatingPanel = true; window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = true; window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
            window.minSize = FloatingGeometry.minimum
            window.delegate = self
            window.identifier = NSUserInterfaceItemIdentifier("floating-window")
            window.setAccessibilityIdentifier("floating-window")
            window.contentView = NSHostingView(rootView: FloatingPromptView(session: session, windows: self))
            panel = window
            if let screen = readerWindow?.screen ?? NSScreen.main {
                let saved = preferences.defaults.string(forKey: "mac.floatingFrame").map(NSRectFromString)
                let frame = saved.flatMap { $0.width.isFinite && $0.height.isFinite && $0.origin.x.isFinite && $0.origin.y.isFinite ? $0 : nil }
                window.setFrame(frame.map { FloatingGeometry.clamp($0, to: screen.visibleFrame) }
                    ?? FloatingGeometry.nearCamera(size: FloatingGeometry.standard, visible: screen.visibleFrame, displayCenterX: screen.frame.midX), display: true)
            }
        }
        saveFrame()
        panel?.orderFrontRegardless(); floatingVisible = true
    }
    func toggleFloatingSettings() {
        if floatingSettingsVisible { hideFloatingSettings(); return }
        guard let panel else { return }
        // SwiftUI's ordinary popover activates the owning app when its controls
        // are clicked. Keep these controls in a nonactivating AppKit panel too.
        let window = PromptPanel(contentRect: CGRect(x: 0, y: 0, width: 340, height: 454),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.level = .floating; window.isFloatingPanel = true; window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true; window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
        window.identifier = NSUserInterfaceItemIdentifier("floating-settings-window")
        window.setAccessibilityIdentifier("floating-settings-window")
        window.delegate = self
        let host = NSHostingView(rootView: FloatingSettings(windows: self))
        window.contentView = host
        settingsPanel = window; floatingSettingsVisible = true
        positionFloatingSettings()
        panel.addChildWindow(window, ordered: .above)
        window.orderFrontRegardless()
    }
    func hideFloatingSettings() {
        guard let window = settingsPanel else { return }
        settingsPanel = nil; floatingSettingsVisible = false
        panel?.removeChildWindow(window)
        window.close()
    }
    private func positionFloatingSettings() {
        guard let panel, let window = settingsPanel, let screen = panel.screen ?? NSScreen.main else { return }
        window.setFrame(FloatingGeometry.settingsFrame(beside: panel.frame, visible: screen.visibleFrame, contentSize: window.contentView?.fittingSize ?? CGSize(width: 340, height: 454)), display: true)
    }
    func nearCamera() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        panel.setFrame(FloatingGeometry.nearCamera(size: panel.frame.size, visible: screen.visibleFrame, displayCenterX: screen.frame.midX), display: true)
        saveFrame()
    }
    func move(to corner: FloatingCorner) {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        panel.setFrame(FloatingGeometry.corner(corner, size: panel.frame.size, visible: screen.visibleFrame), display: true)
        saveFrame()
    }
    func resize(_ size: CGSize) {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        panel.setFrame(FloatingGeometry.resize(panel.frame, size: size, visible: screen.visibleFrame), display: true)
        saveFrame()
    }
    func keepVisible() {
        guard let panel, let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) }) ?? NSScreen.main else { return }
        panel.setFrame(FloatingGeometry.clamp(panel.frame, to: screen.visibleFrame), display: true)
        saveFrame()
    }
    func toggleFullScreen() { readerWindow?.toggleFullScreen(nil) }
    func discardFinishedRecorder() { if session == nil, closingTask == nil { lastRecorder = nil } }
    func finish() { end(completed: true, review: true) }
    func end(completed: Bool, review: Bool) {
        guard let ending = session else { return }
        ending.end(); session = nil
        if let recorder = ending.recorder {
            lastRecorder = recorder
            closingTask = Task { [weak self] in
                await recorder.finish(completed: completed)
                self?.closingTask = nil
                if review { self?.onFinished?(recorder) }
            }
        }
        switching = true
        hideFloatingSettings()
        readerWindow?.close(); readerWindow = nil
        panel?.close(); panel = nil
        switching = false; floatingVisible = false
    }
    func windowWillClose(_ notification: Notification) {
        guard !switching else { return }
        if let closing = notification.object as? NSWindow {
            if closing === settingsPanel {
                panel?.removeChildWindow(closing)
                settingsPanel = nil; floatingSettingsVisible = false
                return
            }
            guard closing === readerWindow || closing === panel else { return }
            if closing === readerWindow { readerWindow = nil }
            if closing === panel { panel = nil }
        }
        end(completed: false, review: true)
    }
    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        saveFrame(); positionFloatingSettings()
    }
    func windowDidResize(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        saveFrame(); positionFloatingSettings()
    }
    private func saveFrame() {
        if let panel {
            if floatingFrame != panel.frame { floatingFrame = panel.frame }
            preferences.defaults.set(NSStringFromRect(panel.frame), forKey: "mac.floatingFrame")
        }
    }
}

final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) {
        if identifier?.rawValue == "floating-settings-window" { close() }
    }
}

struct PanelDragHandle: NSViewRepresentable {
    var resize = false
    func makeNSView(context: Context) -> DragHandle { DragHandle(resize: resize) }
    func updateNSView(_ nsView: DragHandle, context: Context) {}
}

final class DragHandle: NSView {
    let resize: Bool
    private var startFrame = CGRect.zero
    private var startMouse = CGPoint.zero
    init(resize: Bool) { self.resize = resize; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("Use init(resize:)") }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: resize ? .frameResize(position: .bottomRight, directions: .all) : .openHand)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if resize { startFrame = window.frame; startMouse = NSEvent.mouseLocation }
        else { window.performDrag(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard resize, let window, let screen = window.screen else { return }
        let location = NSEvent.mouseLocation
        let size = CGSize(width: max(FloatingGeometry.minimum.width, startFrame.width + location.x - startMouse.x),
                          height: max(FloatingGeometry.minimum.height, startFrame.height - location.y + startMouse.y))
        window.setFrame(FloatingGeometry.clamp(CGRect(x: startFrame.minX, y: startFrame.maxY - size.height,
            width: size.width, height: size.height), to: screen.visibleFrame), display: true)
    }
}
