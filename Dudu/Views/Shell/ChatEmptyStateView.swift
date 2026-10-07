import SwiftUI

/// First-run empty state for the Chat tab (plan §7, step 7 acceptance).
///
/// This is REAL UI, not a stand-in: with no provider configured it points at
/// Settings; the step-2 Chat builder keeps this view and presents the real
/// ChatView once a provider exists. The "chat screen under construction" line
/// is honest about what C1 does and does not ship.
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
                Image(systemName: "sparkles")
                    .font(.system(size: FontSettings.shared.scaledApp(30), weight: .medium))
                    .foregroundStyle(DuduTheme.pink)
            }
            .padding(.bottom, 4)

            Text("开始聊天")
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)

            Text(hasEnabledProvider
                 ? "聊天界面正在构建中（Phase C 第 2 步），模型服务已经就绪，很快就能开聊。"
                 : "还没有配置模型服务，先去设置里添加一个，回来就能开聊。")
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if !hasEnabledProvider {
                Button {
                    selection = .settings
                } label: {
                    Text("前往设置")
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
