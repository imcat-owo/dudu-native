import Foundation

// MARK: - Duplex turn-taking state machine. PURE — no timers, no audio, no network.
//
// States: listening → capturing → thinking → speaking → listening …
// Barge-in: speaking + sustained user speech → cancel speech → capturing.
//
// The engine decides; VoiceCallSession executes via adapters.
// Every transition that carries words appends to the transcript.
//
// Ported from ~/workspace/openmuse/apps/mobile/src/voice-call/turn-engine.ts.

enum EngineEvent: Sendable {
    case vadSpeechStart
    case vadSpeechEnd
    case bargeIn
    case captureTimeout
    case sttDone(text: String)
    case sttEmpty
    case sttError(error: String)
    case llmDone(text: String)
    case llmError(error: String)
    case ttsQueueEmpty
    case endCall
    /// Mute pressed mid-capture: abandon the capture, back to listening.
    case userAbort
    /// WaveformKey press-and-hold: force a capture (barge-in if speaking).
    case pushToTalkStart
    /// WaveformKey released: end the forced capture and transcribe.
    case pushToTalkEnd
}

enum EngineAction: Sendable {
    case startCapture
    case stopCaptureTranscribe
    case think(userText: String)
    case speak(sentences: [String])
    case cancelSpeech
    case backToListening
    case callEnded(reason: String)
}

final class DuplexTurnEngine: @unchecked Sendable {

    private var turnState: TurnState = .listening
    private var transcript: [CallTranscriptEntry] = []
    private var stats = CallStats()
    private var ended = false
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        self.stats.startedAt = now()
    }

    var state: TurnState { turnState }
    var isEnded: Bool { ended }

    func getTranscript() -> [CallTranscriptEntry] { transcript }
    func getStats() -> CallStats { stats }

    private func log(role: CallRole, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        transcript.append(CallTranscriptEntry(at: now(), role: role, text: t))
    }

    @discardableResult
    func dispatch(_ event: EngineEvent) -> [EngineAction] {
        guard !ended else { return [] }
        var actions: [EngineAction] = []
        func end(_ reason: String) -> [EngineAction] {
            ended = true
            stats.endedAt = now()
            return [.callEnded(reason: reason)]
        }

        switch event {
        case .endCall:
            return end("user-ended")

        case .userAbort:
            if turnState == .capturing {
                turnState = .listening
                actions.append(.backToListening)
            }
            return actions

        case .pushToTalkStart:
            // Explicit hold: she takes the turn NOW, even mid-speech.
            if turnState == .speaking {
                stats.bargeIns += 1
                turnState = .capturing
                actions.append(.cancelSpeech)
                actions.append(.startCapture)
            } else if turnState == .listening {
                turnState = .capturing
                actions.append(.startCapture)
            }
            return actions

        case .pushToTalkEnd:
            if turnState == .capturing {
                turnState = .thinking
                actions.append(.stopCaptureTranscribe)
            }
            return actions

        case .vadSpeechStart:
            // Barge-in: she talks over the AI → cancel speech, take the turn.
            if turnState == .speaking {
                stats.bargeIns += 1
                turnState = .capturing
                actions.append(.cancelSpeech)
                actions.append(.startCapture)
            } else if turnState == .listening {
                turnState = .capturing
                actions.append(.startCapture)
            }
            return actions

        case .bargeIn:
            // Session-level barge-in (sustained speech while speaking).
            if turnState == .speaking {
                stats.bargeIns += 1
                turnState = .capturing
                actions.append(.cancelSpeech)
                actions.append(.startCapture)
            }
            return actions

        case .vadSpeechEnd, .captureTimeout:
            if turnState == .capturing {
                turnState = .thinking
                actions.append(.stopCaptureTranscribe)
            }
            return actions

        case .sttDone(let text):
            guard turnState == .thinking else { return actions }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                // Heard nothing usable — back to listening, no phantom turn.
                turnState = .listening
                actions.append(.backToListening)
                return actions
            }
            log(role: .user, text: t)
            stats.turns += 1
            actions.append(.think(userText: t))
            return actions

        case .sttEmpty:
            if turnState == .thinking {
                turnState = .listening
                actions.append(.backToListening)
            }
            return actions

        case .sttError(let error):
            // Loud failure, not a fake turn: tell her we didn't catch that.
            if turnState == .thinking {
                turnState = .listening
                log(role: .assistant, text: "[没听清：\(error)]")
                actions.append(.backToListening)
            }
            return actions

        case .llmDone(let text):
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                turnState = .listening
                actions.append(.backToListening)
                return actions
            }
            log(role: .assistant, text: t)
            turnState = .speaking
            actions.append(.speak(sentences: splitCallSentences(t)))
            return actions

        case .llmError(let error):
            if turnState == .thinking {
                turnState = .listening
                log(role: .assistant, text: "[刚才走神了：\(error)]")
                actions.append(.backToListening)
            }
            return actions

        case .ttsQueueEmpty:
            if turnState == .speaking {
                turnState = .listening
                actions.append(.backToListening)
            }
            return actions
        }
    }
}
