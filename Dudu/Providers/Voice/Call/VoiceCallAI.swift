import Foundation

// MARK: - Voice call AI adapters (STT / LLM)
//
// Production wiring into the existing pipelines — no duplicates:
//   STT: her configured voice-input chain (cloud candidates in order),
//        falling back to the offline System recognizer.
//        (Convention mirrors VoiceProviderResolver: "nil → caller uses the
//        offline System provider".)
//   LLM: one-shot through LLMProviderFactory — the SAME factory the chat
//        agent loop and the model-use bridge resolve providers from.
//   TTS: spoken through VoiceOutputPlayer (see VoiceCallSession).
//
// Everything here throws loudly on failure. Nothing is faked: an empty or
// failed STT result is surfaced as stt-empty/stt-error, never invented text.

@MainActor
enum VoiceCallAI {

    private static let logger = AppLogger(category: "VoiceCall")

    // MARK: - STT

    /// Transcribe a captured utterance WAV to text.
    static func transcribe(wav: Data) async throws -> String {
        let candidates = VoiceProviderResolver.resolvedInputCandidates()
        var lastError: Error?
        for entry in candidates {
            guard let provider = VoiceProviderResolver.inputProvider(for: entry) else { continue }
            do {
                let req = VoiceInputRequest(
                    audioData: wav,
                    model: entry.model.id,
                    language: nil,
                    resolvedModel: entry.model)
                let resp = try await provider.transcribe(req)
                logger.info("call STT ok via \(entry.model.displayName)")
                return resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                lastError = error
                logger.warning("call STT failed via \(entry.model.displayName): \(error.localizedDescription)")
            }
        }
        // Fallback: offline System recognizer (needs Speech permission).
        guard await SystemVoiceProvider.ensureSpeechAuthorization() else {
            throw lastError ?? VoiceProviderError.unsupported("Speech recognition permission not granted")
        }
        let resp = try await VoiceProviderFactory.systemProvider()
            .transcribe(VoiceInputRequest(audioData: wav))
        return resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - LLM

    /// Voice-call system prompt: the persona's own voice plus spoken-style
    /// constraints. The reply is spoken aloud via TTS — formatting, lists and
    /// long paragraphs don't survive speech.
    ///
    /// Ported from the old Dudu's buildCallSystemPrompt (instances.ts).
    static func callSystemPrompt(personaName: String) -> String {
        """
        你是\(personaName)。

        You are on a LIVE VOICE CALL with her. Your reply will be spoken aloud via TTS.
        Hard rules for voice:
        - Keep every reply SHORT: 1-3 sentences, like spoken conversation. Never a wall of text.
        - Plain text only: no markdown, no lists, no emoji, no stage directions.
        - Reply in HER language (the language she just used).
        - If you didn't understand, say so briefly and ask her to repeat — never bluff.
        """
    }

    /// One-shot reply through the existing provider pipeline.
    static func reply(history: [CallTurn], entry: ModelEntry, personaName: String) async throws -> String {
        let provider = try await LLMProviderFactory.makeProvider(for: entry)
        let messages = history.map { turn in
            LLMMessage(
                role: turn.role == .user ? .user : .assistant,
                content: turn.text)
        }
        let response = try await provider.sendMessage(
            messages: messages,
            systemPrompt: callSystemPrompt(personaName: personaName),
            maxTokens: 400,
            temperature: 0.7)
        return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - TTS preflight

    /// Whether anything can actually synthesize speech right now — mirrors
    /// VoiceOutputPlayer's own candidate resolution. The call refuses to
    /// start silent: a call she can't hear is a fake call.
    static func ttsAvailable() -> Bool {
        VoiceOutputPlayer.shared.hasUsableOutputTargets
    }
}
