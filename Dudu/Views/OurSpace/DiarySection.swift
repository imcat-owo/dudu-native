import SwiftUI

// MARK: - DiarySection · 我的日记
//
// His diary, written for the two of them. Entries persist device-local.
// Newest first.

struct DiarySection: View {
    @ObservedObject private var store = OurSpaceStore.shared
    @State private var showingEditor = false
    @State private var entryToDelete: DiaryEntry?
    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OurSpaceSectionHeader(title: "我的日记", actionTitle: "写日记") {
                showingEditor = true
            }
            if store.diary.isEmpty {
                OurSpaceEmptyState(
                    systemImage: "book",
                    title: "还没有日记",
                    message: "值得记住的日子，他会写下来。也可以现在写第一篇。",
                    actionTitle: "写日记"
                ) {
                    showingEditor = true
                }
            } else {
                ForEach(store.diary) { entry in
                    NavigationLink {
                        DiaryDetailView(entry: entry)
                    } label: {
                        diaryRow(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            DiaryEditorSheet(store: store)
        }
        .confirmationDialog("删除这篇日记？", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let entry = entryToDelete {
                    store.deleteDiary(id: entry.id)
                }
                entryToDelete = nil
            }
            Button("取消", role: .cancel) {
                entryToDelete = nil
            }
        }
    }

    private func diaryRow(_ entry: DiaryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .lineLimit(1)
                Text(entry.content)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .lineLimit(2)
                Text(entry.date)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            Spacer(minLength: 4)
            Button {
                entryToDelete = entry
                showingDeleteConfirm = true
            } label: {
                DuduIcon(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }
}

// MARK: - DiaryDetailView

private struct DiaryDetailView: View {
    @ObservedObject private var store = OurSpaceStore.shared
    let entry: DiaryEntry
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.title)
                    .font(DuduTheme.headingFont(delta: 2))
                    .foregroundStyle(DuduTheme.duduText)
                Text(entry.date + " · " + ourSpaceRelativeTime(from: entry.createdAt))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                Divider()
                    .background(DuduTheme.duduDivider)
                Text(entry.content)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                    .textSelection(.enabled)
            }
            .padding(DuduTheme.pagePadding)
        }
        .background(DuduTheme.duduBackground)
        .navigationTitle("日记")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button {
                    showingDeleteConfirm = true
                } label: {
                    DuduIcon(systemName: "trash")
                        .foregroundStyle(DuduTheme.duduDestructive)
                }
            }
        }
        .confirmationDialog("删除这篇日记？", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                store.deleteDiary(id: entry.id)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - DiaryEditorSheet

private struct DiaryEditorSheet: View {
    @ObservedObject var store: OurSpaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var content = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        OurSpaceSheet(title: "写日记", saveTitle: "保存", canSave: canSave) {
            store.addDiary(title: title, content: content)
        } content: {
            OurSpaceField(label: "标题", placeholder: "给今天起个名字", text: $title)
            VStack(alignment: .leading, spacing: 6) {
                Text("正文")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduTextDim)
                TextEditor(text: $content)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
            }
            Text("日期默认为今天（\(OurSpaceStore.todayString())）。")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }
}
