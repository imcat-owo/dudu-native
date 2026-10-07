import SwiftUI

/// Phase C tab bar. Two tabs now; the bar is built to grow.
///
/// Phase D tabs — RESERVED positions only. Do NOT build them here, do NOT
/// add buttons for them (no dead buttons):
///   case activity    // 动态 Activity
///   case ideas       // 灵感 Ideas
///   case goals       // 目标 Goals
///   case apps        // 应用 Apps
///   case ourSpace    // 我们的空间 Our Space
enum DuduTab: String, CaseIterable, Identifiable {
    case chat
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "聊天"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .settings: return "gearshape"
        }
    }
}
