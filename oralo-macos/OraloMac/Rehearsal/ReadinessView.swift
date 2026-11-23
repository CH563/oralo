import AppKit
import AVFoundation
import Speech
import SwiftUI
import OraloCore

struct StartRequest: Identifiable {
    let id = UUID()
    let document: ScriptDocument
    let floating: Bool
    let kind: RehearsalRecord.Kind
    var initialMode: PromptMode
}

@MainActor @Observable final class MacReadiness {
    enum State { case idle, checking, ready, needsModel, unavailable }
    private(set) var state = State.idle
    private(set) var message = ""
    private(set) var levels: [Float] = Array(repeating: 0, count: 23)
    private(set) var heardSound = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var capture = MicrophoneCapture()
    @ObservationIgnored private var cancelDownload: (() -> Void)?
    @ObservationIgnored private var token = UUID()
    func stop() {
        token = UUID(); task?.cancel(); task = nil; cancelDownload?(); cancelDownload = nil; capture.stop()
    }
    func check(locale: String, compatibility: Bool, download: Bool = false) {
        stop(); let current = UUID(); token = current
        state = .checking; heardSound = false
        levels = Array(repeating: 0, count: 23)
        message = MacCopy.text("检查设备端识别…", "Checking on-device recognition…")
        task = Task {
            do {
                if !compatibility, #available(macOS 26, *) {
                    guard SpeechTranscriber.isAvailable,
                          let language = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else {
                        throw SpeechFailure.unavailable("This device or language does not support the new speech model. Try Compatibility mode, or use manual cue selection.")
                    }
                    try Task.checkCancellation()
                    let module = SpeechTranscriber(locale: language, preset: .timeIndexedProgressiveTranscription)
                    let status = await AssetInventory.status(forModules: [module])
                    try Task.checkCancellation()
                    guard status != .unsupported else { throw SpeechFailure.unavailable("The speech model is unavailable for this language on this device.") }
                    if status != .installed {
                        guard download else { throw SpeechFailure.modelRequired }
                        message = MacCopy.text("下载设备端语音模型…", "Downloading on-device speech model…")
                        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                            try Task.checkCancellation()
                            cancelDownload = { request.progress.cancel() }
                            try await request.downloadAndInstall()
                            cancelDownload = nil
                        }
                    }
                } else {
                    let authorization = await withCheckedContinuation { continuation in
                        SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
                    }
                    try Task.checkCancellation()
                    guard authorization == .authorized else {
                        throw SpeechFailure.permission("Speech recognition access is off. Enable it in Settings, or use manual cue selection.")
                    }
                    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
                          recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
                        throw SpeechFailure.unavailable("On-device recognition is unavailable for this device or language. No audio will be sent to a server; manual cue selection is available.")
                    }
                }
                try await MicrophoneCapture.authorize()
                try Task.checkCancellation()
                guard token == current else { return }
                let chunks = try capture.start()
                state = .ready
                message = MacCopy.text("识别已就绪，请说一句话检查音量。", "Recognition is ready. Say a sentence to check the input level.")
                var meterTime = Date.distantPast
                for try await chunk in chunks {
                    try Task.checkCancellation()
                    guard token == current else { return }
                    if chunk.level > 0.2 { heardSound = true }
                    if Date().timeIntervalSince(meterTime) > 0.1 {
                        levels.removeFirst(); levels.append(chunk.level); meterTime = .now
                    }
                }
            } catch {
                guard token == current, !Task.isCancelled else { return }
                capture.stop()
                if case SpeechFailure.modelRequired = error { state = .needsModel } else { state = .unavailable }
                message = MacCopy.error(error)
            }
        }
    }
}

struct ReadinessView: View {
    let request: StartRequest
    let model: MacAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var readiness = MacReadiness()
    @State private var mode: PromptMode
    @State private var starting = false
    init(request: StartRequest, model: MacAppModel) {
        self.request = request; self.model = model; _mode = State(initialValue: request.initialMode)
    }
    private var canStart: Bool { mode != .voice || readiness.state == .ready }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(MacCopy.text("准备开讲", "Ready when you are")).font(.title.bold())
                    Text(request.document.displayTitle).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button { readiness.stop(); dismiss() } label: { Image(systemName: "xmark") }
                    .help(MacCopy.text("关闭", "Close")).accessibilityLabel(MacCopy.text("关闭", "Close")).keyboardShortcut(.cancelAction)
            }
            Text(MacCopy.metrics(request.document.text, preferences: model.preferences)).font(.callout).foregroundStyle(.secondary)
            Picker(MacCopy.text("提词方式", "Prompt mode"), selection: $mode) {
                ForEach(PromptMode.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    if mode == .voice {
                        HStack {
                            Label(request.document.localeID == "zh-CN" ? MacCopy.text("普通话 · 设备端识别", "Mandarin · on-device") : "English · on-device", systemImage: "waveform")
                            Spacer()
                            if readiness.state == .checking { ProgressView().controlSize(.small) }
                        }
                        Text(readiness.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            SoundWave(levels: readiness.levels, active: readiness.state == .ready)
                            Spacer()
                            Text(readiness.heardSound ? MacCopy.text("已检测到声音", "Sound detected") : MacCopy.text("系统当前输入设备", "Current system input"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            if readiness.state == .needsModel {
                                Button(MacCopy.text("下载模型", "Download model")) { check(download: true) }
                            }
                            Button(MacCopy.text("重新检查", "Check again")) { check() }.disabled(readiness.state == .checking)
                            Button(MacCopy.text("系统声音设置", "Sound settings")) {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                            }
                        }
                        Toggle(MacCopy.text("兼容识别模式", "Compatibility recognition"), isOn: Binding(get: { model.preferences.compatibility }, set: {
                            model.preferences.compatibility = $0; check()
                        })).controlSize(.small)
                    } else {
                        Label(MacCopy.text("麦克风关闭", "Microphone stays off"), systemImage: "mic.slash")
                        Text(mode == .fixed ? MacCopy.text("按设定语速滚动，可随时暂停或选句。", "Scrolls at your chosen pace. Pause or select a sentence anytime.") : MacCopy.text("用上一句、下一句或点击正文控制进度。", "Use Back, Next, or click a sentence to move through your script."))
                            .foregroundStyle(.secondary)
                        if mode == .fixed { PaceSpeedControl(preferences: model.preferences) }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            if request.document.layoutNeedsReview || request.document.pronunciations.contains(where: \.needsReview) {
                Label(MacCopy.text("有分句或注音需要检查，可返回备稿处理。", "Some sentence breaks or readings need attention in Prepare."), systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Text(request.kind == .rehearsal ? MacCopy.text("记录停顿和接稿，结束后复盘。", "Review pauses and cue changes afterward.") : MacCopy.text("按你的节奏，自然地讲。", "Speak naturally, at your pace."))
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button(request.kind == .rehearsal ? MacCopy.text("开始排练", "Start rehearsal") : MacCopy.text("开始演讲", "Start speaking")) {
                    starting = true; readiness.stop()
                    Task { await model.launch(request, mode: mode); starting = false }
                }.oraloActionStyle(prominent: true).disabled(!canStart || starting).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 560).oraloActionStyle()
            .preferredColorScheme(model.preferences.colorScheme)
            .task { check() }
            .onChange(of: mode) { check() }
            .onDisappear { readiness.stop() }
    }
    private func check(download: Bool = false) {
        readiness.stop()
        if mode == .voice { readiness.check(locale: request.document.localeID, compatibility: model.preferences.compatibility, download: download) }
    }
}

struct PaceSpeedControl: View {
    @Bindable var preferences: MacPreferences
    var session: MacSpeechSession? = nil
    var body: some View {
        HStack {
            Text(MacCopy.text("速度", "Speed"))
            Slider(value: Binding(get: { preferences.fixedSpeed }, set: {
                preferences.fixedSpeed = $0; session?.fixedSpeed = $0
            }), in: 0.5...2, step: 0.1) { Text(MacCopy.text("定速倍率", "Pace multiplier")) }.labelsHidden()
            Text(String(format: "%.1f×", preferences.fixedSpeed)).monospacedDigit().frame(width: 40)
        }
    }
}

struct PromptModeControl: View {
    @Bindable var preferences: MacPreferences
    let session: MacSpeechSession
    var floating = false
    var body: some View {
        VStack(spacing: 8) {
            Picker(MacCopy.text("提词方式", "Prompt mode"), selection: Binding(get: { session.mode }, set: {
                if floating { preferences.floatingMode = $0 } else { preferences.startingMode = $0 }
                if $0 != .fixed { preferences.followsVoice = $0 == .voice }
                session.changeMode($0)
            })) { ForEach(PromptMode.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            PaceSpeedControl(preferences: preferences, session: session).disabled(session.mode != .fixed)
        }
    }
}
