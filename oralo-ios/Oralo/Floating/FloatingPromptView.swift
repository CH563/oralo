import AVFoundation
import OraloCore
import SwiftUI

struct FloatingPromptView: View {
    @Bindable var controller: FloatingPromptController
    @Environment(\.dismiss) private var dismiss
    @State private var choosingPassage = false
    private func t(_ zh: String, _ en: String) -> String { AppCopy.bilingual(zh, en) }
    private var currentPassage: String {
        guard let document = controller.document else { return "" }
        return document.segmentSpans().last(where: { $0.1.location <= controller.offset })
            .flatMap { pair in document.segments.first { $0.id == pair.0 }?.text } ?? document.segments.first?.text ?? ""
    }
    private var status: String {
        if let seconds = controller.countdown { return t("\(seconds) 秒后开始", "Starting in \(seconds)…") }
        if controller.mode == .voice, [.ready, .floating, .unavailable].contains(controller.state) {
            return controller.voiceStatusText
        }
        return switch controller.state {
        case .idle: t("请重新选择讲稿", "Choose a script again")
        case .ready: controller.hasEnded ? t("已读到末尾", "End of script") : (controller.isPlaying ? t("定速预览中", "Previewing at a fixed pace") : t("已暂停 · 定速提词", "Paused · Fixed pace"))
        case .stopping: t("正在关闭小窗…", "Closing Picture in Picture…")
        case .starting: t("正在开启小窗…", "Opening Picture in Picture…")
        case .floating: controller.isPlaying ? t("小窗定速滚动中", "Floating prompt is scrolling") : t("小窗已暂停", "Floating prompt is paused")
        case .unavailable: t("当前设备环境不支持画中画", "Picture in Picture is unavailable here")
        case .failed: t("小窗暂未开启", "Picture in Picture did not open")
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(t("把下一句，留在眼前。", "Keep your next line in sight."))
                        .font(.title2.bold())
                    Text(t("切到其他 App，下一句也在眼前。语音跟随按你的节奏，定速滚动无需麦克风。", "Keep your next line visible in other apps. Follow your voice, or scroll at a fixed pace without the microphone."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker(t("提词方式", "Prompting mode"), selection: Binding(get: { controller.mode }, set: controller.setMode)) {
                        Text(t("定速滚动", "Fixed pace")).tag(FloatingPromptController.Mode.fixed)
                        Text(t("语音跟随", "Voice follow")).tag(FloatingPromptController.Mode.voice)
                    }.pickerStyle(.segmented).disabled(controller.isOpen).accessibilityIdentifier("floating-mode")
                    FloatingPreview(controller: controller)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 20))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(t("小窗稿件预览", "Floating script preview"))
                        .accessibilityValue(currentPassage)
                        .accessibilityIdentifier("floating-preview")
                    Label(status, systemImage: controller.isOpen ? "pip" : "pause.circle")
                        .font(.subheadline).foregroundStyle(OraloStyle.readingAccent)
                        .accessibilityIdentifier("floating-status")
                    if let message = controller.message {
                        Text(message).font(.footnote).foregroundStyle(.orange).accessibilityIdentifier("floating-error")
                    }
                    if controller.mode == .voice {
                        Text(t("先开启收音，再切换 App。其他 App 录像或通话可能中断收音，届时会保留原句。", "Start listening before switching apps. Another app’s recording or call may interrupt the microphone; your place will be held."))
                            .font(.footnote).foregroundStyle(.secondary)
                        if !controller.isOpen, controller.voiceState == .unavailable {
                            if controller.needsModel {
                                Button(t("下载语音模型并重试", "Download speech model and retry")) { controller.retryVoice(downloadModels: true) }
                            } else if !controller.useCompatibility {
                                Button(t("使用兼容识别重试", "Retry with compatibility recognition")) { controller.retryVoice(compatibility: true) }
                            }
                        }
                    }
                    if controller.versionChanged {
                        Text(t("讲稿已修改，请重新选择起点。", "This script changed. Choose where to begin again."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { previewControls(singleLine: true) }
                        VStack(alignment: .leading, spacing: 12) { previewControls(singleLine: false) }
                    }.buttonStyle(.bordered).font(.subheadline).frame(minHeight: 44)
                    VStack(alignment: .leading, spacing: 14) {
                        if controller.mode == .fixed {
                        LabeledContent(t("滚动速度", "Scrolling speed"), value: controller.speed.formatted(.number.precision(.fractionLength(1))) + "×")
                        Slider(value: Binding(get: { controller.speed }, set: controller.setSpeed), in: 0.5...2, step: 0.1) {
                            Text(t("滚动速度", "Scrolling speed"))
                        }.accessibilityIdentifier("floating-speed")
                        }
                        LabeledContent(t("文字大小", "Text size"), value: (controller.scale * 100).formatted(.number.precision(.fractionLength(0))) + "%")
                        Slider(value: Binding(get: { controller.scale }, set: controller.setScale), in: 0.8...1.4, step: 0.1) {
                            Text(t("文字大小", "Text size"))
                        }.accessibilityIdentifier("floating-font-size")
                    }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                    Text(controller.mode == .voice
                         ? t("语音准备好后开启小窗，返回这里会暂停。若相机将小窗收至侧边，点箭头展开。可双指缩放。", "The window opens when speech is ready. Return here to pause. If Camera stashes it, tap the edge arrow to restore it. Pinch to resize.")
                         : t("开启后倒数 3 秒开始滚动，返回这里会暂停。若相机将小窗收至侧边，点箭头展开。可双指缩放小窗。", "Scrolling starts after a 3-second countdown. Return here to pause. If Camera stashes the window, tap the edge arrow to restore it. Pinch to resize."))
                        .font(.footnote).foregroundStyle(.secondary)
                    if controller.supported {
                        SessionPrimary(title: controller.isOpen ? t("关闭小窗", "Close floating window") : controller.voiceState == .preparing ? t("取消准备", "Cancel preparation") : t("开启小窗", "Open floating window"),
                                       symbol: "pip", id: "floating-start") {
                            if controller.isOpen { controller.closeWindow() }
                            else if controller.voiceState == .preparing { controller.pause() }
                            else { controller.startPictureInPicture() }
                        }.disabled((controller.state == .starting || controller.state == .stopping) || controller.document == nil || controller.hasEnded)
                    } else {
                        Text(t("仍可在这里预览，或返回备稿使用全屏提词。", "You can preview here or return to your script for full-screen prompting."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    DisclosureGroup(t("小窗诊断", "Window diagnostics")) {
                        Text(t("仅含系统事件，不含讲稿、录音或转写。", "System events only. No script, audio or transcript."))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(controller.diagnosticReport).font(.caption.monospaced()).textSelection(.enabled)
                            .accessibilityIdentifier("floating-diagnostics")
                        ShareLink(t("分享诊断", "Share diagnostics"), item: controller.diagnosticReport)
                    }.font(.footnote)
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-floating-interruptions"),
                       ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-library=") }) {
                        Button("Simulate audio interruption") {
                            NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
                                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
                            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
                                userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue])
                        }.accessibilityIdentifier("floating-test-interruption")
                    }
                    #endif
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.background(OraloStyle.canvas)
                .navigationTitle(t("小窗提词", "Floating prompt")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(t("完成", "Done")) { dismiss() }.accessibilityIdentifier("floating-done")
                } }
                .sheet(isPresented: $choosingPassage) { passagePicker }
                .onAppear { controller.showPreview() }
                .onDisappear { controller.hidePreview() }
        }.tint(OraloStyle.readingAccent)
    }
    @ViewBuilder private func previewControls(singleLine: Bool) -> some View {
        Button(controller.mode == .voice
               ? (controller.voiceState == .preparing ? t("取消准备", "Cancel preparation") : controller.isPlaying ? t("暂停跟随", "Pause following") : t("试试语音跟随", "Try voice following"))
               : (controller.isPlaying ? t("暂停预览", "Pause preview") : t("预览滚动", "Preview scrolling")), systemImage: controller.isPlaying ? "pause.fill" : controller.mode == .voice ? "mic" : "play.fill") {
            controller.togglePreview()
        }.fixedSize(horizontal: singleLine, vertical: true)
            .frame(minHeight: 44)
            .disabled(controller.hasEnded || controller.document == nil || controller.isOpen)
            .accessibilityIdentifier("floating-preview-play")
        Button(t("选择起点", "Choose passage"), systemImage: "text.line.first.and.arrowtriangle.forward") {
            controller.pause(); choosingPassage = true
        }.fixedSize(horizontal: singleLine, vertical: true)
            .frame(minHeight: 44)
            .disabled(controller.document == nil)
            .accessibilityIdentifier("floating-choose-passage")
    }
    private var passagePicker: some View {
        NavigationStack {
            List {
                if let document = controller.document {
                    ForEach(Array(document.segmentSpans().enumerated()), id: \.element.0) { index, pair in
                        if let segment = document.segments.first(where: { $0.id == pair.0 }) {
                            Button { controller.seek(pair.1.location); choosingPassage = false } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
                                    Text(segment.text).foregroundStyle(.primary)
                                }.padding(.vertical, 8)
                            }.accessibilityIdentifier("floating-passage-\(index)")
                        }
                    }
                }
            }.navigationTitle(t("从这里开始", "Start from here")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("取消", "Cancel")) { choosingPassage = false } } }
        }
    }
}
