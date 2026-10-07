import SwiftUI
import UniformTypeIdentifiers

// MARK: - MusicRoomView · 听歌房 (D19, 2026-10-07)
//
// NetEase-style player adapted to the two of them — small and 精致:
// compact rows, small type, DuduTheme only, zero emoji.
// Entered from the 听歌 card in 我们的空间 (see the old manual:
// the room "lives in Our Space as the 听歌 card").

// MARK: - Root

struct MusicRoomView: View {
    @StateObject private var dj = AIDJ.shared
    @ObservedObject private var store = MusicStore.shared

    @State private var showingAddTrack = false
    @State private var showingLibrary = false
    @State private var showingPlaylists = false
    @State private var showingQueue = false
    @State private var showingAppleSettings = false
    @State private var commentDraft = ""
    @State private var sliderPos = 0.0
    @State private var seeking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                nowPlayingCard
                djPicksCard
                lyricsCard
                togetherRow
                actionsRow
                commentsCard
                appleMusicCard
            }
            .padding(.horizontal, DuduTheme.pagePadding)
            .padding(.vertical, 12)
        }
        .background(DuduTheme.duduBackground)
        .navigationTitle("听歌房")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddTrack = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                }
            }
        }
        .sheet(isPresented: $showingAddTrack) { AddTrackSheet() }
        .sheet(isPresented: $showingLibrary) { MusicLibrarySheet() }
        .sheet(isPresented: $showingPlaylists) { MusicPlaylistsSheet() }
        .sheet(isPresented: $showingQueue) { MusicQueueSheet() }
        .onChange(of: store.intent) { _, _ in
            Task { await dj.applyIntentIfPending() }
        }
        .onAppear {
            Task {
                await dj.refreshAppleAuthState()
                await dj.applyIntentIfPending()
            }
        }
    }

    // MARK: - Now playing

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let track = dj.currentTrack {
                HStack(spacing: 10) {
                    trackArtwork(for: track, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(DuduTheme.bodyFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduText)
                            .lineLimit(1)
                        Text(track.artist.isEmpty ? "未知艺人" : track.artist)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(track.source.label)
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(DuduTheme.duduIconChip, in: Capsule())
                            if store.together.active {
                                Text("一起听")
                                    .font(DuduTheme.captionFont(weight: .semibold))
                                    .foregroundStyle(DuduTheme.duduText)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(DuduTheme.pinkSoft, in: Capsule())
                            }
                        }
                    }
                    Spacer()
                    Button {
                        toggleOurs(track)
                    } label: {
                        Image(systemName: store.isOurs(track.id) ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundStyle(DuduTheme.pink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.isOurs(track.id) ? "取消我们的歌" : "标为我们的歌")
                }

                // Progress
                VStack(spacing: 2) {
                    Slider(
                        value: $sliderPos,
                        in: 0...(max(dj.status.duration ?? 0, 1)),
                        onEditingChanged: { editing in
                            seeking = editing
                            if !editing {
                                Task { await dj.seek(to: sliderPos) }
                            }
                        }
                    )
                    .tint(DuduTheme.pink)
                    .onChange(of: dj.status.position) { _, pos in
                        if !seeking { sliderPos = pos }
                    }
                    .onAppear { sliderPos = dj.status.position }
                    HStack {
                        Text(fmtTime(dj.status.position))
                        Spacer()
                        Text(fmtTime(dj.status.duration ?? 0))
                    }
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .monospacedDigit()
                }

                // Transport — every button does something real.
                HStack(spacing: 0) {
                    Spacer()
                    transportButton(systemImage: "backward.end.fill") {
                        Task { await dj.restart() }
                    }
                    .accessibilityLabel("从头播放")
                    Spacer()
                    Button {
                        Task { await dj.togglePlayPause() }
                    } label: {
                        Image(systemName: dj.status.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(DuduTheme.duduText)
                            .frame(width: 52, height: 52)
                            .background(DuduTheme.pinkSoft, in: Circle())
                    }
                    .accessibilityLabel(dj.status.playing ? "暂停" : "播放")
                    Spacer()
                    transportButton(systemImage: "forward.end.fill") {
                        Task { await dj.skip() }
                    }
                    .accessibilityLabel("下一首")
                    Spacer()
                }

                if let err = dj.lastError {
                    Text(err)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduDestructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                OurSpaceEmptyState(
                    systemImage: "music.note",
                    title: "还没在放歌",
                    message: store.tracks.isEmpty
                        ? "歌单是空的。点右上角加号导入音频，或者跟我说歌名，我来放。"
                        : "点下面选一首，或者跟我说歌名，我来放。",
                    actionTitle: store.tracks.isEmpty ? "去加歌" : "去选歌",
                    action: { showingAddTrack = store.tracks.isEmpty; showingLibrary = !store.tracks.isEmpty }
                )
            }
        }
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    private func transportButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(DuduTheme.duduText)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private func toggleOurs(_ track: MusicTrack) {
        if store.isOurs(track.id) {
            _ = store.removeFromPlaylist(MusicStore.oursPlaylistId, trackId: track.id)
        } else {
            try? store.markOurs(trackId: track.id)
        }
        dj.refreshRecommendations()
    }

    // MARK: - DJ picks (heuristics, honestly labeled)

    private var djPicksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DJ 为你排队")
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Button {
                    dj.djQueueTopPicks()
                    showingQueue = true
                } label: {
                    Text("一键排队")
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DuduTheme.pinkSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Text("按播放历史排的简单规则，不是 AI 懂你")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            if let mood = dj.herMoodToday {
                Text("她今天的心情：「\(mood)」")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .lineLimit(2)
            }
            if dj.recommendations.isEmpty {
                Text("多听几首，就有推荐了。")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            } else {
                ForEach(dj.recommendations) { rec in
                    Button {
                        Task { try? await dj.playTrack(rec.track) }
                    } label: {
                        HStack(spacing: 8) {
                            trackArtwork(for: rec.track, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rec.track.title)
                                    .font(DuduTheme.captionFont(weight: .semibold))
                                    .foregroundStyle(DuduTheme.duduText)
                                    .lineLimit(1)
                                Text(rec.reasons.joined(separator: " · "))
                                    .font(DuduTheme.captionFont())
                                    .foregroundStyle(DuduTheme.duduTextDim)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: - Lyrics (tap a line, ask in dialog)

    private var lyricsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("歌词")
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
            if let track = dj.currentTrack, !track.lyrics.isEmpty {
                let idx = lyricIndexAt(track.lyrics, position: dj.status.position)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(track.lyrics.enumerated()), id: \.offset) { i, line in
                            Button {
                                store.setSelectedLyric(line.text)
                            } label: {
                                Text(line.text)
                                    .font(i == idx ? DuduTheme.bodyFont(weight: .semibold) : DuduTheme.bodyFont())
                                    .foregroundStyle(i == idx ? DuduTheme.duduText : DuduTheme.duduTextDim)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 180)
                if let sel = store.selectedLyric {
                    Text("已选中「\(sel)」，去对话框问我这句。")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .lineLimit(2)
                } else {
                    Text("点某一句，可以去对话框问我这句什么意思。")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            } else {
                Text(dj.currentTrack == nil ? "放首歌就有歌词了。" : "这首歌还没有歌词。")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: - Together mode

    private var togetherRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(DuduTheme.pink)
            VStack(alignment: .leading, spacing: 2) {
                Text("一起听")
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                Text(store.together.active ? "正在一起听，放的歌会记下日期" : "打开后，放的歌会记下“X月X日一起听过”")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { store.together.active },
                set: { _ = store.setTogether(active: $0, by: .her) }
            ))
            .labelsHidden()
            .tint(DuduTheme.pink)
        }
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: - Library / playlists / queue entry points

    private var actionsRow: some View {
        HStack(spacing: 10) {
            roomAction(title: "歌单", systemImage: "music.note.list", count: store.playlists.count) {
                showingPlaylists = true
            }
            roomAction(title: "歌曲库", systemImage: "square.stack", count: store.tracks.count) {
                showingLibrary = true
            }
            roomAction(title: "排队", systemImage: "list.number", count: store.queueIds.count) {
                showingQueue = true
            }
        }
    }

    private func roomAction(title: String, systemImage: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(DuduTheme.pink)
                Text("\(title) · \(count)")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Comments on the current song

    private var commentsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这首歌的留言")
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
            if let track = dj.currentTrack {
                let list = store.listComments(trackId: track.id)
                if list.isEmpty {
                    Text("还没有留言，写一句吧。")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                } else {
                    ForEach(list.suffix(5)) { c in
                        HStack(alignment: .top, spacing: 6) {
                            Text(c.author.label)
                                .font(DuduTheme.captionFont(weight: .semibold))
                                .foregroundStyle(DuduTheme.pink)
                            Text(c.text)
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduText)
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("写一句…", text: $commentDraft)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(8)
                        .background(DuduTheme.duduBackground, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                    Button("发送") {
                        let t = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        try? store.addComment(trackId: track.id, author: .her, text: t)
                        commentDraft = ""
                    }
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DuduTheme.pinkSoft, in: Capsule())
                    .buttonStyle(.plain)
                }
            } else {
                Text("放首歌再留言。")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: - Apple Music state (honest)

    private var appleMusicCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Apple Music")
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Button {
                    showingAppleSettings = true
                } label: {
                    Text("去设置")
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DuduTheme.duduIconChip, in: Capsule())
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingAppleSettings) {
                    AppleMusicSettingsView()
                }
            }
            Text(dj.appleAuthState.hint)
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .fixedSize(horizontal: false, vertical: true)
            if dj.appleAuthState != .authorized {
                Button {
                    Task { await dj.appleAuthorize() }
                } label: {
                    Text("连接 Apple Music")
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(DuduTheme.pinkSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }
}

// MARK: - Shared pieces

/// Track artwork: picked cover → Apple Music artwork → music-note fallback.
@MainActor func trackArtwork(for track: MusicTrack, size: CGFloat) -> some View {
    Group {
        if !track.coverUri.isEmpty, FileManager.default.fileExists(atPath: track.coverUri) {
            AsyncImage(url: URL(fileURLWithPath: track.coverUri)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: artworkFallback(size: size)
                }
            }
        } else if !track.artworkUrl.isEmpty, let url = URL(string: track.artworkUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: artworkFallback(size: size)
                }
            }
        } else {
            artworkFallback(size: size)
        }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
}

@MainActor private func artworkFallback(size: CGFloat) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: size * 0.22)
            .fill(DuduTheme.duduIconChip)
        Image(systemName: "music.note")
            .font(.system(size: size * 0.4))
            .foregroundStyle(DuduTheme.pink)
    }
    .frame(width: size, height: size)
}

func fmtTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds)
    return "\(s / 60):\(String(format: "%02d", s % 60))"
}

// MARK: - Add track sheet

struct AddTrackSheet: View {
    @ObservedObject private var store = MusicStore.shared
    @StateObject private var dj = AIDJ.shared

    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var source: TrackSource = .local
    @State private var audioUri = ""
    @State private var audioName = ""
    @State private var coverUri = ""
    @State private var showAudioPicker = false
    @State private var showCoverPicker = false
    @State private var appleQuery = ""
    @State private var appleHits: [SourceTrack] = []
    @State private var appleSearching = false
    @State private var appleError: String?
    @State private var pickedCatalog: SourceTrack?
    @State private var error: String?

    var body: some View {
        OurSpaceSheet(title: "加歌", saveTitle: "保存", canSave: canSave, onSave: save) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("来源", selection: $source) {
                    Text("本地").tag(TrackSource.local)
                    Text("Apple Music").tag(TrackSource.appleMusic)
                }
                .pickerStyle(.segmented)

                if source == .local {
                    OurSpaceField(label: "歌名", placeholder: "必填", text: $title)
                    OurSpaceField(label: "艺人", placeholder: "选填", text: $artist)
                    OurSpaceField(label: "专辑", placeholder: "选填", text: $album)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("音频文件")
                            .font(DuduTheme.captionFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduTextDim)
                        Button {
                            showAudioPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 13))
                                Text(audioName.isEmpty ? "选择音频文件" : audioName)
                                    .font(DuduTheme.captionFont())
                                    .lineLimit(1)
                            }
                            .foregroundStyle(DuduTheme.duduText)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                        }
                        .buttonStyle(.plain)
                        if audioUri.isEmpty {
                            Text("不加音频也行，先记下歌名，以后再补。")
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("封面（选填）")
                            .font(DuduTheme.captionFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduTextDim)
                        Button {
                            showCoverPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 13))
                                Text(coverUri.isEmpty ? "选择封面图片" : "已选封面")
                                    .font(DuduTheme.captionFont())
                            }
                            .foregroundStyle(DuduTheme.duduText)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    appleSearchBlock
                }

                if let error {
                    Text(error)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduDestructive)
                }
            }
        }
        .fileImporter(isPresented: $showAudioPicker, allowedContentTypes: [.audio]) { result in
            handlePickedAudio(result)
        }
        .fileImporter(isPresented: $showCoverPicker, allowedContentTypes: [.image]) { result in
            handlePickedCover(result)
        }
    }

    private var canSave: Bool {
        if source == .local {
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return pickedCatalog != nil
    }

    // MARK: Apple Music search block

    private var appleSearchBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dj.appleAuthState != .authorized {
                Text(dj.appleAuthState.hint)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await dj.appleAuthorize() }
                } label: {
                    Text("先连接 Apple Music")
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(DuduTheme.pinkSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    TextField("搜歌名 / 歌手", text: $appleQuery)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(8)
                        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                    Button(appleSearching ? "搜…" : "搜索") {
                        Task { await runAppleSearch() }
                    }
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DuduTheme.pinkSoft, in: Capsule())
                    .buttonStyle(.plain)
                    .disabled(appleSearching || appleQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let appleError {
                    Text(appleError)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduDestructive)
                }
                ForEach(appleHits, id: \.id) { hit in
                    Button {
                        pickedCatalog = hit
                    } label: {
                        HStack(spacing: 8) {
                            if !hit.artworkUrl.isEmpty, let url = URL(string: hit.artworkUrl) {
                                AsyncImage(url: url) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable().scaledToFill()
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.title)
                                    .font(DuduTheme.captionFont(weight: .semibold))
                                    .foregroundStyle(DuduTheme.duduText)
                                    .lineLimit(1)
                                Text(hit.artist)
                                    .font(DuduTheme.captionFont())
                                    .foregroundStyle(DuduTheme.duduTextDim)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if pickedCatalog?.id == hit.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(DuduTheme.pink)
                            }
                        }
                        .padding(8)
                        .background(
                            pickedCatalog?.id == hit.id ? DuduTheme.pinkSoft : DuduTheme.duduCard,
                            in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func runAppleSearch() async {
        appleSearching = true
        appleError = nil
        defer { appleSearching = false }
        do {
            appleHits = try await dj.appleSearch(query: appleQuery, limit: 10)
            if appleHits.isEmpty { appleError = "曲库里没找到，换个关键词试试。" }
        } catch {
            appleError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Pickers

    private func handlePickedAudio(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let dir = try musicAudioDir()
            let dest = dir.appendingPathComponent(sanitized(url.lastPathComponent))
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            audioUri = dest.path
            audioName = url.lastPathComponent
        } catch {
            self.error = "导入失败：\(error.localizedDescription)"
        }
    }

    private func handlePickedCover(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let dir = try musicAudioDir()
            let dest = dir.appendingPathComponent("cover-" + sanitized(url.lastPathComponent))
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            coverUri = dest.path
        } catch {
            self.error = "封面导入失败：\(error.localizedDescription)"
        }
    }

    private func musicAudioDir() throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Music", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private func sanitized(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: bad).joined(separator: "_")
    }

    // MARK: Save

    private func save() {
        do {
            if source == .local {
                let t = try store.addTrack(MusicStore.TrackInput(
                    title: title, artist: artist, album: album,
                    source: .local, audioUri: audioUri, coverUri: coverUri,
                    addedBy: .her
                ))
                try? store.addToPlaylist(MusicStore.sharedPlaylistId, trackId: t.id)
            } else if let hit = pickedCatalog {
                let t = try store.addTrack(MusicStore.TrackInput(
                    title: hit.title, artist: hit.artist,
                    source: .appleMusic, sourceRef: hit.id, artworkUrl: hit.artworkUrl,
                    addedBy: .her
                ))
                try? store.addToPlaylist(MusicStore.sharedPlaylistId, trackId: t.id)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
