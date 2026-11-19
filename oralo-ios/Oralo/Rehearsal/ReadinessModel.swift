import AVFoundation
import Observation
import Speech
import UIKit

@MainActor @Observable
final class ReadinessModel {
    enum State { case unchecked, checking, ready, needsModel, denied, unavailable }
    private(set) var state: State = .unchecked
    private(set) var levels: [Float] = Array(repeating: 0, count: 23)
    private(set) var heardSound = false
    private(set) var detail: String?
    private(set) var battery: Int?
    var backend = SpeechPrototypeModel.Backend.automatic
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var capture: MicrophoneCapture?
    @ObservationIgnored private var cancelInstallation: (() -> Void)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lastLevel = Date.distantPast
    @ObservationIgnored private var wasMonitoringBattery = false
    private func t(_ zh: String, _ en: String) -> String { PronunciationCopy.text(zh, en) }

    func appear() {
        wasMonitoringBattery = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshBattery()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-library=") }) {
            if ProcessInfo.processInfo.arguments.contains("--ui-session-speech-replay") { state = .ready }
            if ProcessInfo.processInfo.arguments.contains("--ui-preflight=denied") { state = .denied }
            if ProcessInfo.processInfo.arguments.contains("--ui-preflight=unavailable") { state = .unavailable }
        }
        #endif
    }
    func refreshBattery() { let value = UIDevice.current.batteryLevel; battery = value < 0 ? nil : Int(value * 100) }
    func disappear() { stop(); UIDevice.current.isBatteryMonitoringEnabled = wasMonitoringBattery }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil
        cancelInstallation?(); cancelInstallation = nil
        capture?.stop(); capture = nil
        levels = Array(repeating: 0, count: 23)
        if state == .checking || state == .ready { state = .unchecked }
    }
    func check(localeID: String, download: Bool = false) {
        stop(); state = .checking; detail = nil; heardSound = false
        let token = UUID(); generation = token
        let microphone = MicrophoneCapture(); capture = microphone
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if self.backend == .automatic, #available(iOS 26, *) {
                    try await self.checkModern(localeID: localeID, download: download)
                } else {
                    let status = await withCheckedContinuation { continuation in
                        SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
                    }
                    try Task.checkCancellation()
                    guard status == .authorized else { throw SpeechFailure.permission(self.t("请在系统设置中开启语音识别。", "Enable speech recognition in Settings.")) }
                    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable,
                          recognizer.supportsOnDeviceRecognition else { throw SpeechFailure.unavailable(self.t("此设备或语言暂不能使用设备端识别。", "On-device recognition is unavailable for this device or language.")) }
                }
                try Task.checkCancellation()
                try await MicrophoneCapture.authorize()
                try Task.checkCancellation()
                guard self.generation == token else { return }
                let samples = try microphone.start()
                self.state = .ready
                for try await chunk in samples {
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    guard Date().timeIntervalSince(self.lastLevel) >= 0.1 else { continue }
                    self.lastLevel = .now
                    let level = chunk.level
                    self.heardSound = self.heardSound || level > 0.2
                    self.levels.removeFirst(); self.levels.append(level)
                }
            } catch {
                microphone.stop()
                guard self.generation == token, !Task.isCancelled else { return }
                switch error {
                case SpeechFailure.permission: self.state = .denied
                case SpeechFailure.modelRequired: self.state = .needsModel
                default: self.state = .unavailable
                }
                switch self.state {
                case .denied: self.detail = self.t("请在系统设置中检查麦克风与语音识别权限。也可以仅手动开始。", "Check microphone and speech permissions in Settings, or start manually.")
                case .needsModel: self.detail = self.t("此语言需要先下载语音模型。也可以仅手动开始。", "Download the speech model for this language, or start manually.")
                default: self.detail = self.t("设备端识别或当前收音暂不可用。请检查音频设备后重试，也可以手动开始。", "On-device recognition or audio input is unavailable. Check your audio device and retry, or start manually.")
                }
            }
        }
    }
    @available(iOS 26, *)
    private func checkModern(localeID: String, download: Bool) async throws {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw SpeechFailure.unavailable(t("此设备或语言暂不支持新语音模型，可试用兼容识别。", "The new speech model is unavailable. You can try compatibility recognition."))
        }
        try Task.checkCancellation()
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        let status = await AssetInventory.status(forModules: [transcriber])
        try Task.checkCancellation()
        guard status != .unsupported else { throw SpeechFailure.unavailable(t("此语言的模型暂不可用。", "The model is unavailable for this language.")) }
        if status != .installed {
            guard download else { throw SpeechFailure.modelRequired }
            detail = t("正在下载语音模型，可取消并手动开始。", "Downloading the speech model. You can cancel and start manually.")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try Task.checkCancellation(); cancelInstallation = { request.progress.cancel() }
                try await request.downloadAndInstall(); cancelInstallation = nil
            }
            try Task.checkCancellation()
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else { throw SpeechFailure.modelRequired }
        }
    }
}
