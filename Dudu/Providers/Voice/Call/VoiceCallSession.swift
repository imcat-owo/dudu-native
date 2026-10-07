import AVFoundation
import Combine
import Foundation

// MARK: - VoiceCallSession — duplex call orchestrator.
//
// Drives the PURE DuplexTurnEngine; the engine decides, this session executes:
//   monitor mic (CallMicrophone dB) → EnergyVad → capture → WAV
//   → STT (VoiceCallAI) → LLM one-shot (VoiceCallAI) → sentence-split
//   → VoiceOutputPlayer (streaming TTS queue) → speaker.
//   Barge-in: BargeInVad on mic dB while speaking → stopSession (pause player,
//   cancel the TTS queue) → hand the turn back to her.
//
// Pipeline (cascaded, Pipecat-style, adapted to iOS constraints):
// Turn latency is chunked: capture + STT + LLM + first TTS sentence.
// Expect seconds, not the 1.5s of server-side realtime models.
//
// Honest limits:
// - The capture buffer is continuous (no recorder restart), so onset clipping
//   is ~0 — better than the old Dudu's ~200ms handoff gap.
// - Echo: barge-in uses a louder threshold while speaking (bargeInExtraDb);
//   the session runs .playAndRecord/.voiceChat so the OS hardware echo
//   canceller is in the path. Whether it fully suppresses speaker→mic
//   feedback on-device is NOT verified in CI — the dB guard is the backstop.

@MainActor
final class VoiceCallSession: ObservableObject {

    // MARK: - UI-observable state

    @Published private(set) var phase: CallPhase = .idle
    @Published private(set) var turnState: TurnState = .listening
    @Published private(set) var transcript: [CallTranscriptEntry] = []
    @Published private(set) var stats = CallStats()
    /// Live mic level in dB, throttled to ~15Hz for the waveform UI.
    @Published private(set) var levelDb: Float = -80
    @Published private(set) var isMuted = false
    @Published private(set) var isSpeakerOn = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var durationSec: Int = 0

    // MARK: - Config

    let personaName: String
    let entry: ModelEntry?
    /// TTS ownership id — barge-in stops ONLY this call's queued speech.
    let ttsSessionId = "voice-call-\(UUID().uuidString)"

    private let cfg = VadConfig.standard
    private let engine = DuplexTurnEngine()
    private let vad = EnergyVad(config: .standard)
    private let bargeVad = BargeInVad(config: .standard)
    private let mic = CallMicrophone()
    private let logger = AppLogger(category: "VoiceCall")

    private var history: [CallTurn] = []
    private var running = false
    private var speakToken = 0
    private var captureStartAt: Double = 0
    private var pushTalkActive = false
    private var wasMutedBeforePushTalk = false
    private var timer: Timer?
    private var lastLevelPublish: Double = 0

    init(personaName: String, entry: ModelEntry?) {
        self.personaName = personaName
        self.entry = entry
    }

    // MARK: - Lifecycle

    /// Start the call. `fromPhase` is .outgoing (she tapped call) or .ringing
    /// (she accepted an AI proposal) — connecting → live on success.
    func start(fromPhase: CallPhase) async {
        guard !running else { return }
        phase = .connecting
        errorMessage = nil

        // Mic permission first — no permission, no fake call.
        let micOK = await VoiceActivityDetector.requestMicrophonePermission()
        guard micOK else {
            fail("通话需要麦克风权限——去设置里打开才能说话。")
            return
        }
        // The call must be heard: refuse a silent call rather than faking one.
        guard VoiceCallAI.ttsAvailable() else {
            fail("通话需要语音合成——先去设置里配一个 TTS 服务再打过来。")
            return
        }
        guard entry != nil else {
            fail("通话需要先配好模型——先去「连接」里设置。")
            return
        }

        // Duplex session: mic + speaker together, voiceChat mode puts the OS
        // hardware echo canceller in the path (barge-in's dB guard is the
        // software backstop; on-device AEC is not verified in CI).
        _ = AudioSessionCoordinator.shared.beginAndWait(.voiceCall)
        // The tap hops to the main queue, but the closure is still
        // nonisolated — hop to the actor explicitly (same pattern as
        // SpeechRecognitionManager's tap → pushLevel).
        mic.onLevel = { [weak self] db in
            Task { @MainActor [weak self] in self?.onMetering(db) }
        }
        do {
            try mic.start()
        } catch {
            AudioSessionCoordinator.shared.end(.voiceCall)
            fail("麦克风启动失败：\(error.localizedDescription)")
            return
        }

        running = true
        stats = CallStats()
        stats.startedAt = Date()
        phase = .live
        publish()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                self.durationSec += 1
            }
        }
        logger.info("call started (from \(fromPhase.rawValue))")
    }

    /// End the call. Idempotent.
    func end(reason: String = "user-ended") {
        guard running || phase == .live || phase == .connecting else { return }
        phase = .ending
        publish()
        speakToken += 1
        for action in engine.dispatch(.endCall) { runAction(action) }
        teardown()
        phase = .ended
        publish()
        logger.info("call ended (\(reason))")
    }

    private func fail(_ message: String) {
        errorMessage = message
        phase = .ended
        publish()
        logger.warning("call failed to start: \(message)")
    }

    private func teardown() {
        running = false
        timer?.invalidate()
        timer = nil
        mic.onLevel = nil
        mic.stop()
        VoiceOutputPlayer.shared.stopSession(ttsSessionId)
        AudioSessionCoordinator.shared.end(.voiceCall)
    }

    // MARK: - Controls (all real, no dead buttons)

    /// Mute: stop listening entirely (no phantom VAD while muted).
    func setMuted(_ muted: Bool) {
        guard running else { return }
        isMuted = muted
        if muted {
            if engine.state == .capturing {
                mic.cancelCapture()
                for action in engine.dispatch(.userAbort) { runAction(action) }
            }
            mic.stop()
            vad.reset()
            bargeVad.reset()
        } else {
            do {
                try mic.start()
            } catch {
                errorMessage = "麦克风重启失败：\(error.localizedDescription)"
            }
        }
        publish()
    }

    /// Speaker / earpiece route. Real AVAudioSession route override —
    /// the old Dudu had no toggle (expo-audio couldn't do it); native can.
    func setSpeakerOn(_ on: Bool) {
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(on ? .speaker : .none)
            isSpeakerOn = on
        } catch {
            errorMessage = "切换扬声器失败：\(error.localizedDescription)"
        }
        publish()
    }

    // MARK: - Push-to-talk (WaveformKey)

    /// Press-and-hold: force a capture — interrupts the AI if speaking.
    /// Temporarily overrides mute for the hold.
    func beginPushToTalk() {
        guard running, !pushTalkActive else { return }
        pushTalkActive = true
        wasMutedBeforePushTalk = isMuted
        if isMuted {
            isMuted = false
            try? mic.start()
        }
        for action in engine.dispatch(.pushToTalkStart) { runAction(action) }
        publish()
    }

    /// Release: end the forced capture and transcribe.
    func endPushToTalk() {
        guard pushTalkActive else { return }
        pushTalkActive = false
        for action in engine.dispatch(.pushToTalkEnd) { runAction(action) }
        if wasMutedBeforePushTalk {
            setMuted(true)
        }
        publish()
    }

    // MARK: - Metering → VAD → engine

    private func nowMs() -> Double {
        ProcessInfo.processInfo.systemUptime * 1000
    }

    private func onMetering(_ db: Float) {
        guard running, !isMuted, !engine.isEnded else { return }
        // Throttle UI publishing; the VAD still sees every sample.
        let now = nowMs()
        if now - lastLevelPublish >= 66 {
            lastLevelPublish = now
            levelDb = db
        }
        switch engine.state {
        case .speaking:
            _ = bargeVad.push(db: db, nowMs: now)
            if bargeVad.isSpeaking && bargeVad.speechDurationMs(nowMs: now) >= cfg.minSpeechMs {
                doBargeIn()
            }
        case .listening:
            for e in vad.push(db: db, nowMs: now) where e == .speechStart {
                runActions(engine.dispatch(.vadSpeechStart))
            }
        case .capturing:
            for e in vad.push(db: db, nowMs: now) where e == .speechEnd {
                runActions(engine.dispatch(.vadSpeechEnd))
            }
            if now - captureStartAt > cfg.maxTurnMs {
                runActions(engine.dispatch(.captureTimeout))
            }
        case .thinking:
            break
        }
    }

    private func doBargeIn() {
        bargeVad.reset()
        speakToken += 1 // invalidate the in-flight speak queue
        runActions(engine.dispatch(.bargeIn))
        logger.info("barge-in: speech cancelled, turn handed to her")
    }

    // MARK: - Engine actions

    private func runActions(_ actions: [EngineAction]) {
        for a in actions { runAction(a) }
        publish()
    }

    private func runAction(_ action: EngineAction) {
        switch action {
        case .startCapture:
            captureStartAt = nowMs()
            // From a barge-in the normal VAD wasn't fed while speaking —
            // mark it explicitly so silence from here ends the capture.
            if !vad.isSpeaking { vad.forceSpeaking(nowMs: captureStartAt) }
            mic.startCapture()

        case .stopCaptureTranscribe:
            guard let wav = mic.stopCapture() else {
                runActions(engine.dispatch(.sttEmpty))
                return
            }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let text = try await VoiceCallAI.transcribe(wav: wav)
                    self.runActions(self.engine.dispatch(.sttDone(text: text)))
                } catch {
                    self.runActions(self.engine.dispatch(
                        .sttError(error: error.localizedDescription)))
                }
            }

        case .think(let userText):
            history.append(CallTurn(role: .user, text: userText))
            let snapshot = history
            Task { [weak self] in
                guard let self, let entry = self.entry else { return }
                do {
                    let text = try await VoiceCallAI.reply(
                        history: snapshot, entry: entry, personaName: self.personaName)
                    self.runActions(self.engine.dispatch(.llmDone(text: text)))
                } catch {
                    self.runActions(self.engine.dispatch(
                        .llmError(error: error.localizedDescription)))
                }
            }

        case .speak(let sentences):
            let token = speakToken + 1
            speakToken = token
            history.append(CallTurn(role: .assistant, text: sentences.joined()))
            let player = VoiceOutputPlayer.shared
            for s in sentences { player.enqueueForCall(s, sessionId: ttsSessionId) }
            // Wait until OUR queued speech fully drains, then back to listening.
            Task { [weak self] in
                guard let self else { return }
                await self.waitForSpeechDrain(player: player)
                guard token == self.speakToken, self.running else { return }
                self.runActions(self.engine.dispatch(.ttsQueueEmpty))
            }

        case .cancelSpeech:
            VoiceOutputPlayer.shared.stopSession(ttsSessionId)

        case .backToListening:
            break // mic never stopped metering; nothing to restart

        case .callEnded:
            teardown()
        }
        publish()
    }

    /// Poll the TTS queue until our sentences are done playing. Barge-in /
    /// end-of-call bump `speakToken`, which invalidates the wait.
    private func waitForSpeechDrain(player: VoiceOutputPlayer) async {
        // Give the prefetch a beat to mark synthesis in-flight so we don't
        // observe a false "drained" on the first poll.
        try? await Task.sleep(nanoseconds: 300_000_000)
        while running {
            if !player.isPlaying && !player.isSynthesizing { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func publish() {
        turnState = engine.state
        transcript = engine.getTranscript()
        stats = engine.getStats()
    }

    // MARK: - Handoff (no info loss)

    /// Call summary for the chat transcript. nil when nothing was actually
    /// said — no phantom summary for a call that never got going.
    func makeSummary() -> String? {
        let t = engine.getTranscript().filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !t.isEmpty else { return nil }
        let turns = engine.getStats().turns
        let mm = durationSec / 60
        let ss = durationSec % 60
        let dur = mm > 0 ? "\(mm)分\(ss)秒" : "\(ss)秒"
        var lines = ["【语音通话 · \(dur) · \(turns)轮】"]
        for e in t {
            let who = e.role == .user ? "她" : personaName
            lines.append("\(who)：\(e.text)")
        }
        if engine.getStats().bargeIns > 0 {
            lines.append("（她中途打断了 \(engine.getStats().bargeIns) 次）")
        }
        return lines.joined(separator: "\n")
    }
}
