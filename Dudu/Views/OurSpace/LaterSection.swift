import SwiftUI

// MARK: - LaterSection · 稍后告诉她
//
// Queue of things he wants to tell her later. She checks them off.
// Undone first (oldest first), done sink below. Persists device-local.

struct LaterSection: View {
    @ObservedObject private var store = OurSpaceStore.shared
    @State private var showingEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                OurSpaceSectionHeader(title: "稍后告诉她", actionTitle: "记一笔") {
                    showingEditor = true
                }
            }
            if store.undoneLaterCount > 0 {
                Text("还有 \(store.undoneLaterCount) 件没做")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            if store.laterItems.isEmpty {
                OurSpaceEmptyState(
                    systemImage: "tray",
                    title: "没有待办事项",
                    body: "想跟她说的话，先记在这里，一件一件划掉。",
                    actionTitle: "记一笔"
                ) {
                    showingEditor = true
                }
            } else {
                ForEach(store.laterItems) { item in
                    laterRow(item)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            LaterEditorSheet(store: store)
        }
    }

    private func laterRow(_ item: LaterItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.toggleLater(id: item.id)
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(item.done ? DuduTheme.pink : DuduTheme.duduTextDim, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if item.done {
                        Circle()
                            .fill(DuduTheme.pink)
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DuduTheme.duduCard)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(item.done ? DuduTheme.duduTextDim : DuduTheme.duduText)
                    .strikethrough(item.done, color: DuduTheme.duduTextDim)
                Text(ourSpaceRelativeTime(from: item.createdAt) + "记下")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }

            Spacer(minLength: 4)

            Button(role: .destructive) {
                store.deleteLater(id: item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
        .opacity(item.done ? 0.75 : 1)
    }
}

// MARK: - LaterEditorSheet

private struct LaterEditorSheet: View {
    @ObservedObject var store: OurSpaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        OurSpaceSheet(title: "记一笔", saveTitle: "记下", canSave: canSave) {
            store.addLater(text: text)
        } content: {
            OurSpaceField(label: "想跟她说什么", placeholder: "例如：周末带她去那家新开的店", text: $text, axis: .vertical)
            Text("记下来就不会忘。她划掉一件，这里就少一件。")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }
}
