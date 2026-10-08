import Foundation
import AVFoundation
import SwiftUI

// MARK: - Built-in TTS presets (kelivo-style)
//
// [T-tts-builtin-presets 10-08] Kelivo's TTS page does two things: (1) free-form
// custom service config (custom URL + key + voice/model — already covered by
// TTSServiceStore), and (2) built-in presets of free high-quality Chinese
// voices that work out of the box with NO key. This file adds (2).
//
// The native engine has no keyless network vendor (no edge-tts port), so the
// presets are curated Apple system voices — free, offline, no credential —
// with the best installed Chinese voice pre-selected by default. One preset is
// ALWAYS selected unless the user explicitly picks "不用内置音色", in which
// case the read-aloud chain falls through exactly like before (service →
// Model-Group → System), so the old behavior is one tap away.
//
// Selection is mutually exclusive with an explicit custom-service selection:
// picking a preset clears TTSServiceStore's selectedServiceId (so the new
// choice actually takes effect); tapping a service row re-selects there.
// Keys are never involved here — presets need none — and nothing is logged.

// MARK: - Preset model

/// One built-in voice preset: a pinned Apple TTS voice (or auto-by-language).
struct TTSBuiltInPreset: Identifiable {
    let id: String
    let title: String
    let detail: String
    /// AVSpeechSynthesisVoice identifier pinned by this preset. nil = let the
    /// system pick by language (SystemVoiceProvider.resolveVoice's fallback).
    let voiceIdentifier: String?
    /// Short sentence spoken by the 试听 button. Empty = the "off" row, which
    /// has nothing to play (its 试听 button is honestly disabled).
    let sampleText: String

    var previewable: Bool { !sampleText.isEmpty }
}

// MARK: - Preset store

/// Built-in preset list + which one is selected. @MainActor because the list is
/// built from AVSpeechSynthesisVoice.speechVoices() (UI-thread roster) and the
/// settings UI reads it directly.
@MainActor
final class TTSBuiltInPresetStore {
    static let shared = TTSBuiltInPresetStore()

    private static let selectedKey = "tts.selectedPresetId.v1"
    static let defaultPresetId = "preset-auto"
    static let offPresetId = "preset-off"

    private init() {}

    /// Curated list, rebuilt on each access (cheap: a filter over the voice
    /// roster) so freshly downloaded Enhanced/Premium packs show up without a
    /// restart.
    var presets: [TTSBuiltInPreset] {
        Self.buildPresets()
    }

    /// The selected preset id, defaulting to `preset-auto` — one preset is
    /// selected BY DEFAULT, no paid key needed out of the box.
    var selectedPresetId: String {
        UserDefaults.standard.string(forKey: Self.selectedKey) ?? Self.defaultPresetId
    }

    /// The selected preset, or nil when the user picked "不用内置音色" — the
    /// read-aloud chain then falls through like before this feature existed.
    var selectedPreset: TTSBuiltInPreset? {
        let id = selectedPresetId
        if id == Self.offPresetId { return nil }
        let list = presets
        return list.first { $0.id == id } ?? list.first { $0.id == Self.defaultPresetId }
    }

    /// Select a preset. Picking a real preset releases any explicit
    /// custom-service selection (the two can't both be "the" target);
    /// picking "off" leaves the service selection alone so a configured
    /// service keeps working.
    func setSelectedPresetId(_ id: String) {
        UserDefaults.standard.set(id, forKey: Self.selectedKey)
        if id != Self.offPresetId {
            TTSServiceStore.shared.setSelectedServiceId(nil)
        }
        NotificationCenter.default.post(name: .ttsServicesChanged, object: nil)
    }

    // MARK: List building

    private static func baseLang(_ voice: AVSpeechSynthesisVoice) -> String {
        String(voice.language.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
    }

    private static func qualityRank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
        switch q {
        case .premium:  return 0
        case .enhanced: return 1
        default:        return 2
        }
    }

    private static func qualityWord(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium:  return " · 高品质版"
        case .enhanced: return " · 增强版"
        default:        return ""
        }
    }

    static func buildPresets() -> [TTSBuiltInPreset] {
        let sample = SystemVoiceProvider.sampleText(forLanguage: "zh")
        // Best-installed-first so "first(where:)" below always prefers the
        // Enhanced/Premium pack over the compact default.
        let zhVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { baseLang($0) == "zh" }
            .sorted { qualityRank($0.quality) < qualityRank($1.quality) }

        var rows: [TTSBuiltInPreset] = []

        // 1. Auto — the best Chinese voice on THIS device. Always present, and
        //    the default selection: out of the box the app reads aloud with a
        //    curated good voice, no key required.
        rows.append(TTSBuiltInPreset(
            id: defaultPresetId,
            title: "中文自动",
            detail: "用这台手机上最好的中文语音",
            voiceIdentifier: zhVoices.first?.identifier,
            sampleText: sample))

        // 2/3. Curated personae the engine already ships: Tingting (female)
        //    and Lisheng (male), each pinned to their best installed quality.
        //    Only listed when actually installed — never a dead row.
        if let tingting = zhVoices.first(where: { $0.identifier.localizedCaseInsensitiveContains("tingting") }) {
            rows.append(TTSBuiltInPreset(
                id: "preset-tingting",
                title: "婷婷",
                detail: "女声\(qualityWord(tingting))",
                voiceIdentifier: tingting.identifier,
                sampleText: sample))
        }
        if let lisheng = zhVoices.first(where: { $0.identifier.localizedCaseInsensitiveContains("lisheng") }) {
            rows.append(TTSBuiltInPreset(
                id: "preset-lisheng",
                title: "李生",
                detail: "男声\(qualityWord(lisheng))",
                voiceIdentifier: lisheng.identifier,
                sampleText: sample))
        }

        // 4. Off — restores the pre-preset fall-through (service → group →
        //    System). Kept so nobody is locked into a built-in voice.
        rows.append(TTSBuiltInPreset(
            id: offPresetId,
            title: "不用内置音色",
            detail: "只用你自己配的语音服务",
            voiceIdentifier: nil,
            sampleText: ""))

        return rows
    }
}

// MARK: - Test playback (试听)

/// Drives the per-row 试听 buttons in TTS settings: synthesizes a short sample
/// sentence and plays it through the shared TTSPreviewPlayer (which stops any
/// previous preview first — two rows can never talk over each other).
///
/// Honest states only: idle / playing (tap again to stop) / failed with a
/// plain-language reason. A row whose synthesis genuinely can't run (custom
/// service with no key) gets a disabled button + reason instead — never fake
/// playback.
@MainActor
final class TTSVoiceTestPlayer: ObservableObject {
    static let shared = TTSVoiceTestPlayer()

    enum State { case idle, playing, failed }

    @Published private(set) var stateByKey: [String: State] = [:]
    @Published private(set) var failedReasonByKey: [String: String] = [:]

    private var task: Task<Void, Never>?

    private init() {}

    func state(forKey key: String) -> State { stateByKey[key] ?? .idle }

    func failedReason(forKey key: String) -> String { failedReasonByKey[key] ?? "" }

    static func presetKey(_ preset: TTSBuiltInPreset) -> String { "preset:\(preset.id)" }
    static func serviceKey(_ service: TTSServiceOptions) -> String { "service:\(service.id)" }

    /// 全停：取消在播/在合成的试听，清掉所有行的状态。视图退出时用。
    func stop() {
        task?.cancel()
        task = nil
        TTSPreviewPlayer.shared.stop()
        stateByKey = [:]
        failedReasonByKey = [:]
    }

    /// 只停一行：取消在播/在合成的试听，只清这一行的状态，其它行的失败
    /// 原因等状态原样保留。试听是独占的，被停掉时还标着 .playing 的其它
    /// 行一并回 .idle，免得界面撒谎。
    func stop(key: String) {
        task?.cancel()
        task = nil
        TTSPreviewPlayer.shared.stop()
        stateByKey.removeValue(forKey: key)
        failedReasonByKey.removeValue(forKey: key)
        for other in stateByKey.keys where other != key && stateByKey[other] == .playing {
            stateByKey[other] = .idle
        }
    }

    /// Whether a custom service row can be previewed — and the plain reason
    /// when it can't. Presets never need a key, so they're always testable.
    func serviceTestability(_ service: TTSServiceOptions) -> (ok: Bool, reason: String) {
        if !TTSServiceStore.shared.hasAPIKey(for: service) {
            return (false, "先配好密钥才能试听")
        }
        if TTSProviderBridge.provider(for: service) == nil {
            return (false, "这个服务商现在试听不了")
        }
        return (true, "")
    }

    /// Preview a built-in preset: render the sample with the pinned system
    /// voice (on-device, no network, no key) and play it.
    func testPreset(_ preset: TTSBuiltInPreset) {
        guard preset.previewable else { return }  // "off" row: nothing to play
        let key = Self.presetKey(preset)
        if state(forKey: key) == .playing { stop(key: key); return }
        begin(key: key) {
            let request = VoiceOutputRequest(
                input: preset.sampleText,
                model: preset.voiceIdentifier,
                speed: VoiceOutputPreferences.speedMultiplier)
            return try await SystemVoiceProvider.shared.synthesize(request)
        }
    }

    /// Preview a custom service: real synthesis through the vendor with the
    /// stored key. Fails honestly (failed state + reason) when the network or
    /// the vendor rejects it.
    func testService(_ service: TTSServiceOptions) {
        let key = Self.serviceKey(service)
        if state(forKey: key) == .playing { stop(key: key); return }
        guard serviceTestability(service).ok,
              let provider = TTSProviderBridge.provider(for: service) else {
            stateByKey[key] = .failed
            failedReasonByKey[key] = serviceTestability(service).reason
            return
        }
        begin(key: key) {
            let request = TTSProviderBridge.request(
                for: service,
                text: SystemVoiceProvider.sampleText(forLanguage: "zh"))
            return try await provider.synthesize(request)
        }
    }

    // MARK: Internals

    private func begin(key: String, synth: @escaping () async throws -> Data) {
        stop(key: key)
        stateByKey[key] = .playing
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await synth()
                try Task.checkCancellation()
                try TTSPreviewPlayer.shared.play(data) { [weak self] in
                    self?.stateByKey[key] = .idle
                }
            } catch is CancellationError {
                // stop() already cleared the state; nothing to show.
            } catch {
                self.stateByKey[key] = .failed
                self.failedReasonByKey[key] = Self.friendlyReason(error)
                VoiceLog.log("TTS test playback failed (\(key)): \(error)")
            }
        }
    }

    /// Plain-language failure reason — no status codes, no jargon.
    private static func friendlyReason(_ error: Error) -> String {
        let desc = (error as NSError).localizedDescription.lowercased()
        if desc.contains("401") || desc.contains("unauthorized") || desc.contains("forbidden") {
            return "密钥不对，被服务商拦下了，检查一下密钥再试"
        }
        if error is URLError {
            return "网络没连上，检查一下网络再试"
        }
        return "试听失败了，稍后再试试"
    }
}
