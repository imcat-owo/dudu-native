//
//  DuduVoiceBubblePlayer.swift
//  Dudu
//
//  P7 PORT (2026-10-07): minimal engine-owned stand-in for OpenMinis'
//  Views/Chat/Media/AudioPlayback.swift `GlobalAudioPlayer` (546-line
//  ObservableObject — Views/Phase C, NOT ported).
//
//  The chat core auto-plays voice bubbles after sending them
//  (AIChatViewModel+ConcurrentTools) and PlayerOffloadBridge drives audio
//  sessions through it. Deleting those calls would drop features; this
//  preserves them with plain AVAudioPlayer. When Phase C ports the full
//  AudioPlayback view layer, it may replace this with the real player —
//  but it must NOT redeclare this type (single definition).
//

import AVFoundation
import Foundation

/// Minimal audio playback for the chat core and offloads.
/// Not the full GlobalAudioPlayer (no generation tracking, no UI state,
/// no Control Center integration) — just enough that audio features work.
final class DuduVoiceBubblePlayer {
    static let shared = DuduVoiceBubblePlayer()

    private var player: AVAudioPlayer?

    private init() {}

    /// Play a file, replacing any current playback.
    func play(url: URL) {
        // Match GlobalAudioPlayer.play(url:): suspend the silent-audio
        // keep-alive so media gets full volume (MainActor-isolated).
        Task { @MainActor in
            BackgroundKeepAliveManager.shared.suspendSilentAudioForMedia()
        }
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

    /// Toggle between playing and paused.
    func togglePlayPause() {
        guard let p = player else { return }
        if p.isPlaying {
            p.pause()
        } else {
            p.play()
        }
    }

    /// Seek to a time in seconds.
    func seek(to seconds: TimeInterval) {
        player?.currentTime = seconds
    }

    /// Stop playback and release the player.
    func stop() {
        player?.stop()
        player = nil
    }

    /// Whether audio is currently playing.
    var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    /// Duration of the loaded file in seconds, 0 if none.
    var duration: TimeInterval {
        player?.duration ?? 0
    }

    /// Current playback position in seconds, 0 if none.
    var currentTime: TimeInterval {
        player?.currentTime ?? 0
    }
}
