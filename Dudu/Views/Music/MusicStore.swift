import Combine
import Foundation

// MARK: - MusicStore · 听歌房 data layer (D19, 2026-10-07)
//
// Ported from the old Dudu spec (openmuse/apps/mobile/src/music/store.ts):
// same model semantics — shared playlist, 我们的歌, per-song comments,
// per-song memory notes, together-listen dates ("X月X日一起听过"),
// DJ intents (the AI writes them from dialog, the room UI applies them),
// together-listening mode, tap-a-lyric context, LRC parsing.
//
// Differences from the old spec (native realities):
// - Persistence is UserDefaults JSON (device-local), same discipline as
//   OurSpaceStore. The music user token / developer token are NOT here —
//   they live in the keychain (see AppleMusicSource / MusicKeychain).
// - Hook points for the AI engine (all public, @MainActor):
//     MusicStore.shared.addTrack(...)        — 点歌 from dialog
//     MusicStore.shared.sendIntent(...)      — dj_play / dj_pause / ...
//     MusicStore.shared.markOurs(trackId:)    — 我们的歌 (persists across sessions)
//     MusicStore.shared.setTogether(...)      — 一起听 mode
//     MusicStore.shared.togetherListenDates / countTogetherListens
//   Everything publishes through @Published so the UI refreshes live.

// MARK: - Models

/// Who added / wrote something: her or the AI.
enum MusicAuthor: String, Codable, CaseIterable {
    case her
    case ai

    var label: String {
        switch self {
        case .her: return "她"
        case .ai: return "小梦"
        }
    }
}

/// Where a track plays from. Pluggable — future sources (NetEase via MCP,
/// …) add a raw value here; the store, sources and UI all key off it.
enum TrackSource: String, Codable, CaseIterable {
    case local
    case appleMusic = "apple-music"

    var label: String {
        switch self {
        case .local: return "本地"
        case .appleMusic: return "Apple Music"
        }
    }
}

/// One timed lyric line. `time` is seconds from track start.
struct LyricLine: Codable, Equatable {
    var time: Double
    var text: String
}

struct MusicTrack: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var source: TrackSource
    /// Source-scoped playable ref. local: unused (audioUri is the ref).
    /// apple-music: the Apple Music catalog song id.
    var sourceRef: String
    /// Local audio file path (app documents) or URL. Empty = no audio yet —
    /// the UI must say so honestly, never play silence.
    var audioUri: String
    var coverUri: String
    var artworkUrl: String
    var lyrics: [LyricLine]
    var addedBy: MusicAuthor
    var playCount: Int
    var createdAt: Date

    /// True when the track can actually produce sound.
    var isPlayable: Bool {
        if source == .appleMusic { return !sourceRef.trimmingCharacters(in: .whitespaces).isEmpty }
        return !audioUri.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Explicit memberwise init: a custom init(from:) suppresses the
    /// synthesized one, and addTrack depends on this exact signature.
    init(
        id: String,
        title: String,
        artist: String,
        album: String,
        source: TrackSource,
        sourceRef: String,
        audioUri: String,
        coverUri: String,
        artworkUrl: String,
        lyrics: [LyricLine],
        addedBy: MusicAuthor,
        playCount: Int,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.source = source
        self.sourceRef = sourceRef
        self.audioUri = audioUri
        self.coverUri = coverUri
        self.artworkUrl = artworkUrl
        self.lyrics = lyrics
        self.addedBy = addedBy
        self.playCount = playCount
        self.createdAt = createdAt
    }

    /// Migration guard: old stored tracks may lack newer fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        artist = (try? c.decode(String.self, forKey: .artist)) ?? ""
        album = (try? c.decode(String.self, forKey: .album)) ?? ""
        source = (try? c.decode(TrackSource.self, forKey: .source)) ?? .local
        sourceRef = (try? c.decode(String.self, forKey: .sourceRef)) ?? ""
        audioUri = (try? c.decode(String.self, forKey: .audioUri)) ?? ""
        coverUri = (try? c.decode(String.self, forKey: .coverUri)) ?? ""
        artworkUrl = (try? c.decode(String.self, forKey: .artworkUrl)) ?? ""
        lyrics = (try? c.decode([LyricLine].self, forKey: .lyrics)) ?? []
        addedBy = (try? c.decode(MusicAuthor.self, forKey: .addedBy)) ?? .her
        playCount = (try? c.decode(Int.self, forKey: .playCount)) ?? 0
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
    }
}

enum PlaylistKind: String, Codable {
    case shared
    case ours
    case custom

    var label: String {
        switch self {
        case .shared: return "共享歌单"
        case .ours: return "我们的歌"
        case .custom: return "自建歌单"
        }
    }
}

struct MusicPlaylist: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var kind: PlaylistKind
    var trackIds: [String]
    var createdBy: MusicAuthor
    var createdAt: Date

    var displayName: String { kind == .custom ? name : kind.label }
}

struct MusicComment: Codable, Identifiable, Equatable {
    var id: String
    var trackId: String
    var author: MusicAuthor
    var text: String
    var createdAt: Date
}

struct MusicMemory: Codable, Identifiable, Equatable {
    var id: String
    var trackId: String
    var text: String
    var createdAt: Date
}

/// One "we listened to this together" date. `date` is midnight-normalized
/// (local day) so the UI can render "X月X日一起听过".
struct TogetherListen: Codable, Equatable {
    var trackId: String
    var date: Date
}

enum DjAction: String, Codable {
    case play
    case pause
    case skip
    case restart
}

/// Playback intent written by the AI (from dialog), consumed by the room UI.
/// The UI applies intents newer than the last applied one and ignores intents
/// older than `staleIntentInterval` — a stale intent (e.g. written before the
/// app was backgrounded) must never suddenly start music.
struct DjIntent: Codable, Equatable {
    var action: DjAction
    /// For "play": the track to play. Absent = resume current.
    var trackId: String?
    var at: Date
    var by: MusicAuthor
}

/// "拉我一起听" — shared listening session state.
struct TogetherState: Codable, Equatable {
    var active: Bool
    var startedAt: Date?
    var startedBy: MusicAuthor?
}

// MARK: - Pure helpers

/// Intents older than this are never executed.
let staleIntentInterval: TimeInterval = 5 * 60

/// Pure: true when the intent is too old to execute.
func isIntentStale(_ intent: DjIntent, now: Date = Date()) -> Bool {
    now.timeIntervalSince(intent.at) > staleIntentInterval
}

/// Parse LRC-ish lyrics into timed lines.
/// Accepts `[mm:ss.xx] text` and `[mm:ss] text`; ignores metadata tags like
/// `[ti:...]` / `[ar:...]` and blank lines. Sorted by time.
func parseLrc(_ text: String) -> [LyricLine] {
    var lines: [LyricLine] = []
    for raw in text.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("[") else { continue }
        guard let close = line.firstIndex(of: "]") else { continue }
        let stamp = String(line[line.index(after: line.startIndex)..<close])
        let body = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { continue }
        let parts = stamp.split(separator: ":")
        guard parts.count == 2, let min = Double(parts[0]) else { continue }
        let secParts = parts[1].split(whereSeparator: { $0 == "." || $0 == "," })
        guard let sec = Double(secParts[0]), sec < 60 else { continue }
        var frac = 0.0
        if secParts.count > 1, let f = Double(String(secParts[1]).padding(toLength: 3, withPad: "0", startingAt: 0)) {
            frac = f / 1000.0
        }
        lines.append(LyricLine(time: min * 60 + sec + frac, text: body))
    }
    return lines.sorted { $0.time < $1.time }
}

/// Index of the lyric line active at `position` seconds (-1 if none).
func lyricIndexAt(_ lyrics: [LyricLine], position: Double) -> Int {
    var idx = -1
    for (i, l) in lyrics.enumerated() {
        if l.time <= position + 0.05 { idx = i } else { break }
    }
    return idx
}

/// "10月3日" style day for together-listen history.
func fmtMusicDay(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.month, .day], from: date)
    return "\(c.month ?? 0)月\(c.day ?? 0)日"
}

// MARK: - Store

/// 听歌房 data layer. @MainActor, UserDefaults JSON, device-local.
@MainActor
final class MusicStore: ObservableObject {
    static let shared = MusicStore()

    static let sharedPlaylistId = "pl-shared"
    static let oursPlaylistId = "pl-ours"

    @Published private(set) var tracks: [MusicTrack] = []
    @Published private(set) var playlists: [MusicPlaylist] = []
    @Published private(set) var comments: [MusicComment] = []
    @Published private(set) var memories: [MusicMemory] = []
    @Published private(set) var queueIds: [String] = []
    @Published private(set) var nowPlayingId: String?
    @Published private(set) var intent: DjIntent?
    @Published private(set) var appliedIntentAt: Date?
    @Published private(set) var together: TogetherState = TogetherState(active: false, startedAt: nil, startedBy: nil)
    @Published private(set) var selectedLyric: String?
    @Published private(set) var togetherListens: [TogetherListen] = []

    private enum Key {
        static let tracks = "dudu.music.v1.tracks"
        static let playlists = "dudu.music.v1.playlists"
        static let comments = "dudu.music.v1.comments"
        static let memories = "dudu.music.v1.memories"
        static let queue = "dudu.music.v1.queue"
        static let nowPlaying = "dudu.music.v1.now"
        static let intent = "dudu.music.v1.intent"
        static let appliedIntentAt = "dudu.music.v1.intent.appliedAt"
        static let together = "dudu.music.v1.together"
        static let selectedLyric = "dudu.music.v1.selectedLyric"
        static let togetherListens = "dudu.music.v1.togetherListens"
    }

    private let defaults = UserDefaults.standard
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    init() {
        tracks = (load(Key.tracks, as: [MusicTrack].self) ?? []).sorted { $0.createdAt > $1.createdAt }
        playlists = load(Key.playlists, as: [MusicPlaylist].self) ?? []
        comments = load(Key.comments, as: [MusicComment].self) ?? []
        memories = load(Key.memories, as: [MusicMemory].self) ?? []
        queueIds = load(Key.queue, as: [String].self) ?? []
        nowPlayingId = load(Key.nowPlaying, as: String.self)
        intent = load(Key.intent, as: DjIntent.self)
        appliedIntentAt = load(Key.appliedIntentAt, as: Date.self)
        together = load(Key.together, as: TogetherState.self) ?? TogetherState(active: false, startedAt: nil, startedBy: nil)
        selectedLyric = load(Key.selectedLyric, as: String.self)
        togetherListens = load(Key.togetherListens, as: [TogetherListen].self) ?? []
        ensureDefaultPlaylists()
    }

    private func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    /// Re-read everything from UserDefaults, dropping in-memory state.
    /// Used after a restore rollback rewrote the raw values behind this store.
    func reloadFromDisk() {
        tracks = (load(Key.tracks, as: [MusicTrack].self) ?? []).sorted { $0.createdAt > $1.createdAt }
        playlists = load(Key.playlists, as: [MusicPlaylist].self) ?? []
        comments = load(Key.comments, as: [MusicComment].self) ?? []
        memories = load(Key.memories, as: [MusicMemory].self) ?? []
        togetherListens = load(Key.togetherListens, as: [TogetherListen].self) ?? []
        ensureDefaultPlaylists()
    }

    // MARK: - Backup / restore

    /// Keys that describe HER library — the durable, user-authored half.
    /// Transient playback state (queue order, now-playing, DJ intents, the
    /// live together state) is deliberately excluded: it describes a moment,
    /// not her collection.
    private static let backupKeys = [
        Key.tracks, Key.playlists, Key.comments, Key.memories, Key.togetherListens
    ]

    /// The durable keys, for the restore rollback snapshot.
    /// Nonisolated so the backup engine can read it off the MainActor.
    nonisolated static var backupKeysList: [String] {
        [Key.tracks, Key.playlists, Key.comments, Key.memories, Key.togetherListens]
    }

    /// Snapshot as the store's own UserDefaults key → encoded bytes (opaque,
    /// like OurSpaceStore.backupRecords). `count` is the item count per key,
    /// for honest category stats.
    func backupRecords() -> [(key: String, data: Data, count: Int)] {
        Self.backupKeys.compactMap { key -> (String, Data, Int)? in
            guard let data = defaults.data(forKey: key) else { return nil }
            let count: Int
            switch key {
            case Key.tracks: count = (try? decoder.decode([MusicTrack].self, from: data))?.count ?? 0
            case Key.playlists: count = (try? decoder.decode([MusicPlaylist].self, from: data))?.count ?? 0
            case Key.comments: count = (try? decoder.decode([MusicComment].self, from: data))?.count ?? 0
            case Key.memories: count = (try? decoder.decode([MusicMemory].self, from: data))?.count ?? 0
            case Key.togetherListens: count = (try? decoder.decode([TogetherListen].self, from: data))?.count ?? 0
            default: count = 0
            }
            return (key, data, count)
        }
    }

    /// Merge one backup's records into the live store. Union by id (equality
    /// for together-listens), local wins on collision — restoring must never
    /// delete or roll back her library. Returns (imported, skipped).
    @discardableResult
    func restoreBackupRecords(_ records: [(key: String, data: Data, count: Int)])
        -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0
        for (key, data, _) in records {
            switch key {
            case Key.tracks:
                guard let incoming = try? decoder.decode([MusicTrack].self, from: data) else {
                    skipped += 1; continue
                }
                let r = mergeIdentifiable(&tracks, incoming: incoming)
                tracks.sort { $0.createdAt > $1.createdAt }
                save(tracks, key: Key.tracks)
                imported += r.added; skipped += r.skipped
            case Key.playlists:
                guard let incoming = try? decoder.decode([MusicPlaylist].self, from: data) else {
                    skipped += 1; continue
                }
                let r = mergeIdentifiable(&playlists, incoming: incoming)
                save(playlists, key: Key.playlists)
                imported += r.added; skipped += r.skipped
            case Key.comments:
                guard let incoming = try? decoder.decode([MusicComment].self, from: data) else {
                    skipped += 1; continue
                }
                let r = mergeIdentifiable(&comments, incoming: incoming)
                save(comments, key: Key.comments)
                imported += r.added; skipped += r.skipped
            case Key.memories:
                guard let incoming = try? decoder.decode([MusicMemory].self, from: data) else {
                    skipped += 1; continue
                }
                let r = mergeIdentifiable(&memories, incoming: incoming)
                save(memories, key: Key.memories)
                imported += r.added; skipped += r.skipped
            case Key.togetherListens:
                guard let incoming = try? decoder.decode([TogetherListen].self, from: data) else {
                    skipped += 1; continue
                }
                var seen = togetherListens
                var added = 0
                for item in incoming where !seen.contains(item) {
                    seen.append(item); togetherListens.append(item); added += 1
                }
                save(togetherListens, key: Key.togetherListens)
                imported += added; skipped += incoming.count - added
            default:
                skipped += 1
            }
        }
        return (imported, skipped)
    }

    /// Union by id; local wins on collision.
    private func mergeIdentifiable<T: Identifiable>(
        _ current: inout [T], incoming: [T]
    ) -> (added: Int, skipped: Int) where T.ID == String {
        var ids = Set(current.map(\.id))
        var added = 0
        var skipped = 0
        for item in incoming {
            if ids.contains(item.id) { skipped += 1 }
            else { ids.insert(item.id); current.append(item); added += 1 }
        }
        return (added, skipped)
    }

    private static func newId(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    // ---------- tracks ----------

    struct TrackInput {
        var title: String
        var artist: String = ""
        var album: String = ""
        var source: TrackSource = .local
        var sourceRef: String = ""
        var audioUri: String = ""
        var coverUri: String = ""
        var artworkUrl: String = ""
        var lyricsLrc: String = ""
        var addedBy: MusicAuthor = .her
    }

    @discardableResult
    func addTrack(_ input: TrackInput) throws -> MusicTrack {
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw MusicError.emptyTitle }
        if input.source == .appleMusic, input.sourceRef.trimmingCharacters(in: .whitespaces).isEmpty {
            throw MusicError.appleTrackNeedsCatalogId
        }
        let t = MusicTrack(
            id: Self.newId("trk"),
            title: title,
            artist: input.artist.trimmingCharacters(in: .whitespacesAndNewlines),
            album: input.album.trimmingCharacters(in: .whitespacesAndNewlines),
            source: input.source,
            sourceRef: input.sourceRef.trimmingCharacters(in: .whitespacesAndNewlines),
            audioUri: input.audioUri.trimmingCharacters(in: .whitespacesAndNewlines),
            coverUri: input.coverUri.trimmingCharacters(in: .whitespacesAndNewlines),
            artworkUrl: input.artworkUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            lyrics: input.lyricsLrc.isEmpty ? [] : parseLrc(input.lyricsLrc),
            addedBy: input.addedBy,
            playCount: 0,
            createdAt: Date()
        )
        tracks.insert(t, at: 0)
        save(tracks, key: Key.tracks)
        return t
    }

    func getTrack(_ id: String) -> MusicTrack? {
        tracks.first { $0.id == id }
    }

    func searchTracks(_ query: String) -> [MusicTrack] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return tracks.filter {
            $0.title.lowercased().contains(q)
                || $0.artist.lowercased().contains(q)
                || $0.album.lowercased().contains(q)
        }
    }

    @discardableResult
    func updateTrack(_ id: String, patch: (inout MusicTrack) -> Void) -> MusicTrack? {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return nil }
        patch(&tracks[i])
        save(tracks, key: Key.tracks)
        return tracks[i]
    }

    @discardableResult
    func deleteTrack(_ id: String) -> Bool {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return false }
        tracks.remove(at: i)
        save(tracks, key: Key.tracks)
        // Cascade: playlists, queue, comments, memories, together listens, now playing.
        for j in playlists.indices {
            playlists[j].trackIds.removeAll { $0 == id }
        }
        save(playlists, key: Key.playlists)
        queueIds.removeAll { $0 == id }
        save(queueIds, key: Key.queue)
        comments.removeAll { $0.trackId == id }
        save(comments, key: Key.comments)
        memories.removeAll { $0.trackId == id }
        save(memories, key: Key.memories)
        togetherListens.removeAll { $0.trackId == id }
        save(togetherListens, key: Key.togetherListens)
        if nowPlayingId == id { nowPlayingId = nil; save(nowPlayingId, key: Key.nowPlaying) }
        return true
    }

    func bumpPlayCount(_ id: String) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i].playCount += 1
        save(tracks, key: Key.tracks)
    }

    // ---------- playlists ----------

    /// Creates 共享歌单 + 我们的歌 on first run. Idempotent.
    func ensureDefaultPlaylists() {
        var changed = false
        if !playlists.contains(where: { $0.id == Self.sharedPlaylistId }) {
            playlists.append(MusicPlaylist(id: Self.sharedPlaylistId, name: "", kind: .shared,
                                           trackIds: [], createdBy: .her, createdAt: Date()))
            changed = true
        }
        if !playlists.contains(where: { $0.id == Self.oursPlaylistId }) {
            playlists.append(MusicPlaylist(id: Self.oursPlaylistId, name: "", kind: .ours,
                                           trackIds: [], createdBy: .her, createdAt: Date()))
            changed = true
        }
        if changed { save(playlists, key: Key.playlists) }
    }

    func orderedPlaylists() -> [MusicPlaylist] {
        let order: (MusicPlaylist) -> Int = { $0.kind == .shared ? 0 : $0.kind == .ours ? 1 : 2 }
        return playlists.sorted { order($0) < order($1) || ($0.kind == $1.kind && $0.createdAt < $1.createdAt) }
    }

    func getPlaylist(_ id: String) -> MusicPlaylist? {
        playlists.first { $0.id == id }
    }

    @discardableResult
    func createPlaylist(name: String, createdBy: MusicAuthor) throws -> MusicPlaylist {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw MusicError.emptyTitle }
        guard n.count <= 60 else { throw MusicError.nameTooLong }
        let p = MusicPlaylist(id: Self.newId("pl"), name: n, kind: .custom,
                              trackIds: [], createdBy: createdBy, createdAt: Date())
        playlists.append(p)
        save(playlists, key: Key.playlists)
        return p
    }

    @discardableResult
    func renamePlaylist(_ id: String, name: String) -> MusicPlaylist? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty,
              let i = playlists.firstIndex(where: { $0.id == id && $0.kind == .custom }) else { return nil }
        playlists[i].name = n
        save(playlists, key: Key.playlists)
        return playlists[i]
    }

    @discardableResult
    func deletePlaylist(_ id: String) -> Bool {
        guard let i = playlists.firstIndex(where: { $0.id == id && $0.kind == .custom }) else { return false }
        playlists.remove(at: i)
        save(playlists, key: Key.playlists)
        return true
    }

    @discardableResult
    func addToPlaylist(_ playlistId: String, trackId: String) throws -> Bool {
        guard getTrack(trackId) != nil else { throw MusicError.trackNotFound }
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { throw MusicError.playlistNotFound }
        if !playlists[i].trackIds.contains(trackId) {
            playlists[i].trackIds.append(trackId)
            save(playlists, key: Key.playlists)
        }
        return true
    }

    @discardableResult
    func removeFromPlaylist(_ playlistId: String, trackId: String) -> Bool {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return false }
        let before = playlists[i].trackIds.count
        playlists[i].trackIds.removeAll { $0 == trackId }
        guard playlists[i].trackIds.count != before else { return false }
        save(playlists, key: Key.playlists)
        return true
    }

    @discardableResult
    func moveInPlaylist(_ playlistId: String, trackId: String, dir: Int) -> Bool {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return false }
        guard let at = playlists[i].trackIds.firstIndex(of: trackId) else { return false }
        let to = at + dir
        guard to >= 0, to < playlists[i].trackIds.count else { return false }
        playlists[i].trackIds.swapAt(at, to)
        save(playlists, key: Key.playlists)
        return true
    }

    func playlistTracks(_ playlistId: String) -> [MusicTrack] {
        guard let p = getPlaylist(playlistId) else { return [] }
        return p.trackIds.compactMap { getTrack($0) }
    }

    /// Marks a track as one of 我们的歌 — the playlist AND the persistent
    /// memory that survives sessions (the store itself is the memory here;
    /// the AI reads it via tools on every turn).
    @discardableResult
    func markOurs(trackId: String) throws -> MusicTrack {
        guard let t = getTrack(trackId) else { throw MusicError.trackNotFound }
        try addToPlaylist(Self.oursPlaylistId, trackId: trackId)
        return t
    }

    func isOurs(_ trackId: String) -> Bool {
        getPlaylist(Self.oursPlaylistId)?.trackIds.contains(trackId) ?? false
    }

    // ---------- comments ----------

    @discardableResult
    func addComment(trackId: String, author: MusicAuthor, text: String) throws -> MusicComment {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw MusicError.emptyComment }
        guard t.count <= 500 else { throw MusicError.textTooLong }
        guard getTrack(trackId) != nil else { throw MusicError.trackNotFound }
        let c = MusicComment(id: Self.newId("cm"), trackId: trackId, author: author, text: t, createdAt: Date())
        comments.append(c)
        save(comments, key: Key.comments)
        return c
    }

    func listComments(trackId: String) -> [MusicComment] {
        comments.filter { $0.trackId == trackId }.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func deleteComment(_ id: String) -> Bool {
        guard let i = comments.firstIndex(where: { $0.id == id }) else { return false }
        comments.remove(at: i)
        save(comments, key: Key.comments)
        return true
    }

    // ---------- per-song memory notes ----------

    @discardableResult
    func addMemoryNote(trackId: String, text: String) throws -> MusicMemory {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw MusicError.emptyComment }
        guard t.count <= 500 else { throw MusicError.textTooLong }
        guard getTrack(trackId) != nil else { throw MusicError.trackNotFound }
        let m = MusicMemory(id: Self.newId("mm"), trackId: trackId, text: t, createdAt: Date())
        memories.append(m)
        save(memories, key: Key.memories)
        return m
    }

    func listMemoryNotes(trackId: String) -> [MusicMemory] {
        memories.filter { $0.trackId == trackId }.sorted { $0.createdAt > $1.createdAt }
    }

    // ---------- together-listen dates ----------

    private static func dayStart(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Record that this track was listened to together today.
    /// Deduped by day — one entry per track per day. No-op for unknown tracks.
    @discardableResult
    func recordTogetherListen(trackId: String) -> Bool {
        guard getTrack(trackId) != nil else { return false }
        let today = Self.dayStart(Date())
        if togetherListens.contains(where: { $0.trackId == trackId && Self.dayStart($0.date) == today }) {
            return false
        }
        togetherListens.append(TogetherListen(trackId: trackId, date: today))
        save(togetherListens, key: Key.togetherListens)
        return true
    }

    func togetherListenDates(trackId: String) -> [Date] {
        togetherListens.filter { $0.trackId == trackId }.map { $0.date }.sorted(by: >)
    }

    /// Total "我们一起听过" count — every entry exists because a track
    /// actually played with together mode on.
    func countTogetherListens() -> Int { togetherListens.count }

    // ---------- queue ----------

    @discardableResult
    func enqueue(_ trackId: String) throws -> Bool {
        guard getTrack(trackId) != nil else { throw MusicError.trackNotFound }
        queueIds.append(trackId)
        save(queueIds, key: Key.queue)
        return true
    }

    func queueTracks() -> [MusicTrack] {
        queueIds.compactMap { getTrack($0) }
    }

    @discardableResult
    func removeFromQueue(_ trackId: String) -> Bool {
        let before = queueIds.count
        queueIds.removeAll { $0 == trackId }
        guard queueIds.count != before else { return false }
        save(queueIds, key: Key.queue)
        return true
    }

    @discardableResult
    func moveInQueue(_ trackId: String, dir: Int) -> Bool {
        guard let at = queueIds.firstIndex(of: trackId) else { return false }
        let to = at + dir
        guard to >= 0, to < queueIds.count else { return false }
        queueIds.swapAt(at, to)
        save(queueIds, key: Key.queue)
        return true
    }

    func clearQueue() {
        queueIds.removeAll()
        save(queueIds, key: Key.queue)
    }

    /// Pops the head of the queue. Returns the track id or nil.
    @discardableResult
    func shiftQueue() -> String? {
        guard !queueIds.isEmpty else { return nil }
        let head = queueIds.removeFirst()
        save(queueIds, key: Key.queue)
        return head
    }

    // ---------- now playing / DJ intents ----------

    func setNowPlaying(_ trackId: String?) {
        nowPlayingId = trackId
        save(nowPlayingId, key: Key.nowPlaying)
        // If together-listening is on, this play counts as "we listened together".
        if let trackId, together.active {
            _ = recordTogetherListen(trackId: trackId)
        }
    }

    func getNowPlaying() -> MusicTrack? {
        guard let id = nowPlayingId else { return nil }
        return getTrack(id)
    }

    /// The AI writes playback intents from dialog; the room UI consumes them.
    /// Pure — never touches audio directly.
    @discardableResult
    func sendIntent(action: DjAction, by: MusicAuthor, trackId: String? = nil) throws -> DjIntent {
        if action == .play, let trackId {
            guard getTrack(trackId) != nil else { throw MusicError.trackNotFound }
        }
        let intent = DjIntent(action: action, trackId: trackId, at: Date(), by: by)
        self.intent = intent
        save(intent, key: Key.intent)
        return intent
    }

    func markIntentApplied(_ at: Date) {
        appliedIntentAt = at
        save(at, key: Key.appliedIntentAt)
    }

    // ---------- together mode ----------

    @discardableResult
    func setTogether(active: Bool, by: MusicAuthor) -> TogetherState {
        together = TogetherState(active: active,
                                 startedAt: active ? Date() : nil,
                                 startedBy: active ? by : nil)
        save(together, key: Key.together)
        return together
    }

    // ---------- selected lyric (tap-to-ask) ----------

    func setSelectedLyric(_ text: String?) {
        selectedLyric = text
        save(selectedLyric, key: Key.selectedLyric)
    }
}

// MARK: - Errors

enum MusicError: LocalizedError {
    case emptyTitle
    case nameTooLong
    case textTooLong
    case emptyComment
    case trackNotFound
    case playlistNotFound
    case appleTrackNeedsCatalogId
    case notPlayable(String)
    case sourceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "歌名不能为空。"
        case .nameTooLong: return "名字太长了（最多 60 字）。"
        case .textTooLong: return "太长了（最多 500 字）。"
        case .emptyComment: return "内容不能为空。"
        case .trackNotFound: return "找不到这首歌。"
        case .playlistNotFound: return "找不到这个歌单。"
        case .appleTrackNeedsCatalogId: return "Apple Music 的歌需要 catalog id。"
        case .notPlayable(let what): return what
        case .sourceUnavailable(let what): return what
        }
    }
}
