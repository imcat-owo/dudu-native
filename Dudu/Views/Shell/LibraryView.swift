import SwiftUI

/// Wave 2 Item 7 — 资料 tab: a real FilesBrowserView in the "文件" section
/// above the existing KnowledgeView (the knowledge base, in the "知识库"
/// section). Both sections get a proper DuduSectionTitle; the file browser
/// is bounded so the knowledge section below stays visible.
struct LibraryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DuduSectionTitle(AppLocalized("library.filesSection"))
                .padding(.horizontal, DuduTheme.pagePadding)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            FilesBrowserView()
                .padding(.top, 4)
            DuduSectionTitle(AppLocalized("library.knowledgeSection"))
                .padding(.horizontal, DuduTheme.pagePadding)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            KnowledgeView()
        }
        .background(DuduTheme.duduBackground.ignoresSafeArea())
    }
}
