import SwiftUI

/// STUB — honest stand-in for the Settings tab.
///
/// The real SettingsView (模型服务 → ProviderListView, 外观 → AppearanceView,
/// 字体, 关于) is built by the Phase C step-6 builder. This stub ships no fake
/// rows and no dead buttons; it is replaced wholesale by that builder.
struct SettingsStubView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous)
                    .fill(DuduTheme.duduIconChip)
                    .frame(width: 64, height: 64)
                Image(systemName: "gearshape")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(DuduTheme.pink)
            }

            Text("设置")
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)

            Text("设置页（模型服务 / 外观 / 字体 / 关于）由 Phase C 后续步骤构建。")
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DuduTheme.duduBackground)
    }
}
