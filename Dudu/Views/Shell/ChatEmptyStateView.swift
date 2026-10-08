import SwiftUI

/// First-run empty state for the Chat tab (plan §7, step 7 acceptance).
///
/// This is REAL UI, not a stand-in: with no provider configured it points at
/// Settings; once a provider exists, sending a message starts the chat.
struct ChatEmptyStateView: View {
    @Binding var selection: DuduTab
    @EnvironmentObject private var providers: ProviderConfigStore

    private var hasEnabledProvider: Bool {
        providers.instances.contains(where: { $0.isEnabled })
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(DuduTheme.duduIconChip)
                    .frame(width: 76, height: 76)
                DuduIcon(systemName: "sparkles")
                    .font(DuduTheme.appFont(size: 30, weight: .medium))
                    .foregroundStyle(DuduTheme.pink)
            }
            .padding(.bottom, 4)

            Text(L10n.string("chat.empty.title"))
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)

            Text(hasEnabledProvider
                 ? "模型服务已经就绪，在下方输入框发消息开始聊天。"
                 : "还没有配置模型服务，先去设置里添加一个，回来就能开聊。")
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if !hasEnabledProvider {
                Button {
                    selection = .more
                } label: {
                    Text(L10n.string("chat.empty.goSettings"))
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 11)
                        .background(DuduTheme.pinkSoft, in: Capsule())
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DuduTheme.duduBackground)
    }
}
