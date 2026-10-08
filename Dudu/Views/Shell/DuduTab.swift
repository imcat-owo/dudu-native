import SwiftUI

/// Shell tabs for the custom floating glass tab bar (Wave 2 Item 2,
/// html-2 定稿): 我们 / 对话 / 资料 / 更多.
///
/// Raw-value stability: `chat` and `ourSpace` keep their values; the old
/// `settings` tab is now `more` and keeps the "settings" raw value, so any
/// stored deep link that selects "settings" still lands on the same tab.
/// New case `library` ("library") hosts the knowledge base.
///
/// Labels are localized via AppLocalized; the new xcstrings keys
/// (tab.ourSpace / tab.chat / tab.library / tab.more) must be added to
/// Localizable.xcstrings by the localization coordinator.
enum DuduTab: String, CaseIterable, Identifiable {
    case ourSpace
    case chat
    case library = "library"
    case more = "settings"

    var id: String { rawValue }

    /// Left-to-right order in the floating bar.
    static var barOrder: [DuduTab] { [.ourSpace, .chat, .library, .more] }

    var title: String {
        switch self {
        case .ourSpace: return AppLocalized("tab.ourSpace")
        case .chat: return AppLocalized("tab.chat")
        case .library: return AppLocalized("tab.library")
        case .more: return AppLocalized("tab.more")
        }
    }

    /// Kept as a fallback only (accessibility, future use). The floating
    /// bar draws its own solid hand-drawn icons — never SF Symbols.
    var systemImage: String {
        switch self {
        case .ourSpace: return "heart"
        case .chat: return "bubble.left.and.bubble.right"
        case .library: return "book"
        case .more: return "ellipsis"
        }
    }
}
