import Foundation
import SwiftUI

// MARK: - AIAuthorizationCoordinator · 授权弹窗的动作层
//
// Engine 的真实 API 只有两条路，三个按钮如实映射到它们：
//   - 拒绝      → OffloadPermissionManager.respond(to:allowed: false)
//               底座记 denied，本次调用被拒，不改任何持久设置。
//   - 只许一次  → OffloadPermissionManager.respond(to:allowed: true)
//               底座记 approved(grantSession: true)：本会话内同命令不再问，
//               新会话照旧问。不改持久设置。
//   - 总是允许  → 先 OffloadPermissionManager.setPermissionLevel(.bypass, for:)
//               把该命令的持久等级写成 bypass（以后不再弹窗），再 respond
//               放行当前这次挂起。两步都走真实 API，没有假接线。
//
// 超时（30 秒，用户不点）：底座按 timedOut 结算 → 拒绝（fail closed），
// 弹窗由 pendingRequest 变 nil 自动消失。
@MainActor
final class AIAuthorizationCoordinator: ObservableObject {
    static let shared = AIAuthorizationCoordinator()

    private let manager = OffloadPermissionManager.shared

    /// 拒绝：本次拒绝，不记住。
    func deny(_ request: PermissionRequest) {
        manager.respond(to: request.id, allowed: false)
    }

    /// 只许一次：放行本次会话（grantSession: true 在 manager.respond 里），不记住到持久设置。
    func allowOnce(_ request: PermissionRequest) {
        manager.respond(to: request.id, allowed: true)
    }

    /// 总是允许：把该命令的持久等级写成 bypass（以后不再问），再放行当前这次。
    func allowAlways(_ request: PermissionRequest) {
        manager.setPermissionLevel(.bypass, for: request.commandName)
        manager.respond(to: request.id, allowed: true)
    }
}
