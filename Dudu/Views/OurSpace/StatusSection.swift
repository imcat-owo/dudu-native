import SwiftUI

// MARK: - StatusSection · 我的状态
//
// What the AI is doing right now (written by the AI via dialog/tools —
// hook: OurSpaceStore.shared.setAIStatus), plus her mood as she told him.

struct StatusSection: View {
    @ObservedObject private var store = OurSpaceStore.shared
    @State private var showingMoodSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            aiStatusCard
            herMoodCard
        }
        .sheet(isPresented: $showingMoodSheet) {
            MoodSheet(store: store)
        }
    }

    // MARK: AI status

    private var aiStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                DuduIcon(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DuduTheme.pink)
                Text("我在做什么")
                    .font(DuduTheme.titleFont())
                    .foregroundStyle(DuduTheme.duduText)
            }
            if let s = store.aiStatus {
                Text(s.text)
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                if !s.detail.isEmpty {
                    Text(s.detail)
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                Text(ourSpaceRelativeTime(from: s.updatedAt) + "更新")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            } else {
                Text("他还没有更新状态。在聊天里发生的事，他会记在这里。")
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: Her mood

    private var herMoodCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                DuduIcon(systemName: "face.smiling")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DuduTheme.pink)
                Text("她的心情")
                    .font(DuduTheme.titleFont())
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Button {
                    showingMoodSheet = true
                } label: {
                    Text(store.herMood == nil ? "记录一下" : "更新")
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DuduTheme.duduIconChip, in: Capsule())
                }
            }
            if let m = store.herMood {
                Text(m.mood)
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                if !m.note.isEmpty {
                    Text(m.note)
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                Text(ourSpaceRelativeTime(from: m.updatedAt) + "记录")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            } else {
                Text("还没有记录过。心情好的时候、累的时候，都可以记一笔，他会记得。")
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }
}

// MARK: - MoodSheet

private struct MoodSheet: View {
    @ObservedObject var store: OurSpaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var mood: String
    @State private var note: String

    init(store: OurSpaceStore) {
        self.store = store
        _mood = State(initialValue: store.herMood?.mood ?? "")
        _note = State(initialValue: store.herMood?.note ?? "")
    }

    private var canSave: Bool {
        !mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        OurSpaceSheet(title: "记录心情", saveTitle: "保存", canSave: canSave) {
            store.setHerMood(mood: mood, note: note)
        } content: {
            OurSpaceField(label: "现在的心情", placeholder: "例如：有点累，但很开心", text: $mood)
            OurSpaceField(label: "想说的话（可选）", placeholder: "多说一句，他都记着", text: $note, axis: .vertical)
        }
    }
}
