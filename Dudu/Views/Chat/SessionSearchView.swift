import SwiftUI

// MARK: - SessionSearchResultsView · 会话搜索结果
//
// Renders ChatStore.shared.searchSessions(query:) results inside the session
// drawer. The engine matches across session titles AND message text; each
// result carries the matched snippet (or a title-match note when only the
// title matched). Archived sessions show a "已归档" chip. Tapping a result
// opens that session via onSelect — no dead buttons, no fake data.
//
// Styling: Q萌圆润 per the 定妆 — small compact rows, theme colors only
// (DuduTheme), no emoji, no hardcoded colors, no pure black/white text.
struct SessionSearchResultsView: View {
    let results: [ChatStore.SearchResult]
    let currentSessionId: String?
    var onSelect: (ChatSession) -> Void = { _ in }

    var body: some View {
        if results.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(DuduTheme.titleFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                Text("没有找到匹配的对话")
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(results, id: \.session.id) { result in
                    resultRow(result)
                }
            }
            .duduCardList()
        }
    }

    private func resultRow(_ result: ChatStore.SearchResult) -> some View {
        Button {
            onSelect(result.session)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(sessionTitle(for: result.session))
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.duduText)
                            .lineLimit(1)
                        if result.session.archivedAt != nil {
                            Text("已归档")
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    DuduTheme.pinkSoft,
                                    in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip)
                                )
                        }
                    }
                    if let snippet = result.matchSnippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .lineLimit(2)
                    } else if result.titleMatched {
                        Text("标题匹配")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if result.session.id == currentSessionId {
                    Image(systemName: "checkmark")
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.pink)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func sessionTitle(for session: ChatSession) -> String {
        if let t = session.title, !t.isEmpty { return t }
        return "新的对话"
    }
}
