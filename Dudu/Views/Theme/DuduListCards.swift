import SwiftUI

// MARK: - DuduListCards · html-2 定稿 list pattern (Wave 2 Item 3)
//
// 奶油色底 + 白色圆角卡片: every settings-style List/Form in the app gets
// the same treatment — cream page background, each row as its own white
// 17pt card, caption-style section headers in normal case (never the
// default uppercase gray), no default separators.
//
// Two flavors:
//   - duduCardList(): for List. Uses .plain + per-row inset card
//     backgrounds so every row is a separate 17pt white card with gaps,
//     matching html-2's row-list pattern. Keeps swipeActions / onDelete /
//     onMove / EditButton / searchable working (all List-native).
//   - duduCardForm(): for Form (data-entry sheets). Form keeps its grouped
//     nature; sections become white cards on cream with subtle dividers.
//
// All colors via DuduTheme, all type via DuduTheme font helpers — no
// literals, no emoji.

/// Card radius for list rows. Per html-2 定稿: rows use 17pt (radiusChip);
/// 22pt is for large cards (tab bar / composer) only.
private let duduListCardRadius: CGFloat = DuduTheme.radiusChip

struct DuduCardListModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.top, 12)
            .background(DuduTheme.duduBackground)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: 10,
                leading: DuduTheme.pagePadding + 12,
                bottom: 10,
                trailing: DuduTheme.pagePadding + 12
            ))
            .listRowBackground(
                RoundedRectangle(cornerRadius: duduListCardRadius, style: .continuous)
                    .fill(DuduTheme.duduCard)
                    .padding(.horizontal, DuduTheme.pagePadding)
                    .padding(.vertical, 4)
            )
    }
}

struct DuduCardFormModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .padding(.top, 12)
            .background(DuduTheme.duduBackground)
            .listRowBackground(DuduTheme.duduCard)
            .listRowSeparatorTint(DuduTheme.duduDivider)
    }
}

extension View {
    /// html-2 定稿 list: cream page + white 17pt row cards.
    func duduCardList() -> some View {
        modifier(DuduCardListModifier())
    }

    /// html-2 定稿 form: cream page + white section cards.
    func duduCardForm() -> some View {
        modifier(DuduCardFormModifier())
    }
}

// MARK: - Section headers / footers

/// Section header: caption style, normal case, dim color — never the
/// default uppercase gray. Cream-backed so it stays readable if the
/// plain-style header sticks while scrolling.
struct DuduSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(DuduTheme.captionFont(weight: .semibold))
            .foregroundStyle(DuduTheme.duduTextDim)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DuduTheme.duduBackground)
    }
}

/// Section footer: caption style, dim color.
struct DuduSectionFooter<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .font(DuduTheme.captionFont())
            .foregroundStyle(DuduTheme.duduTextDim)
    }
}
