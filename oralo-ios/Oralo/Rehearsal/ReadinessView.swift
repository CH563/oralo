import AVFoundation
import OraloCore
import SwiftUI

struct ReadinessRequest: Identifiable {
    let id = UUID()
    let document: ScriptDocument
    let kind: RehearsalRecord.Kind
    let manual: Bool
}

struct ReadinessView: View {
    let request: ReadinessRequest
    let start: (SpeechPrototypeView.StartMode, SpeechPrototypeModel.Backend) -> Void
    @State private var model = ReadinessModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private func t(_ zh: String, _ en: String) -> String { PronunciationCopy.text(zh, en) }
    private var unavailable: Bool { [.denied, .unavailable, .needsModel].contains(model.state) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.state == .ready || request.manual ? t("准备好了，\n按你的节奏来。", "All set.\nGo at your pace.") : unavailable ? t("仍然可以，\n按你的节奏讲。", "You can still speak\nat your pace.") : t("开始之前，\n确认一下就好。", "Before you begin,\na quick check."))
                            .font(.largeTitle.bold())
                        Text(request.document.localizedTitle + " · " + (request.kind == .rehearsal ? t("排练", "Rehearsal") : t("演讲", "Presentation")))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if request.manual {
                        Label(t("手动切句，无需麦克风。", "Manual cues. No microphone needed."), systemImage: "hand.draw")
                            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
                    } else { checks }
                    if let battery = model.battery {
                        Label(battery <= 20 ? t("电量 \(battery)% · 建议接上电源", "\(battery)% battery · Consider charging") : t("电量 \(battery)%", "\(battery)% battery"), systemImage: battery <= 20 ? "battery.25percent" : "battery.100percent")
                            .font(.footnote).foregroundStyle(battery <= 20 ? .orange : .secondary)
                    }
                    Text(t("只记录进度，不保存录音或完整转写。", "Progress is saved. Audio and full transcripts are not.")).font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(OraloStyle.canvas)
                .navigationTitle(t("开始前", "Before you start")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button(t("关闭", "Close"), systemImage: "xmark") { model.stop(); dismiss() }.labelStyle(.iconOnly).accessibilityIdentifier("close-readiness")
                } }
                .safeAreaInset(edge: .bottom) { actions }
        }
        .tint(OraloStyle.readingAccent)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               AVAudioSession.InterruptionType(rawValue: raw) == .began { model.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
               [.oldDeviceUnavailable, .newDeviceAvailable, .noSuitableRouteForCategory, .override].contains(reason) { model.stop() }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background || (phase == .inactive && model.state == .ready) { model.stop() } else if phase == .active { model.refreshBattery() } }
    }
    private var checks: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: model.state == .denied ? "mic.slash" : "mic").foregroundStyle(OraloStyle.readingAccent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.state == .ready ? (model.heardSound ? t("收音正常", "Sound is coming through") : t("收音已开启", "Microphone is ready")) : model.state == .denied ? t("需要开启权限", "Permission needed") : t("检查收音", "Check your microphone")).font(.headline)
                    Text(t("设备放稳后，说一句试试", "Set your device down and try a sentence")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            MicrophoneWaveform(levels: model.levels, isRecording: model.state == .ready)
                .frame(maxWidth: .infinity).padding(.vertical, 6).accessibilityIdentifier("readiness-waveform")
            Divider()
            HStack(spacing: 14) {
                Image(systemName: "waveform.path").foregroundStyle(OraloStyle.readingAccent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(t("语音跟随", "Voice following")).font(.headline)
                    Text((request.document.localeID.hasPrefix("zh") ? t("普通话", "Mandarin") : t("英语", "English")) + " · " + stateText)
                        .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("readiness-status")
                }
                Spacer(minLength: 0)
                if model.state == .checking { ProgressView() }
                else { Image(systemName: model.state == .ready ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(model.state == .ready ? .green : .secondary) }
            }
            if let detail = model.detail { Text(detail).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("readiness-detail") }
            if model.state == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                Link(t("前往系统设置", "Open Settings"), destination: url)
            }
            if model.state == .needsModel {
                Button(t("下载语音模型", "Download speech model")) { model.check(localeID: request.document.localeID, download: true) }
                    .accessibilityIdentifier("download-speech-model")
            }
            if model.state == .unavailable, model.backend == .automatic {
                Button(t("试用兼容识别", "Try compatibility recognition")) { model.backend = .compatibility; model.check(localeID: request.document.localeID) }
                    .accessibilityIdentifier("check-compatibility")
            }
        }.padding(22).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
    private var stateText: String {
        switch model.state {
        case .ready: t("设备端已就绪", "Ready on this device")
        case .checking: t("正在检查…", "Checking…")
        case .unchecked: t("尚未检查", "Not checked yet")
        case .needsModel: t("需要下载模型", "Model download needed")
        case .denied, .unavailable: t("暂不可用，可手动切句", "Unavailable · Manual cues work")
        }
    }
    private var actions: some View {
        VStack(spacing: 10) {
            if request.manual || unavailable {
                SessionPrimary(title: t("仅手动开始", "Start manually"), symbol: "play.fill", id: "readiness-start-manual") { begin(.manual) }
                if unavailable && model.state != .needsModel { Button(t("重新检查", "Check again")) { model.check(localeID: request.document.localeID) }.frame(minHeight: 44) }
            } else {
                SessionPrimary(title: model.state == .ready ? (request.kind == .rehearsal ? t("开始排练", "Start rehearsal") : t("开始演讲", "Start speaking")) : model.state == .checking ? t("取消检查", "Cancel check") : t("检查语音跟随", "Check voice following"), symbol: model.state == .ready ? "play.fill" : "waveform", id: "readiness-check-start") {
                    if model.state == .ready { begin(.voice) }
                    else if model.state == .checking { model.stop() }
                    else { model.check(localeID: request.document.localeID) }
                }
                Button(t("仅手动开始", "Start manually")) { begin(.manual) }.frame(minHeight: 44).accessibilityIdentifier("readiness-start-manual")
            }
        }.font(.subheadline).padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 12).background(OraloStyle.canvas)
    }
    private func begin(_ mode: SpeechPrototypeView.StartMode) {
        let backend = model.backend
        model.stop()
        start(mode, backend)
    }
}

struct SessionPrimary: View {
    let title: String
    var symbol = "arrow.up.right"
    var id = "session-primary"
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduced
    private var button: some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity, minHeight: 48) }
            .tint(Color("AccentColor")).foregroundStyle(.white).accessibilityIdentifier(id)
    }
    @ViewBuilder var body: some View {
        if #available(iOS 26, *), !reduced { button.buttonStyle(.glassProminent).buttonBorderShape(.capsule) }
        else { button.buttonStyle(.borderedProminent).buttonBorderShape(.capsule) }
    }
}
