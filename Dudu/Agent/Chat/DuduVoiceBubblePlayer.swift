//
//  DuduVoiceBubblePlayer.swift
//  Dudu
//
//  P7 PORT (2026-10-07): minimal engine-owned stand-in for OpenMinis'
//  Views/Chat/Media/AudioPlayback.swift `GlobalAudioPlayer` (546-line
//  ObservableObject — Views/Phase C, NOT ported).
//
//  The chat core auto-plays voice bubbles after sending them
//  (AIChatViewModel+ConcurrentTools). Deleting the call would drop the
//  feature; this preserves it with plain AVAudioPlayer. When Phase C ports
//  the full AudioPlayback view layer, it may replace this with the real
//  player — but it must NOT redeclare this type (single definition).
//

import AVFoundation
import Foundation

/// Minimal voice-bubble playback for the chat core.
/// Not the full GlobalAudioPlayer (no generation tracking, no UI state) —
/// just enough that sent voice bubbles still auto-play.
enum DuduVoiceBubblePlayer {
    private static var player: AVAudioPlayer?

    static func play(url: URL) {
        // Match GlobalAudioPlayer.play(url:): suspend the silent-audio
        // keep-alive so media gets full volume.
        BackgroundKeepAliveManager.shared.suspendSilentAudioForMedia()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            // Best-effort: the bubble was already sent; playback failing
            // must not break the turn.
        }
    }
}
