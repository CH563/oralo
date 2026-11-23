import AppKit
import Foundation
import Testing
import OraloCore
@testable import OraloMac

/// Opt-in hardware test. Retains only counters, never audio or recognized text.
@MainActor struct LiveCaptureTests {
    @available(macOS 26, *)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ORALO_VALIDATE_LIVE_AUDIO"] == "1"))
    func continuousBackgroundCaptureAndRestart() async throws {
        let meeting = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.meeting").first)
        let sample = QuickScript.sample(localization: "zh-Hans")
        let session = try MacSpeechSession(snapshot: ScriptDocument(text: sample.text).snapshot())
        defer { session.pause() }
        try await capture(seconds: 180, session: session, meeting: meeting)
        #expect(!session.recording)
        try await capture(seconds: 15, session: session, meeting: meeting)
        #expect(!session.recording)
    }

    @available(macOS 26, *)
    private func capture(seconds: Double, session: MacSpeechSession, meeting: NSRunningApplication) async throws {
        let source = ModernSpeechSource()
        let probe = CaptureProbe()
        let startingCue = session.currentIndex
        let worker = Task {
            do {
                try await source.run(locale: Locale(identifier: "zh-CN"), downloadModels: false) { event in
                    switch event {
                    case .started: probe.started = true
                    case .level(_, let duration): probe.audioSeconds += duration; probe.buffers += 1
                    case .transcript: probe.transcriptUpdates += 1
                    default: break
                    }
                    session.receive(event)
                }
            } catch {
                if !Task.isCancelled { probe.failure = error.localizedDescription }
            }
        }
        defer { worker.cancel(); source.stop(); session.pause() }
        let preparationDeadline = Date().addingTimeInterval(20)
        while !probe.started && probe.failure == nil && Date() < preparationDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(probe.started, "Recognition failed to start: \(probe.failure ?? "timed out")")
        #expect(session.currentIndex == startingCue)
        meeting.activate()
        NSApp.hide(nil)
        let beginning = Date()
        var previousSeconds = probe.audioSeconds
        var nextCheckpoint = 30.0
        while Date().timeIntervalSince(beginning) < seconds {
            try await Task.sleep(for: .seconds(5))
            try #require(probe.failure == nil, "Capture failed: \(probe.failure ?? "")")
            try #require(session.recording)
            try #require(probe.audioSeconds - previousSeconds > 3, "Audio buffers stalled")
            previousSeconds = probe.audioSeconds
            if Date().timeIntervalSince(beginning) >= nextCheckpoint {
                print("Live capture checkpoint: \(Int(probe.audioSeconds)) audio seconds; \(probe.buffers) buffers")
                nextCheckpoint += 30
            }
        }
        #expect(probe.audioSeconds >= seconds * 0.9)
        // A user may switch between the meeting and other apps during this long run.
        // Foreground-control behavior is covered separately by the coordinate UI test.
        #expect(!NSApp.isActive)
        #expect(!meeting.isTerminated)
        print("Live capture: \(Int(probe.audioSeconds)) seconds, \(probe.buffers) buffers, \(probe.transcriptUpdates) transcript updates; no content retained")
        worker.cancel(); source.stop(); session.pause()
        await worker.value
    }
}

@MainActor private final class CaptureProbe {
    var started = false
    var audioSeconds = 0.0
    var buffers = 0
    var transcriptUpdates = 0
    var failure: String?
}
