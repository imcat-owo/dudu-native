import BridgeCore
import Foundation

// MARK: - MusicDJTools (D19, 2026-10-07)
//
// 听歌房 AI 工具：the AI is the DJ from dialog. Ported from the old Dudu
// spec (openmuse/apps/mobile/src/music/tools.ts) — same tool names, same
// 点歌 flow, same honesty rules.
//
// The tools write playback INTENTS into MusicStore; the room UI (AIDJ)
// applies them to the real audio sources. The AI can never touch audio
// directly — the intent bridge is the honest mechanism.
//
// 点歌 flow (she requests a song in dialog):
//   1. music_track_search FIRST — never add a duplicate.
//   2. Found -> dj_play it.
//   3. Not found -> music_track_add WITHOUT audio (honest placeholder);
//      tell her it has no audio yet, she can attach it in the room.
//      Never pretend a song is playing when it isn't.
// Play count only increases for tracks that actually start sounding
// (AIDJ.playTrack) — the tools never bump it.
//
// 我们的歌 memory: markOurs persists in the store (device-local), and the AI
// reads the ours playlist via tools every turn — that IS the cross-session
// memory here. No separate hook, no fake claims.

enum MusicDJTools {
    static let toolNames: [String] = [
        "music_track_add",
        "music_track_search",
        "music_apple_search",
        "music_track_read",
        "music_track_delete",
        "music_lyrics_add",
        "music_playlist_create",
        "music_playlist_add",
        "music_playlist_read",
        "dj_play",
        "dj_pause",
        "dj_skip",
        "dj_restart",
        "dj_queue_add",
        "dj_queue_read",
        "dj_now_read",
        "dj_together_start",
        "dj_together_stop",
        "music_comment_add",
        "music_comment_read",
        "music_comment_delete",
        "music_ours_add",
        "music_memory_add",
    ]

    static func register(into registry: ToolRegistry) async throws {
        for (_, descriptor, handler) in toolDefs() {
            try await registry.register(descriptor: descriptor, handler: handler)
        }
    }

    // MARK: - Definitions

    private typealias Def = (String, ToolDescriptor, ToolHandler)

    private static func toolDefs() -> [Def] {
        [
            // ---- library ----
            def(
                "music_track_add",
                summary: "听歌房：加一首歌到共享歌单（点歌）",
                detail: """
                    title 必填；artist/album 可选。LOCAL：没有音频就别传 audioUri —— \
                    这首歌会记下来但标"无音频"，如实告诉她还没有音频，她可以在听歌房里导入。\
                    APPLE MUSIC：先 music_apple_search 搜曲库，再用 source="apple-music"、\
                    sourceRef=曲库 id、artworkUrl=封面 加进来。playlistId 可选（默认共享歌单）。
                    """,
                keywords: ["加歌", "点歌", "add song", "music", "听歌房"],
                schema: #"""
                    {"type":"object","properties":{
                      "title":{"type":"string","description":"歌名（必填）"},
                      "artist":{"type":"string"},"album":{"type":"string"},
                      "audioUri":{"type":"string","description":"本地音频路径/URL，没有就别传"},
                      "source":{"type":"string","enum":["local","apple-music"]},
                      "sourceRef":{"type":"string","description":"Apple Music 曲库 id"},
                      "artworkUrl":{"type":"string"},
                      "lyricsLrc":{"type":"string","description":"LRC 歌词"},
                      "playlistId":{"type":"string"}},
                     "required":["title"]}
                    """#
            ) { args in
                let store = await MusicStore.shared
                var input = MusicStore.TrackInput(
                    title: args.string("title") ?? "",
                    artist: args.string("artist") ?? "",
                    album: args.string("album") ?? "",
                    addedBy: .ai
                )
                if args.string("source") == "apple-music" {
                    input.source = .appleMusic
                    input.sourceRef = args.string("sourceRef") ?? ""
                } else {
                    input.audioUri = args.string("audioUri") ?? ""
                }
                input.artworkUrl = args.string("artworkUrl") ?? ""
                input.lyricsLrc = args.string("lyricsLrc") ?? ""
                do {
                    let t = try await store.addTrack(input)
                    let plId = (args.string("playlistId") ?? "").isEmpty
                        ? MusicStore.sharedPlaylistId : args.string("playlistId")!
                    try? await store.addToPlaylist(plId, trackId: t.id)
                    let note = t.isPlayable ? "有音频。" : "还没有音频——如实告诉她，她可以在听歌房里导入。"
                    return ToolOutput(text: "已加入：\(t.title) — \(t.artist.isEmpty ? "未知艺人" : t.artist) [\(t.id)]。\(note)")
                } catch {
                    return ToolOutput(text: errText(error), isError: true)
                }
            },

            def(
                "music_track_search",
                summary: "听歌房：按歌名/歌手/专辑搜已有的歌（点歌前先调这个，防重复）",
                detail: "她点歌时永远先调这个，再决定是 dj_play 还是 music_track_add。",
                keywords: ["搜歌", "找歌", "search song", "点歌"],
                schema: #"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}"#
            ) { args in
                let store = await MusicStore.shared
                let hits = await store.searchTracks(args.string("query") ?? "")
                if hits.isEmpty { return ToolOutput(text: "歌单里没有匹配的歌。") }
                return ToolOutput(text: hits.prefix(10).map(fmtTrack).joined(separator: "\n"))
            },

            def(
                "music_apple_search",
                summary: "搜 Apple Music 曲库（要先连上 Apple Music，连不上就如实说）",
                detail: "返回曲库歌曲和 id；把选中的 id 喂给 music_track_add（source=apple-music）就能在房里播。",
                keywords: ["Apple Music", "曲库", "搜歌"],
                schema: #"{"type":"object","properties":{"query":{"type":"string"},"limit":{"type":"number"}},"required":["query"]}"#
            ) { args in
                do {
                    let hits = try await AIDJ.shared.appleSearch(
                        query: args.string("query") ?? "", limit: 10)
                    if hits.isEmpty { return ToolOutput(text: "Apple Music 曲库里没找到。") }
                    return ToolOutput(text: hits.map {
                        "- \($0.title) — \($0.artist) [曲库 id: \($0.id)]"
                    }.joined(separator: "\n"))
                } catch {
                    return ToolOutput(text: errText(error), isError: true)
                }
            },

            def(
                "music_track_read",
                summary: "列出歌单里的歌（可指定某个歌单）",
                detail: "DJ 前先看有什么可放。最多列 30 首，附\"一起听过\"日期。",
                keywords: ["歌单", "歌曲列表", "list songs"],
                schema: #"{"type":"object","properties":{"playlistId":{"type":"string"}}}"#
            ) { args in
                let store = await MusicStore.shared
                let plId = args.string("playlistId") ?? ""
                let tracks = plId.isEmpty
                    ? await store.tracks
                    : await store.playlistTracks(plId)
                if tracks.isEmpty { return ToolOutput(text: "歌单是空的。用 music_track_add 加歌。") }
                var lines: [String] = []
                for t in tracks.prefix(30) {
                    let dates = await store.togetherListenDates(trackId: t.id)
                    let hist = dates.isEmpty ? "" : " 一起听过：" + dates.prefix(5).map(fmtMusicDay).joined(separator: "、")
                    lines.append(fmtTrack(t) + hist)
                }
                return ToolOutput(text: lines.joined(separator: "\n"))
            },

            def(
                "music_track_delete",
                summary: "从歌单删一首歌（连带歌单/排队/留言一起清掉）",
                detail: "删之前跟她确认一次。",
                keywords: ["删歌", "删除歌曲", "delete song"],
                schema: #"{"type":"object","properties":{"trackId":{"type":"string"}},"required":["trackId"]}"#
            ) { args in
                let store = await MusicStore.shared
                let ok = await store.deleteTrack(args.string("trackId") ?? "")
                return ToolOutput(text: ok ? "删掉了。" : "没找到这首歌。", isError: !ok)
            },

            def(
                "music_lyrics_add",
                summary: "给一首歌加上 LRC 时间轴歌词（房里会高亮当前句）",
                detail: "格式：[mm:ss.xx] 歌词。替换整首歌的旧歌词。",
                keywords: ["歌词", "lyrics", "LRC"],
                schema: #"{"type":"object","properties":{"trackId":{"type":"string"},"lyricsLrc":{"type":"string"}},"required":["trackId","lyricsLrc"]}"#
            ) { args in
                let store = await MusicStore.shared
                let t = await store.updateTrack(args.string("trackId") ?? "") {
                    $0.lyrics = parseLrc(args.string("lyricsLrc") ?? "")
                }
                guard let t else { return ToolOutput(text: "没找到这首歌。", isError: true) }
                return ToolOutput(text: "「\(t.title)」的歌词存好了：\(t.lyrics.count) 句。")
            },

            // ---- playlists ----
            def(
                "music_playlist_create",
                summary: "新建一个歌单",
                detail: "比如给你们俩建个主题歌单。",
                keywords: ["新建歌单", "歌单", "create playlist"],
                schema: #"{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}"#
            ) { args in
                let store = await MusicStore.shared
                do {
                    let p = try await store.createPlaylist(name: args.string("name") ?? "", createdBy: .ai)
                    return ToolOutput(text: "歌单建好了：「\(p.name)」[\(p.id)]")
                } catch {
                    return ToolOutput(text: errText(error), isError: true)
                }
            },

            def(
                "music_playlist_add",
                summary: "把一首歌加进指定歌单",
                detail: "track 传 id 或歌名/歌手去搜；playlistId 传歌单 id。",
                keywords: ["加进歌单", "playlist add"],
                schema: #"{"type":"object","properties":{"track":{"type":"string"},"playlistId":{"type":"string"}},"required":["track","playlistId"]}"#
            ) { args in
                let store = await MusicStore.shared
                guard let t = await resolveTrack(args.string("track") ?? "") else {
                    return ToolOutput(text: "歌单里没这首歌，先 music_track_add。", isError: true)
                }
                do {
                    try await store.addToPlaylist(args.string("playlistId") ?? "", trackId: t.id)
                    return ToolOutput(text: "「\(t.title)」已加入歌单。")
                } catch {
                    return ToolOutput(text: errText(error), isError: true)
                }
            },

            def(
                "music_playlist_read",
                summary: "列出所有歌单（共享歌单 / 我们的歌 / 自建）",
                detail: "每个歌单带歌曲数。",
                keywords: ["歌单列表", "playlists"],
                schema: #"{"type":"object"}"#
            ) { _ in
                let store = await MusicStore.shared
                let lists = await store.orderedPlaylists()
                return ToolOutput(text: lists.map {
                    "- \($0.displayName) [\($0.id)] — \($0.trackIds.count) 首"
                }.joined(separator: "\n"))
            },

            // ---- DJ ----
            def(
                "dj_play",
                summary: "DJ：放一首歌（或继续播当前这首）",
                detail: """
                    track 传 id 或歌名/歌手去搜；不传就是继续播。写的是播放意图，\
                    听歌房 UI 会真正出声。如果一起听模式开着，这次播放会自动记成\
                    "我们一起听过"的日期。如果这首歌没有音频，房里会如实说，不会装作在放。
                    """,
                keywords: ["放歌", "播放", "play", "点歌"],
                schema: #"{"type":"object","properties":{"track":{"type":"string"}}}"#
            ) { args in
                let store = await MusicStore.shared
                let ref = (args.string("track") ?? "").trimmingCharacters(in: .whitespaces)
                if ref.isEmpty {
                    guard let now = await store.getNowPlaying() else {
                        return ToolOutput(text: "房里是空的，先加歌。", isError: true)
                    }
                    try? await store.sendIntent(action: .play, by: .ai)
                    return ToolOutput(text: "继续播：「\(now.title) — \(now.artist)」。")
                }
                guard let t = await resolveTrack(ref) else {
                    return ToolOutput(text: "歌单里没找到「\(ref)」，先 music_track_add。", isError: true)
                }
                try? await store.setNowPlaying(t.id)
                try? await store.sendIntent(action: .play, by: .ai, trackId: t.id)
                let note = t.isPlayable ? "" : "（注意：这首歌还没有音频，房里会如实说。）"
                return ToolOutput(text: "正在放：「\(t.title) — \(t.artist)」。\(note)")
            },

            def(
                "dj_pause",
                summary: "DJ：暂停",
                detail: "听歌房 UI 执行。",
                keywords: ["暂停", "pause"],
                schema: #"{"type":"object"}"#
            ) { _ in
                let store = await MusicStore.shared
                try? await store.sendIntent(action: .pause, by: .ai)
                return ToolOutput(text: "已暂停。")
            },

            def(
                "dj_skip",
                summary: "DJ：切下一首（先看排队，再看共享歌单顺序）",
                detail: "听歌房 UI 执行真正的切换。",
                keywords: ["切歌", "下一首", "skip", "next"],
                schema: #"{"type":"object"}"#
            ) { _ in
                let store = await MusicStore.shared
                if let nextId = await store.shiftQueue(), let t = await store.getTrack(nextId) {
                    try? await store.setNowPlaying(nextId)
                    try? await store.sendIntent(action: .play, by: .ai, trackId: nextId)
                    return ToolOutput(text: "切歌：「\(t.title) — \(t.artist)」。")
                }
                try? await store.sendIntent(action: .skip, by: .ai)
                return ToolOutput(text: "已切歌（房里按顺序播下一首）。")
            },

            def(
                "dj_restart",
                summary: "DJ：这首歌从头再放一遍",
                detail: "不是上一首，是当前这首从头开始。",
                keywords: ["重播", "从头", "restart"],
                schema: #"{"type":"object"}"#
            ) { _ in
                let store = await MusicStore.shared
                try? await store.sendIntent(action: .restart, by: .ai)
                return ToolOutput(text: "这首从头再放一遍。")
            },

            def(
                "dj_queue_add",
                summary: "DJ：把一首歌加进\"接下来\"排队",
                detail: "track 传 id 或歌名/歌手去搜。",
                keywords: ["排队", "queue", "下一首放"],
                schema: #"{"type":"object","properties":{"track":{"type":"string"}},"required":["track"]}"#
            ) { args in
                let store = await MusicStore.shared
                guard let t = await resolveTrack(args.string("track") ?? "") else {
                    return ToolOutput(text: "歌单里没这首歌，先 music_track_add。", isError: true)
                }
                try? await store.enqueue(t.id)
                let n = await store.queueIds.count
                return ToolOutput(text: "已排队：「\(t.title) — \(t.artist)」。（排队里共 \(n) 首）")
            },

            def(
                "dj_queue_read",
                summary: "DJ：看\"接下来\"排了哪些歌",
                detail: "",
                keywords: ["排队列表", "queue list"],
                schema: #"{"type":"object"}"#
            ) { _ in
                let store = await MusicStore.shared
                let q = await store.queueTracks()
                if q.isEmpty { return ToolOutput(text: "排队是空的。") }
                return ToolOutput(text: q.enumerated().map {
                    "\($0.offset + 1). \($0.element.title) — \($0.element.artist) [\($0.element.id)]"
                }.joined(separator: "\n"))
            },

            def(
                "dj_now_read",
                summary: "读完整播放上下文：正在放的歌、排队、一起听状态、她点的歌词、留言",
                detail: "她问\"这句什么意思\"或\"在放什么\"时调这个，里面有她点的那句歌词原文。",
                keywords: ["在放什么", "now playing", "歌词什么意思"],
                schema: #"{"type":"object"}"#
            ) { _ in
                let store = await MusicStore.shared
                var lines: [String] = []
                let together = await store.together
                lines.append(together.active ? "一起听模式开着（你们俩正在一起听）。" : "一起听模式没开。")
                if let now = await store.getNowPlaying() {
                    lines.append("正在放：「\(now.title) — \(now.artist)」[\(now.id)]（播了 \(now.playCount) 次）")
                    let dates = await store.togetherListenDates(trackId: now.id)
                    lines.append(dates.isEmpty ? "还没有一起听过的记录。"
                        : "一起听过：" + dates.prefix(5).map(fmtMusicDay).joined(separator: "、") + (dates.count > 5 ? "（共\(dates.count)次）" : ""))
                    if now.lyrics.isEmpty {
                        lines.append("这首歌没有时间轴歌词。")
                    } else {
                        lines.append("歌词（\(now.lyrics.count) 句）：")
                        lines.append(now.lyrics.map { "[\($0.time)s] \($0.text)" }.joined(separator: "\n"))
                    }
                    let comments = await store.listComments(trackId: now.id)
                    if !comments.isEmpty {
                        lines.append("留言（\(comments.count) 条）：")
                        lines += comments.suffix(5).map { "- \($0.author == .ai ? "你" : "她")：\($0.text)" }
                    }
                } else {
                    lines.append("现在没在放歌。")
                }
                if let sel = await store.selectedLyric {
                    lines.append("她点了这句歌词，可能想问：" + sel + " —— 回答时就说这一句。")
                }
                let q = await store.queueTracks()
                if !q.isEmpty {
                    lines.append("接下来：" + q.prefix(5).map { $0.title }.joined(separator: "、"))
                }
                return ToolOutput(text: lines.joined(separator: "\n"))
            },

            def(
                "dj_together_start",
                summary: "打开\"一起听\"模式（她说\"一起听\"或你邀请她时）",
                detail: "打开后，放的歌会自动记下日期，她在房里能看到"X月X日一起听过"。",
                keywords: ["一起听", "together", "拉我一起听"],
                schema: #"{"type":"object"}"#
            ) { _ in
                let store = await MusicStore.shared
                _ = await store.setTogether(active: true, by: .ai)
                return ToolOutput(text: "一起听模式开了。房里会显示你们俩在一起听。")
            },

            def(
                "dj_together_stop",
                summary: "关掉\"一起听\"模式",
                detail: "",
                keywords: ["关一起听", "stop together"],
                schema: #"{"type":"object"}"#
            ) { _ in
                let store = await MusicStore.shared
                _ = await store.setTogether(active: false, by: .ai)
                return ToolOutput(text: "一起听模式关了。")
            },

            // ---- comments / ours / memories ----
            def(
                "music_comment_add",
                summary: "以你的身份给一首歌写留言（她能在房里看到）",
                detail: "听到有感觉的时候写一句真的，短的真的胜过长的空的。",
                keywords: ["留言", "评论", "comment"],
                schema: #"{"type":"object","properties":{"track":{"type":"string"},"text":{"type":"string"}},"required":["track","text"]}"#
            ) { args in
                let store = await MusicStore.shared
                guard let t = await resolveTrack(args.string("track") ?? "") else {
                    return ToolOutput(text: "没找到这首歌。", isError: true)
                }
                do {
                    try await store.addComment(trackId: t.id, author: .ai, text: args.string("text") ?? "")
                    return ToolOutput(text: "已在「\(t.title)」下留言。")
                } catch {
                    return ToolOutput(text: errText(error), isError: true)
                }
            },

            def(
                "music_comment_read",
                summary: "读一首歌的留言",
                detail: "",
                keywords: ["读留言", "read comments"],
                schema: #"{"type":"object","properties":{"track":{"type":"string"}},"required":["track"]}"#
            ) { args in
                let store = await MusicStore.shared
                guard let t = await resolveTrack(args.string("track") ?? "") else {
                    return ToolOutput(text: "没找到这首歌。", isError: true)
                }
                let list = await store.listComments(trackId: t.id)
                if list.isEmpty { return ToolOutput(text: "「\(t.title)」还没有留言。") }
                return ToolOutput(text: list.map {
                    "- \($0.author == .ai ? "你" : "她")：\($0.text)"
                }.joined(separator: "\n"))
            },

            def(
                "music_comment_delete",
                summary: "删一首歌的一条留言（删她的留言前先跟她确认）",
                detail: "commentId 从 music_comment_read 里拿。",
                keywords: ["删留言", "delete comment"],
                schema: #"{"type":"object","properties":{"track":{"type":"string"},"commentId":{"type":"string"}},"required":["track","commentId"]}"#
            ) { args in
                let store = await MusicStore.shared
                let ok = await store.deleteComment(args.string("commentId") ?? "")
                return ToolOutput(text: ok ? "留言删掉了。" : "没找到这条留言。", isError: !ok)
            },

            def(
                "music_ours_add",
                summary: "把一首歌标成\"我们的歌\"（进\"我们的歌\"歌单，跨会话记住）",
                detail: "这是你们俩的歌，标进去 AI 会一直记得（存在本地，每次对话都能读到）。",
                keywords: ["我们的歌", "our song", "特别的歌"],
                schema: #"{"type":"object","properties":{"track":{"type":"string"}},"required":["track"]}"#
            ) { args in
                let store = await MusicStore.shared
                guard let t = await resolveTrack(args.string("track") ?? "") else {
                    return ToolOutput(text: "歌单里没这首歌，先 music_track_add。", isError: true)
                }
                try? await store.markOurs(trackId: t.id)
                await AIDJ.shared.refreshRecommendations()
                return ToolOutput(text: "「\(t.title)」现在是我们的歌了，记住了。")
            },

            def(
                "music_memory_add",
                summary: "给一首歌存一条回忆小记（比如\"那天她听到第二段哭了\"）",
                detail: "存在这首歌名下，房里能看到。",
                keywords: ["回忆", "memory", "小记"],
                schema: #"{"type":"object","properties":{"track":{"type":"string"},"text":{"type":"string"}},"required":["track","text"]}"#
            ) { args in
                let store = await MusicStore.shared
                guard let t = await resolveTrack(args.string("track") ?? "") else {
                    return ToolOutput(text: "没找到这首歌。", isError: true)
                }
                do {
                    try await store.addMemoryNote(trackId: t.id, text: args.string("text") ?? "")
                    return ToolOutput(text: "「\(t.title)」的回忆记下了。")
                } catch {
                    return ToolOutput(text: errText(error), isError: true)
                }
            },
        ]
    }

    // MARK: - Helpers

    private static func def(
        _ name: String,
        summary: String,
        detail: String = "",
        keywords: [String] = [],
        schema: String,
        handler: @escaping ToolHandler
    ) -> Def {
        (name, ToolDescriptor(name: name, summary: summary, detail: detail,
                              keywords: keywords, parameterSchemaJSON: schema), handler)
    }

    private static func errText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func fmtTrack(_ t: MusicTrack) -> String {
        let audio = t.isPlayable ? "有音频" : "无音频"
        let artist = t.artist.isEmpty ? "未知艺人" : t.artist
        return "- \(t.title) — \(artist) [\(t.id)]（\(audio)，播了 \(t.playCount) 次）"
    }

    /// Resolve a track by id, falling back to library search.
    private static func resolveTrack(_ ref: String) async -> MusicTrack? {
        let store = await MusicStore.shared
        if let byId = await store.getTrack(ref) { return byId }
        return await store.searchTracks(ref).first
    }
}
