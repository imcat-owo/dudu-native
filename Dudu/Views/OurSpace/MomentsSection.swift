import SwiftUI

// MARK: - MomentsSection · 我们的时光
//
// Interactive timeline of their moments together: 时刻 / 里程碑 / 小记.
// Newest first. Entries persist device-local.

struct MomentsSection: View {
    @ObservedObject private var store = OurSpaceStore.shared
    @State private var showingEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OurSpaceSectionHeader(title: "我们的时光", actionTitle: "记一刻") {
                showingEditor = true
            }
            if store.moments.isEmpty {
                OurSpaceEmptyState(
                    systemImage: "clock",
                    title: "还没有时光",
                    message: "一起经历的时刻，他会记在这里。也可以现在记下第一刻。",
                    actionTitle: "记一刻"
                ) {
                    showingEditor = true
                }
            } else {
                timeline
            }
        }
        .sheet(isPresented: $showingEditor) {
            MomentEditorSheet(store: store)
        }
    }

    @MainActor private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.moments.enumerated()), id: \.element.id) { index, m in
                HStack(alignment: .top, spacing: 10) {
                    // Rail: dot + connecting line.
                    VStack(spacing: 0) {
                        Circle()
                            .fill(m.kind.dotColor)
                            .frame(width: 9, height: 9)
                            .padding(.top, 4)
                        if index < store.moments.count - 1 {
                            Rectangle()
                                .fill(DuduTheme.duduDivider)
                                .frame(width: 2)
                                .frame(minHeight: 24)
                        }
                    }
                    .frame(width: 12)

                    MomentCardView(store: store, momentID: m.id)
                }
                .padding(.bottom, index < store.moments.count - 1 ? 10 : 0)
            }
        }
    }
}

// MARK: - MomentEditorSheet

private struct MomentEditorSheet: View {
    @ObservedObject var store: OurSpaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var detail = ""
    @State private var kind: MomentKind = .moment

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        OurSpaceSheet(title: "记一刻", saveTitle: "保存", canSave: canSave) {
            store.addMoment(title: title, detail: detail, kind: kind)
        } content: {
            OurSpaceField(label: "发生了什么", placeholder: "例如：第一次一起看日落", text: $title)
            OurSpaceField(label: "多说一点（可选）", placeholder: "当时的细节", text: $detail, axis: .vertical)
            VStack(alignment: .leading, spacing: 6) {
                Text("类型")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduTextDim)
                HStack(spacing: 8) {
                    ForEach(MomentKind.allCases, id: \.self) { k in
                        let selected = k == kind
                        Button {
                            kind = k
                        } label: {
                            HStack(spacing: 5) {
                                DuduIcon(systemName: k.systemImage)
                                    .font(DuduTheme.appFont(size: 11))
                                Text(k.label)
                                    .font(DuduTheme.captionFont(weight: selected ? .semibold : .regular))
                            }
                            .foregroundStyle(selected ? DuduTheme.duduText : DuduTheme.duduTextDim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selected ? DuduTheme.pinkSoft : DuduTheme.duduCard,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - MomentCardView

/// One moment card: content + WeChat/Instagram-style like & comment actions,
/// with a WeChat-style inline preview of the latest comments.
private struct MomentCardView: View {
    @ObservedObject var store: OurSpaceStore
    let momentID: String
    @State private var showingComments = false

    var body: some View {
        card
            .sheet(isPresented: $showingComments) {
                MomentCommentSheet(store: store, momentID: momentID)
            }
    }

    @MainActor
    private var card: some View {
        Group {
            if let m = store.moment(id: momentID) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        OurSpaceChip(text: m.kind.label, color: m.kind.dotColor.opacity(0.35))
                        Text(m.title)
                            .font(DuduTheme.bodyFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduText)
                    }
                    if !m.detail.isEmpty {
                        Text(m.detail)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    Text(ourSpaceDateTimeString(from: m.timestamp))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                    actionRow(m)
                    commentPreview(m)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                .contextMenu {
                    Button(role: .destructive) {
                        store.deleteMoment(id: m.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
    }

    /// Heart (solid Q萌 style) + comment actions, WeChat/Instagram alignment.
    @MainActor
    private func actionRow(_ m: Moment) -> some View {
        HStack(spacing: 18) {
            Button {
                store.toggleMomentLike(id: m.id)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .font(DuduTheme.appFont(size: 14, weight: .semibold))
                        .foregroundStyle(m.likedByHer ? DuduTheme.pink : DuduTheme.duduTextDim)
                        .scaleEffect(m.likedByHer ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.45), value: m.likedByHer)
                    if m.likeCount > 0 {
                        Text("\(m.likeCount)")
                            .font(DuduTheme.captionFont(weight: .semibold))
                            .foregroundStyle(m.likedByHer ? DuduTheme.pink : DuduTheme.duduTextDim)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                showingComments = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left.fill")
                        .font(DuduTheme.appFont(size: 13, weight: .semibold))
                        .foregroundStyle(DuduTheme.duduTextDim)
                    if !m.comments.isEmpty {
                        Text("\(m.comments.count)")
                            .font(DuduTheme.captionFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 5)
    }

    /// WeChat-style inline preview: latest 2 comments, tap to open the thread.
    private func commentPreview(_ m: Moment) -> some View {
        Group {
            if !m.comments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(m.comments.suffix(2)) { c in
                        HStack(alignment: .top, spacing: 6) {
                            Text(c.author)
                                .font(DuduTheme.captionFont(weight: .semibold))
                                .foregroundStyle(DuduTheme.pink)
                            Text(c.text)
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                                .lineLimit(2)
                        }
                    }
                    if m.comments.count > 2 {
                        Text("查看全部 \(m.comments.count) 条评论")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
                .padding(.top, 4)
                .onTapGesture { showingComments = true }
            }
        }
    }
}

// MARK: - MomentCommentSheet

/// WeChat/Instagram-style comment thread: full list + input bar.
private struct MomentCommentSheet: View {
    @ObservedObject var store: OurSpaceStore
    let momentID: String
    @State private var draft = ""
    @Environment(\.dismiss) private var dismiss

    private var comments: [MomentComment] {
        store.moment(id: momentID)?.comments ?? []
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    if comments.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left")
                                .font(DuduTheme.appFont(size: 28))
                                .foregroundStyle(DuduTheme.duduTextDim)
                            Text("还没有评论，来抢第一条")
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(comments) { c in
                                commentRow(c)
                                if c.id != comments.last?.id {
                                    Rectangle()
                                        .fill(DuduTheme.duduDivider)
                                        .frame(height: 1)
                                        .padding(.leading, 38)
                                }
                            }
                        }
                        .padding(.horizontal, DuduTheme.pagePadding)
                        .padding(.vertical, 8)
                    }
                }
                inputBar
            }
            .background(DuduTheme.duduBackground)
            .navigationTitle("评论\(comments.isEmpty ? "" : " · \(comments.count)")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func commentRow(_ c: MomentComment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Q萌 avatar dot: author initial in a soft pink circle.
            Text(String(c.author.prefix(1)))
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
                .frame(width: 30, height: 30)
                .background(DuduTheme.pinkSoft, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(c.author)
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.pink)
                    Text(ourSpaceRelativeTime(from: c.createdAt))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                    Spacer()
                    if c.author == "她" {
                        Button {
                            store.deleteMomentComment(momentID: momentID, commentID: c.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(DuduTheme.appFont(size: 12))
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(c.text)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
            }
        }
        .padding(.vertical, 10)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("说点什么…", text: $draft, axis: .vertical)
                .font(DuduTheme.inputFont())
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(DuduTheme.duduCard, in: Capsule())
            Button {
                store.addMomentComment(momentID: momentID, text: draft)
                draft = ""
            } label: {
                Text("发送")
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(canSend ? DuduTheme.cream : DuduTheme.duduTextDim)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(canSend ? DuduTheme.pink : DuduTheme.duduIconChip, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, DuduTheme.pagePadding)
        .padding(.vertical, 10)
        .background(DuduTheme.duduBackground)
    }
}
