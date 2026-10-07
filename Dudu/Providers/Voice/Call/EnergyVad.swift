import Foundation

// MARK: - Energy-based voice activity detection over dB metering samples.
// PURE — the clock is injected, so this is fully testable.
//
// Pattern adapted from Pipecat's VADParams (confidence/start_secs/stop_secs)
// minus the neural net: on-device we use the mic tap's dB metering.
// dB is negative; speech is louder (less negative).
//
// Ported from ~/workspace/openmuse/apps/mobile/src/voice-call/vad.ts.

enum VadEvent: Sendable {
    case speechStart
    case speechEnd
}

class EnergyVad: @unchecked Sendable {
    private let cfg: VadConfig
    private var speaking = false
    private var speechStartAt: Double = 0
    private var lastSpeechAt: Double = 0

    init(config: VadConfig) {
        self.cfg = config
    }

    /// Feed one metering sample. Returns any edge events.
    /// `db` nil (metering unavailable) is treated as silence.
    @discardableResult
    func push(db: Float?, nowMs: Double) -> [VadEvent] {
        var events: [VadEvent] = []
        let isSpeech = db.map { $0 > cfg.speechThresholdDb } ?? false
        if isSpeech {
            lastSpeechAt = nowMs
            if !speaking {
                speaking = true
                speechStartAt = nowMs
                events.append(.speechStart)
            }
        } else if speaking && nowMs - lastSpeechAt >= cfg.silenceEndMs {
            speaking = false
            events.append(.speechEnd)
        }
        return events
    }

    var isSpeaking: Bool { speaking }

    /// How long the current speech burst has lasted (for the barge-in gate).
    func speechDurationMs(nowMs: Double) -> Double {
        speaking ? nowMs - speechStartAt : 0
    }

    func reset() {
        speaking = false
    }

    /// Mark speech as in-progress without emitting (used when a capture
    /// starts from a barge-in: the normal VAD wasn't fed while speaking,
    /// but her voice is already going — silence from here must end it).
    func forceSpeaking(nowMs: Double) {
        speaking = true
        speechStartAt = nowMs
        lastSpeechAt = nowMs
    }
}

/// A stricter VAD used while the AI is speaking: requires louder audio
/// (echo guard — the speaker feeds back into the mic) before it counts.
final class BargeInVad: EnergyVad {
    override init(config: VadConfig) {
        var c = config
        c.speechThresholdDb += config.bargeInExtraDb
        super.init(config: c)
    }
}
