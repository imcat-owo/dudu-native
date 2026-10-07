import Foundation
import MusicKit
import StoreKit

// MARK: - MusicSources · pluggable music sources (D19, 2026-10-07)
//
// Ported from the old Dudu spec (openmuse/apps/mobile/src/music/sources.ts):
// the store only records WHICH source a track belongs to
// (`source` + `sourceRef`); everything that touches real audio lives behind
// the MusicSource protocol, so future sources (NetEase via MCP, …) plug in
// here without touching the store, the tools, or the UI.
//
// Sources:
// - local:       audio files she imports. Played through the existing
//                PlayerOffloadBridge session (real AVAudioPlayer audio —
//                no second player built here).
// - apple-music: Apple Music catalog via MusicKit. Needs: her developer
//                token (pasted in Settings, stored in the keychain — NEVER
//                hardcoded), MusicKit authorization, and an Apple Music
//                subscription. Every missing piece is surfaced honestly.

// MARK: - Source auth state

enum SourceAuthState {
    case unknown
    case authorized
    case denied
    case notSubscribed
    case notConfigured
    case unavailable

    /// Honest, her-language description of what is missing and what to do.
    var hint: String {
        switch self {
        case .unknown:
            return "还没连接，不知道状态。"
        case .authorized:
            return "已连接，可以放歌。"
        case .denied:
            return "她在系统设置里拒绝了 Apple Music 访问，去「设置 > 嘟嘟」重新打开。"
        case .notSubscribed:
            return "已授权，但这个 Apple ID 没有 Apple Music 订阅，播不了曲库的歌。"
        case .notConfigured:
            return "还没填 developer token。去「设置 > Apple Music」粘贴她的 token（Apple Developer 后台生成），这是三步里的第一步。"
        case .unavailable:
            return "这台设备上用不了 Apple Music。"
        }
    }
}

// MARK: - Track / status value types

/// A track as a source understands it.
struct SourceTrack {
    /// Stable id within the source (local: our track id; apple-music: catalog id).
    var id: String
    var title: String
    var artist: String
    var artworkUrl: String
    /// Seconds, nil when unknown.
    var duration: Double?
    var source: TrackSource
    /// Opaque ref the source needs to play (audioUri / catalog id).
    var playableRef: String
}

struct SourceStatus {
    var playing: Bool
    /// Seconds.
    var position: Double
    /// Seconds, nil when unknown.
    var duration: Double?
    /// Source-scoped id of the loaded track, nil when nothing loaded.
    var trackId: String?
}

// MARK: - Protocol (the seam future sources plug into)

/// Everything a music source must do. Conformance lives in this file;
/// future sources (NetEase via MCP, …) add a new class here + a
/// TrackSource raw value — nothing else changes.
protocol MusicSource: AnyObject {
    var id: TrackSource { get }
    var label: String { get }
    /// False when the native capability is missing in this build.
    func isAvailable() -> Bool
    func getAuthState() async -> SourceAuthState
    /// Runs the auth flow (may show system dialogs).
    func authorize() async -> SourceAuthState
    func search(query: String, limit: Int) async throws -> [SourceTrack]
    func load(_ track: SourceTrack) async throws
    func play() async throws
    func pause() async
    func seekTo(_ seconds: Double) async
    func getStatus() async -> SourceStatus
    func onStatus(_ cb: @escaping (SourceStatus) -> Void) -> () -> Void
    func release() async
}

// MARK: - MusicKeychain

/// Keychain home for the Apple Music developer token (hers — pasted in
/// Settings, never hardcoded) and the MusicKit user token.
enum MusicKeychain {
    private static let service = "com.dudu.ios.music"
    private static let developerTokenAccount = "musickit-developer-token"
    private static let userTokenAccount = "musickit-user-token"
    private static let authStateKey = "dudu.music.v1.apple-music.auth-state"

    static var developerToken: String? {
        get { read(account: developerTokenAccount) }
        set {
            if let v = newValue, !v.isEmpty { write(v, account: developerTokenAccount) }
            else { delete(account: developerTokenAccount) }
        }
    }

    static var userToken: String? {
        get { read(account: userTokenAccount) }
        set {
            if let v = newValue, !v.isEmpty { write(v, account: userTokenAccount) }
            else { delete(account: userTokenAccount) }
        }
    }

    static var cachedAuthState: String? {
        get { UserDefaults.standard.string(forKey: authStateKey) }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: authStateKey) }
            else { UserDefaults.standard.removeObject(forKey: authStateKey) }
        }
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - End-of-track synthesis (pure, testable)

/// Natural-finish tolerance, in seconds.
let appleEndTolerance: Double = 1.5

/// On natural finish, players report playing=false at the finished position
/// (duration) instead of position 0. The UI auto-advance watches for
/// playing:false + position:0 — translate here so the queue advances.
/// The song-id match guards against stale state right after load().
func applyEndOfTrack(prev: SourceStatus, mirrored: SourceStatus) -> SourceStatus {
    let ended = !mirrored.playing
        && mirrored.trackId != nil
        && mirrored.trackId == prev.trackId
        && (prev.duration ?? 0) > 0
        && mirrored.position >= (prev.duration ?? 0) - appleEndTolerance
    if !ended { return mirrored }
    return SourceStatus(playing: false, position: 0, duration: prev.duration, trackId: mirrored.trackId)
}

// MARK: - local: PlayerOffloadBridge sessions

private let localIdle = SourceStatus(playing: false, position: 0, duration: nil, trackId: nil)

/// Local audio files, played through the existing PlayerOffloadBridge
/// session (which drives DuduVoiceBubblePlayer — real AVAudioPlayer audio).
@MainActor
final class LocalMusicSource: MusicSource {
    let id: TrackSource = .local
    let label = "本地"

    private var sessionId: String?
    private var status: SourceStatus = localIdle
    private var listeners: [(SourceStatus) -> Void] = []
    private var pollTimer: Timer?

    func isAvailable() -> Bool { true }

    func getAuthState() async -> SourceAuthState { .authorized }

    func authorize() async -> SourceAuthState { .authorized }

    func search(query: String, limit: Int) async throws -> [SourceTrack] {
        // Local search happens against our own library (the store), not here.
        []
    }

    func load(_ track: SourceTrack) async throws {
        await release()
        let ref = track.playableRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else {
            throw MusicError.notPlayable("这首还没有音频。先在听歌房里给它加上音频文件。")
        }
        let url: URL
        if ref.hasPrefix("file://") || ref.hasPrefix("/") {
            url = ref.hasPrefix("file://") ? URL(string: ref)! : URL(fileURLWithPath: ref)
        } else if let remote = URL(string: ref), remote.scheme?.hasPrefix("http") == true {
            url = remote
        } else {
            url = URL(fileURLWithPath: ref)
        }
        guard FileManager.default.fileExists(atPath: url.path) || url.scheme?.hasPrefix("http") == true else {
            throw MusicError.notPlayable("音频文件找不到了（可能被删了）。重新导入一次吧。")
        }
        let loaded: (NSDictionary?, NSString?) = await withCheckedContinuation { cont in
            PlayerOffloadBridge.openPlayer(withUrl: url, guestPath: track.title) { data, err in
                cont.resume(returning: (data, err))
            }
        }
        if let err = loaded.1 {
            throw MusicError.notPlayable("播不了：\(err)")
        }
        let sid = (loaded.0?["session_id"] as? String)
        guard let sid else { throw MusicError.notPlayable("播放会话没建起来。") }
        sessionId = sid
        status = SourceStatus(playing: false, position: 0, duration: track.duration, trackId: track.id)
        emit()
        startPolling()
    }

    func play() async throws {
        guard sessionId != nil else { throw MusicError.notPlayable("还没加载歌曲。") }
        var err: NSString?
        _ = PlayerOffloadBridge.resumeSession(sessionId!, error: &err)
        status.playing = true
        emit()
    }

    func pause() async {
        guard let sid = sessionId else { return }
        var err: NSString?
        _ = PlayerOffloadBridge.pauseSession(sid, error: &err)
        status.playing = false
        emit()
    }

    func seekTo(_ seconds: Double) async {
        guard let sid = sessionId else { return }
        var err: NSString?
        _ = PlayerOffloadBridge.seekSession(sid, toSeconds: max(0, seconds), error: &err)
        status.position = max(0, seconds)
        emit()
    }

    func getStatus() async -> SourceStatus { status }

    func onStatus(_ cb: @escaping (SourceStatus) -> Void) -> () -> Void {
        listeners.append(cb)
        let token = listeners.count - 1
        return { [weak self] in self?.listeners[token] = { _ in } }
    }

    func release() async {
        stopPolling()
        if let sid = sessionId {
            var err: NSString?
            _ = PlayerOffloadBridge.stopSession(sid, error: &err)
        }
        sessionId = nil
        status = localIdle
        emit()
    }

    private func emit() {
        let s = status
        for l in listeners { l(s) }
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollOnce() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollOnce() {
        guard let sid = sessionId else { return }
        var err: NSString?
        guard let dict = PlayerOffloadBridge.statusForSession(sid, error: &err) else { return }
        let wasPlaying = status.playing
        let playing = (dict["status"] as? String) == "playing"
        let position = (dict["current_time"] as? Double) ?? status.position
        let duration = (dict["duration"] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? status.duration
        let prev = status
        var mirrored = SourceStatus(playing: playing, position: position, duration: duration, trackId: status.trackId)
        // Synthesize the finished signal so the queue auto-advances.
        if wasPlaying, !playing, let d = duration, d > 0, position >= d - appleEndTolerance {
            mirrored = SourceStatus(playing: false, position: 0, duration: d, trackId: status.trackId)
        } else {
            mirrored = applyEndOfTrack(prev: prev, mirrored: mirrored)
        }
        if mirrored.playing != prev.playing || abs(mirrored.position - prev.position) > 0.5
            || mirrored.duration != prev.duration {
            status = mirrored
            emit()
        } else {
            status = mirrored
        }
    }
}

// MARK: - apple-music: MusicKit

/// Apple Music catalog via MusicKit. Honest by construction: every missing
/// piece (token / authorization / subscription) surfaces as a real state,
/// never a fake player.
@MainActor
final class AppleMusicSource: MusicSource {
    let id: TrackSource = .appleMusic
    let label = "Apple Music"

    private var status: SourceStatus = localIdle
    private var listeners: [(SourceStatus) -> Void] = []
    private var pollTimer: Timer?

    func isAvailable() -> Bool { true }

    func getAuthState() async -> SourceAuthState {
        let token = MusicKeychain.developerToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { return .notConfigured }
        let sys = MusicAuthorization.currentStatus
        if sys == .denied || sys == .restricted { return .denied }
        let cached = MusicKeychain.cachedAuthState
        if cached == "denied" { return .denied }
        if cached == "not-subscribed" { return .notSubscribed }
        if cached == "authorized" {
            // Guard: "authorized" without a stored user token is an
            // inconsistent cache (crashed mid-flow, keychain wiped).
            guard MusicKeychain.userToken != nil else { return .unknown }
            return .authorized
        }
        return .unknown
    }

    func authorize() async -> SourceAuthState {
        let token = MusicKeychain.developerToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { return .notConfigured }
        let sys = await MusicAuthorization.request()
        var state: SourceAuthState
        switch sys {
        case .authorized:
            // Fetch + cache the MusicKit user token against her developer token.
            await fetchUserToken(developerToken: token)
            if let sub = try? await MusicSubscription.current, sub.canPlayCatalogContent {
                state = .authorized
            } else {
                state = .notSubscribed
            }
        case .denied, .restricted:
            state = .denied
        case .notDetermined:
            state = .unknown
        @unknown default:
            state = .unknown
        }
        MusicKeychain.cachedAuthState = {
            switch state {
            case .authorized: return "authorized"
            case .denied: return "denied"
            case .notSubscribed: return "not-subscribed"
            default: return nil
            }
        }()
        return state
    }

    private func fetchUserToken(developerToken: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SKCloudServiceController().requestUserToken(forDeveloperToken: developerToken) { userToken, _ in
                if let userToken { MusicKeychain.userToken = userToken }
                cont.resume()
            }
        }
    }

    func search(query: String, limit: Int = 10) async throws -> [SourceTrack] {
        let state = await getAuthState()
        guard state == .authorized else {
            throw MusicError.sourceUnavailable("Apple Music 还没连上：" + state.hint)
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var request = MusicCatalogSearchRequest(term: q, types: [Song.self])
        request.limit = max(1, min(25, limit))
        let response: MusicCatalogSearchResponse
        do {
            response = try await request.response()
        } catch {
            throw MusicError.sourceUnavailable("搜 Apple Music 失败了：\(error.localizedDescription)")
        }
        return response.songs.map { song in
            SourceTrack(
                id: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                artworkUrl: song.artwork?.url(width: 300, height: 300)?.absoluteString ?? "",
                duration: song.duration,
                source: .appleMusic,
                playableRef: song.id.rawValue
            )
        }
    }

    func load(_ track: SourceTrack) async throws {
        await release()
        let state = await getAuthState()
        guard state == .authorized else {
            throw MusicError.sourceUnavailable("Apple Music 还没连上：" + state.hint)
        }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(rawValue: track.playableRef))
        let response: MusicItemCollection<Song>
        do {
            response = try await request.response()
        } catch {
            throw MusicError.sourceUnavailable("取这首歌失败了：\(error.localizedDescription)")
        }
        guard let song = response.items.first else {
            throw MusicError.notPlayable("Apple Music 曲库里找不到这首歌了。")
        }
        // ApplicationMusicPlayer (not System): app-scoped queue, never
        // disturbs her Music app's own playback.
        let player = ApplicationMusicPlayer.shared
        player.queue = [song]
        status = SourceStatus(playing: false, position: 0, duration: track.duration ?? song.duration, trackId: track.id)
        emit()
        startPolling()
    }

    func play() async throws {
        let player = ApplicationMusicPlayer.shared
        do {
            try await player.play()
        } catch {
            throw MusicError.notPlayable("播不了：\(error.localizedDescription)")
        }
        status.playing = true
        emit()
    }

    func pause() async {
        ApplicationMusicPlayer.shared.pause()
        status.playing = false
        emit()
    }

    func seekTo(_ seconds: Double) async {
        ApplicationMusicPlayer.shared.playbackTime = max(0, seconds)
        status.position = max(0, seconds)
        emit()
    }

    func getStatus() async -> SourceStatus {
        let player = ApplicationMusicPlayer.shared
        let playing = player.playbackStatus == .playing
        let prev = status
        var songId = status.trackId
        if let entry = player.queue.currentEntry, let song = entry.item as? Song {
            songId = song.id.rawValue
        }
        let mirrored = SourceStatus(
            playing: playing,
            position: player.playbackTime,
            duration: status.duration,
            trackId: songId
        )
        status = applyEndOfTrack(prev: prev, mirrored: mirrored)
        return status
    }

    func onStatus(_ cb: @escaping (SourceStatus) -> Void) -> () -> Void {
        listeners.append(cb)
        let token = listeners.count - 1
        return { [weak self] in self?.listeners[token] = { _ in } }
    }

    func release() async {
        stopPolling()
        ApplicationMusicPlayer.shared.pause()
        status = localIdle
        emit()
    }

    private func emit() {
        let s = status
        for l in listeners { l(s) }
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let s = await self.getStatus()
                self.emit()
                _ = s
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

// MARK: - Registry

@MainActor
enum MusicSourceRegistry {
    private static let localSource = LocalMusicSource()
    private static let appleSource = AppleMusicSource()

    static func source(for id: TrackSource) -> any MusicSource {
        switch id {
        case .local: return localSource
        case .appleMusic: return appleSource
        }
    }

    /// Sources usable in this build.
    static func available() -> [any MusicSource] {
        [localSource, appleSource].filter { $0.isAvailable() }
    }
}
