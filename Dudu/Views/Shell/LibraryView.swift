import SwiftUI

/// Wave 2 Item 2 — 资料 tab: a "文件" section header above the existing
/// KnowledgeView (the knowledge base). Item 7 will flesh out the file
/// browser; the KnowledgeView below is real and live, so there is no
/// dead UI here.
struct LibraryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalized("library.filesSection"))
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)
                .padding(.horizontal, DuduTheme.pagePadding)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            KnowledgeView()
        }
        .background(DuduTheme.duduBackground.ignoresSafeArea())
    }
}
