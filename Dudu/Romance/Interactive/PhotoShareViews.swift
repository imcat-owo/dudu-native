//
//  D20b: 主动发照片 UI —— PhotoShareSectionView（供「我们的空间」接线）。
//
//  接线签名：PhotoShareSectionView()
//  coordinator 在 Our Space 里合适的位置放 PhotoShareSectionView() 即可。
//
//  规矩：零 emoji；颜色只走 DuduTheme；文案不用纯黑纯白。

import SwiftUI

/// 主动发照片设置区：总开关（OPT-IN，默认关）+ 状态 + 立刻发一张 + 分享记录。
@MainActor
public struct PhotoShareSectionView: View {
    @State private var enabled: Bool = false
    @State private var status: String = ""
    @State private var log: [PhotoShareLogEntry] = []
    @State private var pipelineConnected: Bool = false
    @State private var notice: String? = nil
    @State private var sharing: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            Divider().background(DuduTheme.duduDivider)
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("主动发照片")
                        .font(DuduTheme.titleFont())
                        .foregroundColor(DuduTheme.duduText)
                    Text("每天在安静的时刻，她可能会收到你分享的瞬间")
                        .font(DuduTheme.captionFont())
                        .foregroundColor(DuduTheme.duduTextDim)
                }
            }
            .tint(DuduTheme.pink)
            .onChange(of: enabled) { newValue in
                Task { await PhotoShareManager.shared.setEnabled(newValue) }
                Task { await reload() }
            }

            Text(status)
                .font(DuduTheme.captionFont())
                .foregroundColor(DuduTheme.duduTextDim)

            if !pipelineConnected {
                Text("图片管线还没接好：现在点「发一张」会诚实地告诉她还没接好，不会用假图顶上。")
                    .font(DuduTheme.captionFont())
                    .foregroundColor(DuduTheme.duduTextDim)
                    .padding(10)
                    .background(DuduTheme.pinkSoft)
                    .cornerRadius(DuduTheme.radiusChip)
            }

            Button(action: shareNow) {
                HStack {
                    if sharing { ProgressView().scaleEffect(0.8) }
                    Text(sharing ? "正在生成…" : "现在发一张")
                        .font(DuduTheme.bodyFont(weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(DuduTheme.pinkSoft)
                .foregroundColor(DuduTheme.kitty)
                .cornerRadius(DuduTheme.radiusPill)
            }
            .disabled(sharing)

            if let notice {
                Text(notice)
                    .font(DuduTheme.captionFont())
                    .foregroundColor(DuduTheme.duduTextDim)
            }

            if !log.isEmpty {
                Text("分享记录")
                    .font(DuduTheme.titleFont())
                    .foregroundColor(DuduTheme.duduText)
                    .padding(.top, 4)
                ForEach(log.prefix(8)) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.caption.isEmpty ? "（无文案）" : entry.caption)
                                .font(DuduTheme.bodyFont())
                                .foregroundColor(DuduTheme.duduText)
                                .lineLimit(2)
                            Text(Self.dateLine(entry.at))
                                .font(DuduTheme.captionFont())
                                .foregroundColor(DuduTheme.duduTextDim)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(DuduTheme.pagePadding)
        .background(DuduTheme.duduCard)
        .cornerRadius(DuduTheme.radiusCard)
        .task { await reload() }
    }

    private var headerRow: some View {
        HStack {
            Text("主动发照片")
                .font(DuduTheme.titleFont())
                .foregroundColor(DuduTheme.duduText)
            Spacer()
            Text(enabled ? "已开启" : "已关闭")
                .font(DuduTheme.captionFont())
                .foregroundColor(DuduTheme.duduTextDim)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DuduTheme.duduDivider)
                .cornerRadius(DuduTheme.radiusPill)
        }
    }

    private func reload() async {
        let mgr = PhotoShareManager.shared
        enabled = await mgr.isEnabled()
        status = await mgr.statusLine()
        log = await mgr.log()
        pipelineConnected = await PhotoShareManager.imagePipeline != nil
    }

    private func shareNow() {
        notice = nil
        sharing = true
        Task {
            do {
                // 她在设置页亲手点的「现在发一张」：这是她要的，不是惊喜。
                // 文案由对话框里的 AI 写——这里只给一句兜底，绝不编假文案冒充。
                let result = try await PhotoShareManager.shared.shareNow(
                    hint: "", personaLook: "", caption: "")
                notice = "照片已生成：\(result.imageURL.lastPathComponent)。去对话框里发给她吧，记得配一句自然的话。"
            } catch {
                notice = error.localizedDescription
            }
            sharing = false
            await reload()
        }
    }

    private static func dateLine(_ at: TimeInterval) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm"
        return fmt.string(from: Date(timeIntervalSince1970: at))
    }
}
