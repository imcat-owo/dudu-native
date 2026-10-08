import SwiftUI
import Security

// MARK: - ApiKeyFieldView · API Key 输入
//
// SecureField for key entry. The key goes straight to the Keychain via
// ProviderKeychainHelper.saveAPIKey and is NEVER displayed back — only the
// saved-at status is shown.

struct ApiKeyFieldView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    let instanceId: String
    @State private var draft = ""
    @State private var savedMessage: String?
    @State private var saveFailed = false

    private var savedAt: Date {
        ProviderKeychainHelper.apiKeySavedAt(instanceId: instanceId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField("粘贴 API Key", text: $draft)
                .font(DuduTheme.bodyFont())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(DuduTheme.duduCard)
                .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                .overlay(
                    RoundedRectangle(cornerRadius: DuduTheme.radiusChip)
                        .stroke(DuduTheme.duduDivider, lineWidth: 1)
                )

            HStack {
                Button("保存") {
                    let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { return }
                    let status = ProviderKeychainHelper.saveAPIKey(key, instanceId: instanceId)
                    if status == errSecSuccess {
                        draft = ""
                        saveFailed = false
                        savedMessage = "已保存到钥匙串"
                    } else {
                        // Honest: the key was NOT saved — say so, with the
                        // Keychain status, instead of claiming success.
                        saveFailed = true
                        savedMessage = "钥匙串保存失败（错误 \(status)），Key 没有保存，请重试"
                    }
                }
                .font(DuduTheme.bodyFont(weight: .medium))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                if savedAt != .distantPast {
                    Button(role: .destructive) {
                        ProviderKeychainHelper.deleteAPIKey(instanceId: instanceId)
                    } label: {
                        Text("删除 Key")
                            .font(DuduTheme.bodyFont())
                    }
                }
            }

            if savedAt != .distantPast {
                HStack(spacing: 6) {
                    DuduIcon(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DuduTheme.success)
                    Text("已保存 · \(savedAt, format: .dateTime.month().day().hour().minute())")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
            if let savedMessage {
                Text(savedMessage)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(saveFailed ? DuduTheme.destructive : DuduTheme.success)
            }
            Text("Key 只存钥匙串，永不显示回传")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
        // Refresh when Keychain auth state changes (authRevision bumps on save/delete).
        .id(store.authRevision)
    }
}
