import SwiftUI

// MARK: - Music library sheets (D19, 2026-10-07)
//
// Playlists / song library / coming-up queue, as sheets over the room.
// Compact rows, small type, DuduTheme only, zero emoji.

// MARK: - Shared track row

struct MusicTrackRow: View {
    @ObservedObject private var store = MusicStore.shared
    @StateObject private var dj = AIDJ.shared
    let track: MusicTrack
    var trailing: (() -> AnyView)?

    init(track: MusicTrack, trailing: (() -> AnyView)? = nil) {
        self.track = track
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            trackArtwork(for: track, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !track.artist.isEmpty {
                        Text(track.artist)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .lineLimit(1)
                    }
                    if !track.isPlayable {
                        Text("无音频")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduDestructive)
                    } else if track.playCount > 0 {
                        Text("播 \(track.playCount) 次")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
            }
            Spacer()
            if let trailing { trailing() }
            Button {
                Task { try? await dj.playTrack(track) }
            } label: {
                DuduIcon(systemName: "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DuduTheme.duduText)
                    .frame(width: 32, height: 32)
                    .background(DuduTheme.pinkSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放")
            .disabled(!track.isPlayable)
            .opacity(track.isPlayable ? 1 : 0.35)
        }
        .padding(8)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
    }
}

// MARK: - Playlists sheet

struct MusicPlaylistsSheet: View {
    @ObservedObject private var store = MusicStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var showingNew = false
    @State private var expanded: String?
    @State private var pendingRenameId: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.orderedPlaylists()) { pl in
                        playlistCard(pl)
                    }
                }
                .padding(DuduTheme.pagePadding)
            }
            .background(DuduTheme.duduBackground)
            .navigationTitle("歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNew = true
                    } label: {
                        DuduIcon(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            }
            .alert(pendingRenameId == nil ? "新建歌单" : "改名", isPresented: $showingNew) {
                TextField("歌单名字", text: $newName)
                Button("取消", role: .cancel) { newName = ""; pendingRenameId = nil }
                Button("确定") {
                    if let rid = pendingRenameId {
                        _ = store.renamePlaylist(rid, name: newName)
                    } else {
                        try? store.createPlaylist(name: newName, createdBy: .her)
                    }
                    newName = ""
                    pendingRenameId = nil
                }
            }
        }
    }

    private func playlistCard(_ pl: MusicPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded = expanded == pl.id ? nil : pl.id
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pl.displayName)
                            .font(DuduTheme.bodyFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduText)
                        Text("\(pl.trackIds.count) 首")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    Spacer()
                    if pl.kind == .custom {
                        Menu {
                            Button("改名") { renamePlaylist(pl) }
                            Button("删除", role: .destructive) {
                                _ = store.deletePlaylist(pl.id)
                            }
                        } label: {
                            DuduIcon(systemName: "ellipsis")
                                .font(.system(size: 13))
                                .foregroundStyle(DuduTheme.duduTextDim)
                                .frame(width: 32, height: 32)
                        }
                    }
                    DuduIcon(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .rotationEffect(.degrees(expanded == pl.id ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            if expanded == pl.id {
                let tracks = store.playlistTracks(pl.id)
                if tracks.isEmpty {
                    Text(pl.kind == .ours ? "还没有我们的歌。听到特别的，点那颗小心心。" : "空的，去歌曲库里加几首。")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                ForEach(tracks) { t in
                    MusicTrackRow(track: t) {
                        AnyView(
                            Button {
                                _ = store.removeFromPlaylist(pl.id, trackId: t.id)
                            } label: {
                                DuduIcon(systemName: "minus.circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(DuduTheme.duduTextDim)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("从歌单移除")
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    private func renamePlaylist(_ pl: MusicPlaylist) {
        newName = pl.name
        pendingRenameId = pl.id
        showingNew = true
    }
}

// MARK: - Library sheet

struct MusicLibrarySheet: View {
    @ObservedObject private var store = MusicStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var showingAdd = false

    private var filtered: [MusicTrack] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? store.tracks
            : store.searchTracks(query)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if store.tracks.isEmpty {
                        OurSpaceEmptyState(
                            systemImage: "music.note.list",
                            title: "歌曲库是空的",
                            message: "导入音频文件，或者从 Apple Music 加歌。跟我说歌名，我也可以记下来。",
                            actionTitle: "加一首",
                            action: { showingAdd = true }
                        )
                    } else {
                        ForEach(filtered) { t in
                            MusicTrackRow(track: t) {
                                AnyView(
                                    Menu {
                                        Button(store.isOurs(t.id) ? "取消我们的歌" : "标为我们的歌") {
                                            if store.isOurs(t.id) {
                                                _ = store.removeFromPlaylist(MusicStore.oursPlaylistId, trackId: t.id)
                                            } else {
                                                try? store.markOurs(trackId: t.id)
                                            }
                                        }
                                        Button("删除", role: .destructive) {
                                            _ = store.deleteTrack(t.id)
                                        }
                                    } label: {
                                        DuduIcon(systemName: "ellipsis")
                                            .font(.system(size: 13))
                                            .foregroundStyle(DuduTheme.duduTextDim)
                                            .frame(width: 32, height: 32)
                                    }
                                )
                            }
                        }
                        if filtered.isEmpty {
                            Text("没找到，换个关键词。")
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                }
                .padding(DuduTheme.pagePadding)
            }
            .background(DuduTheme.duduBackground)
            .navigationTitle("歌曲库")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜歌名 / 歌手")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        DuduIcon(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showingAdd) { AddTrackSheet() }
        }
    }
}

// MARK: - Queue sheet

struct MusicQueueSheet: View {
    @ObservedObject private var store = MusicStore.shared
    @StateObject private var dj = AIDJ.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let q = store.queueTracks()
                    if q.isEmpty {
                        OurSpaceEmptyState(
                            systemImage: "list.number",
                            title: "排队是空的",
                            message: "从歌曲库或 DJ 推荐里加几首，下一首就有着落了。",
                            actionTitle: nil,
                            action: nil
                        )
                    } else {
                        ForEach(Array(q.enumerated()), id: \.element.id) { i, t in
                            HStack(spacing: 8) {
                                Text("\(i + 1)")
                                    .font(DuduTheme.captionFont(weight: .semibold))
                                    .foregroundStyle(DuduTheme.duduTextDim)
                                    .frame(width: 20)
                                MusicTrackRow(track: t) {
                                    AnyView(
                                        Button {
                                            _ = store.removeFromQueue(t.id)
                                        } label: {
                                            DuduIcon(systemName: "xmark.circle")
                                                .font(.system(size: 14))
                                                .foregroundStyle(DuduTheme.duduTextDim)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("移出排队")
                                    )
                                }
                            }
                        }
                        Button("清空排队") {
                            store.clearQueue()
                        }
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduDestructive)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }
                }
                .padding(DuduTheme.pagePadding)
            }
            .background(DuduTheme.duduBackground)
            .navigationTitle("接下来")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
