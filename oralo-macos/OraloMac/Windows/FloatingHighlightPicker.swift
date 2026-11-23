import AppKit
import SwiftUI

/// Both readers share the palette; their text size and spacing remain independent.
struct FloatingHighlightPicker: View {
    @Bindable var preferences: MacPreferences
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(MacCopy.text("高亮色", "Highlight color"))
                Spacer()
                Text(preferences.floatingHighlight.title).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(FloatingHighlight.allCases.filter { $0 != .custom }) { preset in
                    let color = preset.color(dark: scheme == .dark, custom: preferences.floatingCustomHighlight)
                    let selected = preferences.floatingHighlight == preset
                    Button { preferences.floatingHighlight = preset } label: {
                        ZStack {
                            Circle().fill(Color(nsColor: color)).frame(width: 24, height: 24)
                            if selected {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(swatchForeground(color))
                            }
                            selectionRing(selected)
                        }.frame(maxWidth: .infinity, minHeight: 34).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(preset.title).accessibilityLabel(preset.title)
                    .accessibilityValue(selected ? MacCopy.text("已选中", "Selected") : "")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("highlight-\(preset.rawValue)")
                }
                ZStack {
                    CustomHighlightWell(color: Binding(get: { preferences.floatingCustomHighlight }, set: {
                        preferences.floatingCustomHighlight = $0
                        preferences.floatingHighlight = .custom
                    }), mode: $preferences.colorPanelMode).frame(width: 24, height: 24).clipShape(.circle)
                    Image(systemName: "paintpalette.fill").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(swatchForeground(preferences.floatingCustomHighlight.nsColor))
                        .allowsHitTesting(false).accessibilityHidden(true)
                    selectionRing(preferences.floatingHighlight == .custom).allowsHitTesting(false)
                }.frame(maxWidth: .infinity, minHeight: 34)
            }
        }
    }
    private func selectionRing(_ selected: Bool) -> some View {
        Circle().strokeBorder(selected ? Color.primary.opacity(0.65) : .clear, lineWidth: 1.5)
            .frame(width: 32, height: 32).accessibilityHidden(true)
    }
    private func swatchForeground(_ color: NSColor) -> Color {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent > 0.6 ? .black : .white
    }
}

/// Keep Apple's color controls in a panel created as nonactivating. The default
/// minimal-well popover activates the owning app when a color is selected.
struct CustomHighlightWell: NSViewRepresentable {
    @Binding var color: HighlightColor
    @Binding var mode: Int
    func makeCoordinator() -> Coordinator { Coordinator(color: $color, mode: $mode) }
    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(style: .minimal)
        well.supportsAlpha = false
        well.color = color.nsColor
        well.target = context.coordinator
        well.action = #selector(Coordinator.changedWell(_:))
        well.pulldownTarget = context.coordinator
        well.pulldownAction = #selector(Coordinator.openPalette(_:))
        well.setAccessibilityIdentifier("highlight-custom")
        well.setAccessibilityLabel(MacCopy.text("自定义高亮色", "Custom highlight color"))
        well.toolTip = MacCopy.text("自定义高亮色", "Custom highlight color")
        return well
    }
    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.color = $color
        context.coordinator.mode = $mode
        if HighlightColor(nsColor: well.color) != color { well.color = color.nsColor }
        well.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        context.coordinator.updatePalette(color, appearance: well.effectiveAppearance)
        well.setAccessibilityValue(color.hex)
    }
    static func dismantleNSView(_ well: NSColorWell, coordinator: Coordinator) {
        coordinator.closePalette()
        well.target = nil; well.pulldownTarget = nil
    }
    final class Coordinator: NSObject, NSWindowDelegate {
        var color: Binding<HighlightColor>
        var mode: Binding<Int>
        private var palette: NSColorPanel?
        init(color: Binding<HighlightColor>, mode: Binding<Int>) { self.color = color; self.mode = mode }
        @objc func changedWell(_ sender: NSColorWell) { accept(sender.color) }
        @objc private func changedPalette(_ sender: NSColorPanel) { accept(sender.color) }
        private func accept(_ value: NSColor) {
            guard let value = HighlightColor(nsColor: value) else { return }
            color.wrappedValue = value
        }
        func updatePalette(_ value: HighlightColor, appearance: NSAppearance) {
            guard let palette else { return }
            palette.appearance = appearance
            if HighlightColor(nsColor: palette.color) != value {
                let selectedMode = palette.mode
                palette.color = value.nsColor
                palette.mode = selectedMode
            }
        }
        @objc func openPalette(_ sender: NSColorWell) {
            if palette != nil { closePalette(); return }
            guard let owner = sender.window, let screen = owner.screen ?? NSScreen.main else { return }
            let panel = NSColorPanel(contentRect: CGRect(x: 0, y: 0, width: 280, height: 340),
                styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = MacCopy.text("高亮色", "Highlight color")
            panel.appearance = sender.effectiveAppearance
            panel.identifier = NSUserInterfaceItemIdentifier("highlight-color-panel")
            panel.setAccessibilityIdentifier("highlight-color-panel")
            panel.showsAlpha = false; panel.isContinuous = true
            // Setting an RGB color can switch AppKit's picker mode. Restore the
            // user's tab after assigning the color, including grayscale mode.
            panel.color = color.wrappedValue.nsColor
            panel.mode = NSColorPanel.Mode(rawValue: mode.wrappedValue) ?? .wheel
            panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
            panel.delegate = self
            panel.setTarget(self); panel.setAction(#selector(changedPalette(_:)))
            panel.setFrame(FloatingGeometry.settingsFrame(beside: owner.frame, visible: screen.visibleFrame, contentSize: panel.frame.size), display: false)
            palette = panel
            owner.addChildWindow(panel, ordered: .above)
            panel.orderFrontRegardless()
        }
        func closePalette() {
            guard let panel = palette else { return }
            saveMode(panel)
            palette = nil
            panel.parent?.removeChildWindow(panel)
            panel.delegate = nil; panel.setTarget(nil)
            panel.close()
        }
        private func saveMode(_ panel: NSColorPanel) {
            let value = panel.mode.rawValue
            if (0...7).contains(value), mode.wrappedValue != value { mode.wrappedValue = value }
        }
        func windowWillClose(_ notification: Notification) {
            guard let panel = notification.object as? NSColorPanel, panel === palette else { return }
            saveMode(panel)
            panel.parent?.removeChildWindow(panel)
            panel.setTarget(nil); palette = nil
        }
    }
}
