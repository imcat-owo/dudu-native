import Foundation

// MARK: - Voice call (realtime duplex) — shared types. PURE, no AV imports.
//
// A "call" here is a full-duplex voice conversation inside the app:
// mic → VAD → STT → LLM → streaming TTS → speaker, with barge-in
// (she can interrupt the AI mid-sentence, like Pipecat's InterruptionFrame).
//
// Ported from ~/workspace/openmuse/apps/mobile/src/voice-call/types.ts —
// the old Dudu's call model, kept 1:1 so behavior matches what she approved.

/// Lifecycle of one call.
enum CallPhase: String, Sendable {
    case idle
    case outgoing    // she tapped "call"
    case ringing     // AI-proposed call, waiting for her accept/decline
    case connecting  // mic warming up
    case live        // duplex conversation running
    case ending
    case ended
}

/// Turn state inside a live call.
enum TurnState: String, Sendable {
    case listening
    case capturing
    case thinking
    case speaking
}

/// Energy VAD config. Adapted from the Pipecat/LiveKit pattern
/// (stop_secs, min-words interruption gate) to dB metering, which reports
/// dB as a negative number (silence ≈ -70, speech ≈ -45..-10 on iOS PCM).
struct VadConfig: Sendable {
    /// Metering dB above this counts as speech.
    var speechThresholdDb: Float = -38
    /// Silence this long ends the user's turn (Pipecat's stop_secs).
    var silenceEndMs: Double = 900
    /// Speech must last this long to count as barge-in (MinWords-like gate).
    var minSpeechMs: Double = 450
    /// Safety cap on a single capture.
    var maxTurnMs: Double = 60_000
    /// Extra dB required for barge-in while the AI is speaking (echo guard).
    var bargeInExtraDb: Float = 10

    static let standard = VadConfig()
}

/// One line of the call transcript.
struct CallTranscriptEntry: Sendable, Identifiable {
    let id = UUID()
    let at: Date
    let role: CallRole
    let text: String
}

enum CallRole: String, Sendable {
    case user
    case assistant
}

/// One conversation turn for the LLM adapter.
struct CallTurn: Sendable {
    let role: CallRole
    let text: String
}

enum ProposalStatus: String, Sendable, Codable {
    case ringing
    case accepted
    case declined
    case missed
    case expired
}

/// An AI-proposed call. `reason` is the WHY shown to her — the consent basis.
struct CallProposal: Sendable, Codable, Identifiable {
    let id: String
    let personaId: String
    let personaName: String
    /// WHY the AI wants to call — shown to her, the consent basis.
    let reason: String
    let topic: String?
    let createdAt: Date
    var status: ProposalStatus
}

struct CallStats: Sendable {
    var turns: Int = 0
    var bargeIns: Int = 0
    var startedAt: Date = Date()
    var endedAt: Date?
}

/// Split reply text into speakable sentences (sentence-level TTS streaming).
/// Ported from the old Dudu's splitSentences (split after 。！？!?…).
func splitCallSentences(_ text: String) -> [String] {
    let enders: Set<Character> = ["。", "！", "？", "!", "?", "…"]
    var out: [String] = []
    var cur = ""
    for ch in text {
        cur.append(ch)
        if enders.contains(ch) {
            let t = cur.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(t) }
            cur = ""
        }
    }
    let tail = cur.trimmingCharacters(in: .whitespacesAndNewlines)
    if !tail.isEmpty { out.append(tail) }
    return out
}
