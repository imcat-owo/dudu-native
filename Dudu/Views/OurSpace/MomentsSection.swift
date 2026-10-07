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

    private var timeline: some View {
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
                                Image(systemName: k.systemImage)
                                    .font(.system(size: 11))
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
