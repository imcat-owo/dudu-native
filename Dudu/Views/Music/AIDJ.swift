import Foundation

// MARK: - AIDJ · the DJ engine (D19, 2026-10-07)
//
// The AI is the DJ: from dialog it writes playback intents into the store
// (dj_play / dj_pause / dj_skip / dj_restart — see MusicDJTools), and this
// engine applies them to the real audio sources. It also owns the "DJ 为你
// 排队" heuristics.
//
// Honesty rule (her law): the pick/queue suggestions are SIMPLE HEURISTICS
// over play history — play counts, 我们的歌, together-listen dates. They are
// labeled as heuristics in the UI, never as "AI 懂你". Her mood (from
// 我们的空间) is shown as context next to the picks, never used to pretend
// the DJ "understands" her feelings.

// MARK: - Recommendation (heuristic, labeled)

struct DJRecommendation: Identifiable {
    var id: String { track.id }
    var track: MusicTrack
    var score: Double
    /// Human reasons, e.g. ["我们的歌", "播了 12 次", "10月3日一起听过"].
    var reasons: [String]
}

enum DJHeuristics {
    /// Rank playable tracks by play history. Pure — easy to reason about.
    /// - ours: +10 ("我们的歌" first — she decided these matter)
    /// - each play: +1.5, capped at +15
    /// - each together-listen: +3, capped at +12
    /// - unplayable tracks (no audio): excluded, never suggested
    static func recommend(
        tracks: [MusicTrack],
        oursIds: Set<String>,
        togetherListens: [TogetherListen],
        limit: Int = 5
    ) -> [DJRecommendation] {
        let listenCount: [String: Int] = Dictionary(
            grouping: togetherListens, by: { $0.trackId }
        ).mapValues { $0.count }
        let recentListenDates: [String: Date] = Dictionary(
            grouping: togetherListens, by: { $0.trackId }
        ).mapValues { $0.map { $0.date }.max() ?? .distantPast }

        var out: [DJRecommendation] = []
        for t in tracks where t.isPlayable {
            var score = 0.0
            var reasons: [String] = []
            if oursIds.contains(t.id) {
                score += 10
                reasons.append("我们的歌")
            }
            let playScore = min(Double(t.playCount) * 1.5, 15)
            if playScore > 0 {
                score += playScore
                reasons.append("播了 \(t.playCount) 次")
            }
            if let n = listenCount[t.id], n > 0 {
                let s = min(Double(n) * 3, 12)
                score += s
                if let d = recentListenDates[t.id] {
                    reasons.append("\(fmtMusicDay(d))一起听过")
                } else {
                    reasons.append("一起听过 \(n) 次")
                }
            }
            if score > 0 {
                out.append(DJRecommendation(track: t, score: score, reasons: reasons))
            }
        }
        return out.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }
}

// MARK: - AIDJ engine

/// Owns the active audio source, applies DJ intents, and drives the
/// heuristic recommendations. Single owner of "what is sounding right now".
@MainActor
final class AIDJ: ObservableObject {
    static let shared = AIDJ()

    @Published private(set) var status = SourceStatus(playing: false, position: 0, duration: nil, trackId: nil)
    @Published private(set) var currentTrack: MusicTrack?
    @Published private(set) var appleAuthState: SourceAuthState = .unknown
    @Published private(set) var recommendations: [DJRecommendation] = []
    /// Last honest, her-language error (shown in the room, never silent).
    @Published private(set) var lastError: String?

    private let store = MusicStore.shared
    private var activeSource: (any MusicSource)?
    private var statusUnsub: (() -> Void)?
    /// True while the current track is sounding (used for finish detection).
    private var wasPlaying = false

    private init() {
        currentTrack = store.getNowPlaying()
        refreshRecommendations()
        Task { await refreshAppleAuthState() }
    }

    // ---------- transport ----------

    /// Play a track for real. Throws honest, her-language errors.
    func playTrack(_ track: MusicTrack) async throws {
        lastError = nil
        let source = MusicSourceRegistry.source(for: track.source)
        let ref: String
        switch track.source {
        case .local:
            guard track.isPlayable else {
                throw MusicError.notPlayable("「\(track.title)」还没有音频。先在听歌房里给它导入音频文件。")
            }
            ref = track.audioUri
        case .appleMusic:
            let auth = await source.getAuthState()
            guard auth == .authorized else {
                throw MusicError.sourceUnavailable("Apple Music 还没连上：" + auth.hint)
            }
            ref = track.sourceRef
        }
        let st = SourceTrack(id: track.id, title: track.title, artist: track.artist,
                             artworkUrl: track.artworkUrl, duration: nil,
                             source: track.source, playableRef: ref)
        do {
            try await source.load(st)
            switchSource(to: source)
            try await source.play()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
        currentTrack = track
        wasPlaying = true
        store.setNowPlaying(track.id)   // records the together-listen date when 一起听 is on
        store.bumpPlayCount(track.id)
        refreshRecommendations()
    }

    func togglePlayPause() async {
        guard let source = activeSource else {
            // Nothing loaded: resume the last track if there is one.
            if let t = currentTrack ?? store.getNowPlaying() {
                try? await playTrack(t)
            }
            return
        }
        if status.playing {
            await source.pause()
        } else {
            try? await source.play()
        }
    }

    /// Next: queue head first, then the next song in the shared playlist,
    /// then stop honestly (never loops silently).
    func skip() async {
        if let nextId = store.shiftQueue(), let t = store.getTrack(nextId) {
            try? await playTrack(t)
            return
        }
        let shared = store.playlistTracks(MusicStore.sharedPlaylistId)
        if let cur = currentTrack, let i = shared.firstIndex(where: { $0.id == cur.id }),
           i + 1 < shared.count {
            try? await playTrack(shared[i + 1])
            return
        }
        await stopPlayback()
    }

    func restart() async {
        guard let source = activeSource else { return }
        await source.seekTo(0)
        try? await source.play()
    }

    func seek(to seconds: Double) async {
        await activeSource?.seekTo(seconds)
    }

    func stopPlayback() async {
        if let source = activeSource { await source.release() }
        switchSource(to: nil)
        currentTrack = nil
        wasPlaying = false
        store.setNowPlaying(nil)
        status = SourceStatus(playing: false, position: 0, duration: nil, trackId: nil)
    }

    // ---------- DJ intents (written by the AI from dialog) ----------

    /// Applies the pending intent if it is fresh and unapplied.
    /// Called by the room view whenever the store's intent changes.
    func applyIntentIfPending() async {
        guard let intent = store.intent else { return }
        if let applied = store.appliedIntentAt, intent.at <= applied { return }
        if isIntentStale(intent) {
            store.markIntentApplied(intent.at)  // stale: drop, never replay
            return
        }
        switch intent.action {
        case .play:
            if let tid = intent.trackId, let t = store.getTrack(tid) {
                try? await playTrack(t)
            } else {
                await togglePlayPause()  // resume
            }
        case .pause:
            if status.playing { await activeSource?.pause() }
        case .skip:
            await skip()
        case .restart:
            await restart()
        }
        store.markIntentApplied(intent.at)
    }

    // ---------- DJ picks (heuristics, honestly labeled) ----------

    func refreshRecommendations() {
        let ours = Set(store.getPlaylist(MusicStore.oursPlaylistId)?.trackIds ?? [])
        recommendations = DJHeuristics.recommend(
            tracks: store.tracks,
            oursIds: ours,
            togetherListens: store.togetherListens,
            limit: 5
        )
    }

    /// "DJ 为你排队": enqueues the top heuristic picks. Real action.
    func djQueueTopPicks() {
        let ours = Set(store.getPlaylist(MusicStore.oursPlaylistId)?.trackIds ?? [])
        let picks = DJHeuristics.recommend(
            tracks: store.tracks, oursIds: ours,
            togetherListens: store.togetherListens, limit: 5
        )
        for p in picks { try? store.enqueue(p.track.id) }
    }

    /// Her mood today, for display next to the picks (context, not input to
    /// any "understanding" — the heuristics stay play-history only).
    var herMoodToday: String? {
        guard let m = OurSpaceStore.shared.herMood,
              !m.mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Calendar.current.isDateInToday(m.updatedAt) else { return nil }
        return m.mood
    }

    // ---------- Apple Music ----------

    func refreshAppleAuthState() async {
        appleAuthState = await MusicSourceRegistry.source(for: .appleMusic).getAuthState()
    }

    /// Runs the MusicKit authorization flow. Returns the resulting state.
    @discardableResult
    func appleAuthorize() async -> SourceAuthState {
        let state = await MusicSourceRegistry.source(for: .appleMusic).authorize()
        appleAuthState = state
        return state
    }

    /// Catalog search for the AI's 点歌 flow (honest errors propagate).
    func appleSearch(query: String, limit: Int = 10) async throws -> [SourceTrack] {
        try await MusicSourceRegistry.source(for: .appleMusic).search(query: query, limit: limit)
    }

    // ---------- internals ----------

    private func switchSource(to source: (any MusicSource)?) {
        if activeSource?.id != source?.id {
            statusUnsub?()
            statusUnsub = nil
        }
        activeSource = source
        if let source, statusUnsub == nil {
            statusUnsub = source.onStatus { [weak self] s in
                Task { @MainActor [weak self] in self?.handleStatus(s) }
            }
        }
    }

    private func handleStatus(_ s: SourceStatus) {
        let finished = wasPlaying && !s.playing && s.position == 0
            && s.trackId == currentTrack?.id
        status = s
        wasPlaying = s.playing
        if finished {
            Task { await skip() }  // natural finish → next song
        }
    }
}
