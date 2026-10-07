import SwiftUI

// MARK: - ApiKeyFieldView · API Key 输入
//
// SecureField for key entry. The key goes straight to the Keychain via
// ProviderConfigStore.saveAPIKey and is NEVER displayed back — only the
// saved-at status is shown.

struct ApiKeyFieldView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    let instanceId: String
    @State private var draft = ""
    @State private var savedMessage: String?

    private var savedAt: Date {
        ProviderConfigStore.apiKeySavedAt(instanceId: instanceId)
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
                    ProviderConfigStore.saveAPIKey(key, instanceId: instanceId)
                    draft = ""
                    savedMessage = "已保存到钥匙串"
                }
                .font(DuduTheme.bodyFont(weight: .medium))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                if savedAt != .distantPast {
                    Button(role: .destructive) {
                        ProviderConfigStore.deleteAPIKey(instanceId: instanceId)
                    } label: {
                        Text("删除 Key")
                            .font(DuduTheme.bodyFont())
                    }
                }
            }

            if savedAt != .distantPast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DuduTheme.success)
                    Text("已保存 · \(savedAt, format: .dateTime.month().day().hour().minute())")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
            if let savedMessage {
                Text(savedMessage)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.success)
            }
            Text("Key 只存钥匙串，永不显示回传")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
        // Refresh when Keychain auth state changes (authRevision bumps on save/delete).
        .id(store.authRevision)
    }
}
