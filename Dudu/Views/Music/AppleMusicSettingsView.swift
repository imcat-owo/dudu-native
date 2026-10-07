import SwiftUI

// MARK: - AppleMusicSettingsView · Apple Music 设置 (D19, 2026-10-07)
//
// Her developer token, pasted by her — NEVER hardcoded, NEVER shipped.
// Stored in the keychain (not UserDefaults). Without token / authorization /
// subscription, the room says so honestly instead of faking a player.

struct AppleMusicSettingsView: View {
    @StateObject private var dj = AIDJ.shared

    @State private var token: String = ""
    @State private var showToken = false
    @State private var savedFlash = false
    @State private var authorizing = false

    private var hasToken: Bool {
        !(MusicKeychain.developerToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusCard
                tokenCard
                stepsCard
            }
            .padding(DuduTheme.pagePadding)
        }
        .background(DuduTheme.duduBackground)
        .navigationTitle("Apple Music")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            token = MusicKeychain.developerToken ?? ""
            Task { await dj.refreshAppleAuthState() }
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("连接状态")
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
            Text(dj.appleAuthState.hint)
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                authorizing = true
                Task {
                    await dj.appleAuthorize()
                    authorizing = false
                }
            } label: {
                Text(authorizing ? "连接中…" : "连接 Apple Music")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DuduTheme.pinkSoft, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(authorizing || !hasToken)
            if !hasToken {
                Text("先在下面粘贴 developer token，才能点连接。")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: - Developer token (hers)

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Developer Token")
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
            Text("她自己的 token，存在手机钥匙串里，不进代码、不上传。")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            HStack(spacing: 8) {
                Group {
                    if showToken {
                        TextField("粘贴 token", text: $token)
                    } else {
                        SecureField("粘贴 token", text: $token)
                    }
                }
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduText)
                .padding(8)
                .background(DuduTheme.duduBackground, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                Button {
                    showToken.toggle()
                } label: {
                    Image(systemName: showToken ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                Button("保存") {
                    let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    MusicKeychain.developerToken = t.isEmpty ? nil : t
                    savedFlash = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        savedFlash = false
                    }
                    Task { await dj.refreshAppleAuthState() }
                }
                .font(DuduTheme.captionFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(DuduTheme.pinkSoft, in: Capsule())
                .buttonStyle(.plain)
                if hasToken {
                    Button("清除") {
                        MusicKeychain.developerToken = nil
                        MusicKeychain.userToken = nil
                        MusicKeychain.cachedAuthState = nil
                        token = ""
                        Task { await dj.refreshAppleAuthState() }
                    }
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduDestructive)
                    .buttonStyle(.plain)
                }
                if savedFlash {
                    Text("已保存到钥匙串")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
        }
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: - Honest three steps

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("连上 Apple Music 需要三步")
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1)")
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .frame(width: 20, height: 20)
                        .background(DuduTheme.pinkSoft, in: Circle())
                    Text(s)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    private var steps: [String] {
        [
            "Apple Developer 后台：给这个 App ID 打开 MusicKit 服务，然后把上面的 developer token 粘贴进来。",
            "在这台手机上点「连接 Apple Music」，允许嘟嘟访问媒体库。",
            "这个 Apple ID 需要有 Apple Music 订阅，曲库的歌才能播。",
        ]
    }
}
