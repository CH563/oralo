import AVFoundation
import OraloCore
import SwiftUI

struct SpeechPrototypeView: View {
    enum StartMode { case manual, voice }
    @State private var model: SpeechPrototypeModel
    @State private var sheet: Panel?
    @State private var resumeAfterSelection = false
    @State private var isPresenting = false
    @State private var controlsVisible = false
    @State private var manualPaused = false
    @State private var switchedToManual = false
    @State private var resumeAfterFinish = false
    @State private var finishing = false
    @State private var hasStarted = false
    @State private var replayPronunciations: [UUID: [Pronunciation]] = [:]
    private let startMode: StartMode?
    private let recorder: RehearsalRecorder?
    private let onFinish: (() -> Void)?
    private var usingManual: Bool { startMode == .manual || switchedToManual }
    private func t(_ zh: String, _ en: String) -> String { PronunciationCopy.text(zh, en) }
    private let title: String
    private let pauseAfter: Set<UUID>
    private let pronunciations: [UUID: [Pronunciation]]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var readingSize = 32

    init(model: SpeechPrototypeModel = SpeechPrototypeModel(), startMode: StartMode? = nil,
         title: String = "Oralo", pauseAfter: Set<UUID> = [], pronunciations: [UUID: [Pronunciation]] = [:],
         recorder: RehearsalRecorder? = nil, onFinish: (() -> Void)? = nil) {
        _model = State(initialValue: model)
        _isPresenting = State(initialValue: startMode != nil)
        self.startMode = startMode; self.title = title; self.pauseAfter = pauseAfter
        self.pronunciations = pronunciations
        self.recorder = recorder; self.onFinish = onFinish
    }

    private enum Panel: String, Identifiable {
        case setup, recovery, diagnostics, finish
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !isPresenting { statusPanel }
                script
            }
            .background(OraloStyle.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Script & language", systemImage: "slider.horizontal.3") {
                        model.pause(); sheet = .setup
                    }
                    .accessibilityIdentifier("setup")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Test report", systemImage: "chart.bar.xaxis") { sheet = .diagnostics }
                        .accessibilityIdentifier("diagnostics")
                }
            }
            .toolbar(isPresenting ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(isPresenting)
            .persistentSystemOverlays(isPresenting ? .hidden : .automatic)
            .safeAreaInset(edge: .bottom) { if !isPresenting { controls } }
            .overlay(alignment: .top) {
                if isPresenting {
                    if controlsVisible {
                        presentationHeader
                    } else {
                        Button { controlsVisible = true } label: {
                            MicrophoneWaveform(levels: model.audioLevels, isRecording: model.isRecording)
                                .frame(minWidth: 112, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show presentation controls")
                        .accessibilityValue(model.isRecording ? "Microphone on" : "Microphone paused")
                        .accessibilityIdentifier("show-controls-waveform")
                        .padding(.top, 4)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if isPresenting && controlsVisible { controls }
            }
            .sheet(item: $sheet) { panel in
                switch panel {
                case .setup: ScriptSetupView(model: model)
                case .recovery: recovery
                case .diagnostics: DiagnosticsView(model: model)
                case .finish: finishSheet
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    recorder?.pause(interrupted: true)
                    if usingManual { manualPaused = true; controlsVisible = true }
                    model.interrupt("app entered background")
                }
                UIApplication.shared.isIdleTimerDisabled = phase == .active && isPresenting && !manualPaused
            }
            .onChange(of: model.isRecording) { _, recording in
                // Only entering presentation changes chrome. Recognition renewals must not
                // close controls that the speaker deliberately opened.
                if recording && !isPresenting { enterPresentation() }
            }
            .onChange(of: model.lastError) { _, error in
                if error != nil { controlsVisible = true }
            }
            .onChange(of: model.interruptions) { _, _ in controlsVisible = true }
            .onChange(of: model.busy) { _, _ in
                UIApplication.shared.isIdleTimerDisabled = isPresenting && scenePhase == .active && !manualPaused
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) {
                if let value = $0.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                   AVAudioSession.InterruptionType(rawValue: value) == .began {
                    recorder?.pause(interrupted: true)
                    if usingManual { manualPaused = true; controlsVisible = true }
                }
                model.handleAudioInterruption($0)
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) {
                model.handleRouteChange($0)
            }
            .onAppear {
                guard !hasStarted else { return }
                hasStarted = true
                if let recorder {
                    let speechModel = model
                    speechModel.sessionSignal = { [weak recorder, weak speechModel] signal in
                        guard let recorder, let model = speechModel else { return }
                        switch signal {
                        case .started: recorder.startOrResume(cueID: model.follower.session.currentCueID)
                        case .recognized(let cueID, let holding): recorder.observe(cueID: cueID, holding: holding)
                        case .interrupted, .unavailable: recorder.pause(interrupted: true)
                        case .renewing: recorder.pause()
                        }
                    }
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-pronunciation-replay") {
                    for cue in model.follower.cues {
                        for (term, pinyin) in [("团队进展", "tuán duì jìn zhǎn"), ("交付质量", "jiāo fù zhì liàng"), ("谢谢", "xiè xie")] {
                            let range = (cue.text as NSString).range(of: term)
                            if range.location != NSNotFound {
                                replayPronunciations[cue.id, default: []].append(Pronunciation(span: TextSpan(range), term: term, reading: pinyin, kind: .pinyin))
                            }
                        }
                    }
                }
                #endif
                if startMode != nil {
                    enterPresentation()
                    if usingManual { recorder?.startOrResume(cueID: model.follower.session.currentCueID) }
                    else if startMode == .voice { model.start() }
                }
            }
            .onDisappear { model.sessionSignal = nil; model.pause(); recorder?.leave(); UIApplication.shared.isIdleTimerDisabled = false }
        }
        .tint(.accentColor)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(startMode == nil ? "VOICE FOLLOWING · PROTOTYPE" : "VOICE FOLLOWING")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.currentIndex + 1) / \(model.follower.cues.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("cue-position")
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                HStack(alignment: .top) {
                    Image(systemName: model.isRecording ? "mic.fill" : "pause.circle")
                        .foregroundStyle(model.isRecording ? Color.accentColor : .secondary)
                    Text(model.stateLabel(at: timeline.date)).font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    Text(Duration.seconds(Int64(model.activeSeconds(at: timeline.date))), format: .time(pattern: .minuteSecond))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if model.isPreparing { ProgressView().controlSize(.small) }
            if model.isRecording {
                MicrophoneWaveform(levels: model.audioLevels, isRecording: model.isRecording)
            }
            if let error = model.lastError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                if model.needsModel {
                    Button("Download model & start") { model.start(downloadModels: true) }
                        .buttonStyle(.bordered)
                }
                if model.permissionDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var script: some View {
        ScriptReader(cues: model.follower.cues,
                     recognizedIndex: model.currentIndex,
                     confirmedCharacters: model.follower.reading.confirmedCharacterCount,
                     position: model.readingPosition,
                     fontSize: readingSize,
                     presenting: isPresenting,
                     controlsVisible: controlsVisible,
                     reduceMotion: reduceMotion,
                     pauseAfter: pauseAfter,
                     pronunciations: replayPronunciations.isEmpty ? pronunciations : replayPronunciations,
                     select: {
                         selectCue($0, reason: .selection)
                         UIApplication.shared.isIdleTimerDisabled = isPresenting && !manualPaused
                     },
                     revealControls: { controlsVisible = true })
    }

    private func enterPresentation() {
        isPresenting = true
        controlsVisible = false
        UIApplication.shared.isIdleTimerDisabled = true
        #if DEBUG
        model.startLayoutReplayIfRequested()
        #endif
    }

    private var presentationHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                OraloAction(title: "Exit", symbol: "chevron.down", compact: true) {
                    if recorder != nil {
                        resumeAfterFinish = usingManual ? !manualPaused : model.busy
                        recorder?.pause(); model.pause(); manualPaused = true; sheet = .finish
                    } else {
                        model.pause(); isPresenting = false; controlsVisible = false
                        if startMode != nil { dismiss() }
                    }
                }
                .accessibilityIdentifier("exit-presentation")
                Spacer()
                VStack(spacing: 3) {
                    MicrophoneWaveform(levels: model.audioLevels, isRecording: model.isRecording)
                    Text("\(model.currentIndex + 1) / \(model.follower.cues.count)")
                        .font(.caption2.monospacedDigit())
                        .accessibilityIdentifier("presentation-position")
                    if let recorder {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text((recorder.kind == .rehearsal ? t("排练", "Rehearsal") : t("演讲", "Presentation")) + " · " + SessionCopy.duration(recorder.duration()))
                                .font(.caption2.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                                .foregroundStyle(.secondary).accessibilityIdentifier("session-duration")
                        }
                    }
                    if usingManual {
                        Text(manualPaused ? "Paused · Manual" : "Manual")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                OraloAction(title: "Hide", symbol: "eye.slash", compact: true) { controlsVisible = false }
                    .accessibilityIdentifier("hide-controls")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            if !usingManual && (model.lastError != nil || model.isPreparing) {
                VStack(spacing: 8) {
                    statusPanel
                    if recorder != nil {
                        Button(t("继续手动切句", "Continue manually")) {
                            model.pause(); switchedToManual = true; manualPaused = false
                            recorder?.switchToManual(cueID: model.follower.session.currentCueID)
                        }.padding(.bottom, 12).accessibilityIdentifier("continue-manually")
                    }
                }.background(.regularMaterial, in: .rect(cornerRadius: 18)).padding(.horizontal, 12)
            }
            if let recorder, recorder.saveError != nil {
                Text(t("记录暂未保存，结束后可重试。", "Record not saved yet. You can retry after finishing."))
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        if isPresenting {
            OraloGlassGroup {
                HStack(spacing: 10) {
                    OraloAction(title: "Back", symbol: "backward.end") { move(-1) }
                        .disabled(model.currentIndex == 0).accessibilityIdentifier("previous-cue")
                    OraloAction(title: usingManual ? (manualPaused ? "Resume" : "Pause") : (model.busy ? (model.isPreparing ? "Cancel" : "Pause") : "Resume"),
                                symbol: usingManual ? (manualPaused ? "play.fill" : "pause.fill") : (model.busy ? "pause.fill" : "mic.fill"), prominent: true) {
                        if usingManual {
                            manualPaused.toggle()
                            if manualPaused { recorder?.pause() }
                            else { recorder?.startOrResume(cueID: model.follower.session.currentCueID) }
                            UIApplication.shared.isIdleTimerDisabled = !manualPaused
                        } else if model.busy { recorder?.pause(); model.pause() } else { model.start() }
                    }.accessibilityIdentifier("start-stop")
                    OraloAction(title: "Next", symbol: "forward.end") { move(1) }
                        .disabled(model.currentIndex + 1 == model.follower.cues.count).accessibilityIdentifier("next-cue")
                    OraloAction(title: "Pick up", symbol: "arrow.uturn.backward") { openRecovery() }
                        .accessibilityIdentifier("recovery")
                }
            }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
        } else { prototypeControls }
    }

    private func move(_ step: Int) {
        let index = model.currentIndex + step
        guard model.follower.cues.indices.contains(index) else { return }
        selectCue(model.follower.cues[index], reason: step < 0 ? .previous : .next)
        UIApplication.shared.isIdleTimerDisabled = isPresenting && !manualPaused
    }

    private func openRecovery() {
        resumeAfterSelection = usingManual ? !manualPaused : model.busy
        recorder?.pause()
        if usingManual { manualPaused = true }
        model.pause()
        UIApplication.shared.isIdleTimerDisabled = isPresenting && !manualPaused
        sheet = .recovery
    }

    private func selectCue(_ cue: ScriptCue, reason: RehearsalEvent.Kind, resume: Bool? = nil) {
        let shouldResume = resume ?? (usingManual ? !manualPaused : model.busy)
        recorder?.pause()
        recorder?.move(to: cue.id, reason: reason)
        model.select(cue, resume: usingManual ? false : shouldResume)
        if usingManual && shouldResume {
            manualPaused = false; recorder?.startOrResume(cueID: cue.id)
        }
    }

    private var finishSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(recorder?.kind == .rehearsal ? t("结束这次排练？", "Finish this rehearsal?") : t("结束这次演讲？", "Finish this talk?")).font(.title2.bold())
                Text(t("记录会保存在这篇讲稿下，可以随时回来回看。", "Your record stays with this script. Come back whenever you’re ready."))
                    .foregroundStyle(.secondary)
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
        }.background(OraloStyle.canvas)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    SessionPrimary(title: finishing ? t("正在保存…", "Saving…") : t("结束并查看记录", "Finish & review"), symbol: "checkmark", id: "finish-session") {
                        finishing = true
                        Task {
                            await recorder?.finish(completed: model.currentIndex == model.follower.cues.count - 1)
                            sheet = nil; onFinish?()
                        }
                    }.disabled(finishing)
                    Button(t("继续", "Continue")) {
                        sheet = nil
                        if resumeAfterFinish {
                            if usingManual { manualPaused = false; recorder?.startOrResume(cueID: model.follower.session.currentCueID) }
                            else { model.start() }
                        }
                    }.frame(maxWidth: .infinity, minHeight: 44).disabled(finishing).accessibilityIdentifier("continue-session")
                }.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 12).background(OraloStyle.canvas)
            }
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible).interactiveDismissDisabled()
    }

    private var prototypeControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(model.busy ? (model.isPreparing ? "Cancel" : "Pause") : "Start / Resume",
                       systemImage: model.busy ? "pause.fill" : "mic.fill") {
                    if model.busy { model.pause() } else { model.start() }
                }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                .accessibilityIdentifier("start-stop")
                Button("Pick up here", systemImage: "arrow.uturn.backward") {
                    openRecovery()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("recovery")
            }
            .controlSize(.large)
            if !isPresenting {
                Button("Enter presentation", systemImage: "arrow.up.left.and.arrow.down.right") { enterPresentation() }
                    .font(.subheadline).accessibilityIdentifier("enter-presentation")
            }
            Text(isPresenting
                 ? "Tap Hide to focus. Tap the reading area to show controls."
                 : "Purple follows your voice; an underlined tail estimates your pace. Audio stays on device.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private var recovery: some View {
        NavigationStack {
            List(Array(model.follower.cues.enumerated()), id: \.element.id) { index, cue in
                Button {
                    selectCue(cue, reason: .selection, resume: resumeAfterSelection)
                    UIApplication.shared.isIdleTimerDisabled = isPresenting && !manualPaused
                    sheet = nil
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(index + 1)\(index == model.currentIndex ? " · Current" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(cue.text).font(.title3).foregroundStyle(.primary)
                    }.padding(.vertical, 8)
                }
                .accessibilityIdentifier("recover-\(index)")
            }
            .navigationTitle("Choose where to continue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Stay paused") { sheet = nil } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
