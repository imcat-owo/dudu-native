import SwiftUI

// MARK: - AIAuthorizationPromptView · AI 权限授权弹窗
//
// AI 想用设备能力（相册/定位/剪贴板/通知/麦克风/蓝牙等）时，
// OffloadPermissionManager 的 askOnce 等级会把请求挂到底座
// （ToolSuspensionService，tag == "offload"），manager 再把
// 当前挂起映射成 @Published pendingRequest。本视图只观察它：
// 有值就弹出三选一卡片，点按直接调 AIAuthorizationCoordinator
// 走 engine 真实 API；无值/超时/点完后自动消失。
//
// 浮层（非 sheet）：挂在 DuduTabView 的 overlay 里，聊天输入
// 不受影响，继续能聊——跟 MCPApprovalCardView 同一做法。
struct AIAuthorizationPromptView: View {
    @ObservedObject private var manager = OffloadPermissionManager.shared
    @StateObject private var coordinator = AIAuthorizationCoordinator()

    var body: some View {
        if let request = manager.pendingRequest {
            PromptCard(request: request, coordinator: coordinator)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Card

private struct PromptCard: View {
    let request: PermissionRequest
    let coordinator: AIAuthorizationCoordinator

    /// 已点的请求 id：点过一次就锁住三个按钮，防连点重复 respond。
    /// 请求切换时用 .id(request.id) 重置。
    @State private var answered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题行：图标 + "AI 想用{能力}"
            HStack(spacing: 10) {
                DuduIcon(systemName: iconName(for: request.commandName))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DuduTheme.pink)
                    .frame(width: 34, height: 34)
                    .background(DuduTheme.duduIconChip)
                    .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 想用\(request.displayLabel)")
                        .font(DuduTheme.titleFont())
                        .foregroundStyle(DuduTheme.duduText)
                    if !request.description.isEmpty {
                        Text(request.description)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
            }

            // 具体要执行的命令（有才显示），让她看清 AI 到底要干什么。
            if !request.fullCommand.isEmpty {
                Text(request.fullCommand)
                    .font(DuduTheme.monoFont(size: 10))
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DuduTheme.duduBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Divider()
                .background(DuduTheme.duduDivider)

            // 三选一
            VStack(spacing: 8) {
                ChoiceButton(
                    title: "只许一次",
                    style: .primary,
                    disabled: answered
                ) {
                    answered = true
                    coordinator.allowOnce(request)
                }
                ChoiceButton(
                    title: "总是允许",
                    style: .secondary,
                    disabled: answered
                ) {
                    answered = true
                    coordinator.allowAlways(request)
                }
                ChoiceButton(
                    title: "拒绝",
                    style: .quiet,
                    disabled: answered
                ) {
                    answered = true
                    coordinator.deny(request)
                }
            }

            Text("30 秒内不选择将自动拒绝")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .id(request.id)
        .padding(14)
        .background(DuduTheme.duduCard)
        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
        .shadow(color: DuduTheme.duduTextDim.opacity(0.25), radius: 12, y: 4)
        .padding(.horizontal, DuduTheme.pagePadding)
        .padding(.bottom, 8)
    }

    /// 命令名 → SF Symbol（矢量图标，不用 emoji）。
    private func iconName(for command: String) -> String {
        switch command {
        case "apple-photos": return "photo.fill"
        case "apple-location": return "location.fill"
        case "apple-clipboard": return "doc.on.clipboard.fill"
        case "apple-notification": return "bell.fill"
        case "apple-speech": return "mic.fill"
        case "apple-bluetooth": return "bluetooth"
        case "apple-healthkit": return "heart.fill"
        case "apple-calendar": return "calendar"
        case "apple-reminders": return "checklist"
        case "apple-homekit": return "house.fill"
        default: return "lock.shield.fill"
        }
    }
}

// MARK: - Choice button

private struct ChoiceButton: View {
    enum Style { case primary, secondary, quiet }

    let title: String
    let style: Style
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1.0)
        // 三个都是真按钮：拒绝也一样可点。无占位、无死按钮。
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch style {
        case .primary: return DuduTheme.duduText
        case .secondary: return DuduTheme.duduText
        case .quiet: return DuduTheme.duduTextDim
        }
    }

    private var background: Color {
        switch style {
        case .primary: return DuduTheme.pink
        case .secondary: return DuduTheme.duduIconChip
        case .quiet: return Color.clear
        }
    }
}
