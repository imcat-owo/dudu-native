import SwiftUI
import UIKit

// MARK: - ProviderQRShareView · 把单个服务分享成二维码
//
// Native port of old Dudu's ShareSection (api-settings.tsx B12).
// Same user-visible behavior:
//   - "连 key 一起分享" toggle (apigroup.share.withKeys)
//   - QR code of the dudu-provider:v1: text (apigroup.share.qr)
//   - explicit plaintext-key warning when keys are included
//     (apigroup.share.keyWarning) — honest security note, unchanged
//   - copy share text + system share sheet
//
// A provider config is small (no wallpaper/blob), so the QR always fits;
// the too-big branch is still handled honestly instead of assumed away.

struct ProviderQRShareView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    let instanceId: String

    @State private var includeKeys = false
    @State private var copied = false
    @State private var showSystemShare = false
    @State private var shareURL: URL?

    private var instance: ProviderInstance? {
        store.instance(for: instanceId)
    }

    /// Old Dudu's QR_MAX_BYTES (theme/share.ts). Provider payloads are far
    /// smaller, but the guard stays: a huge key pool could still overflow.
    private let qrMaxBytes = 2400

    private var shareText: String {
        guard let instance else { return "" }
        let baseURL = instance.effectiveCustomBaseURL
            ?? ProviderShareVendor.officialBaseURL(for: instance.providerType)
        let key = includeKeys
            ? (ProviderKeychainHelper.loadAPIKey(instanceId: instance.id, caller: "ProviderQRShareView") ?? "")
            : ""
        let modelId = store.entries(for: instance.id).first?.model.id ?? ""
        return ProviderShareCodec.encodeShare(
            name: instance.label,
            vendor: ProviderShareVendor.vendorString(for: instance.providerType),
            baseUrl: baseURL,
            apiKey: key,
            model: modelId,
            includeKeys: includeKeys
        )
    }

    private var qrFits: Bool {
        !shareText.isEmpty && shareText.utf8.count <= qrMaxBytes
    }

    private var isOAuth: Bool {
        instance?.credentialType == .oauth
    }

    var body: some View {
        List {
            Section {
                if let instance {
                    providerRow(instance)
                }
                if !isOAuth {
                    Toggle(AppLocalized("apigroup.share.withKeys"), isOn: $includeKeys)
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                        .tint(DuduTheme.pink)
                } else {
                    Text(AppLocalized("shareimport.oauthNote"))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            } header: {
                Text(AppLocalized("apigroup.share.title"))
            } footer: {
                Text(AppLocalized("apigroup.share.desc"))
            }

            Section {
                if qrFits {
                    HStack {
                        Spacer()
                        QRCodeImageView(text: shareText, size: 200)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    if includeKeys {
                        Text(AppLocalized("apigroup.share.keyWarning"))
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduDestructive)
                    }
                } else {
                    Text(AppLocalized("shareimport.qrTooBig"))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = shareText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    HStack {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(DuduTheme.pink)
                        Text(copied
                             ? AppLocalized("shareimport.copied")
                             : AppLocalized("shareimport.copyText"))
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.duduText)
                    }
                }
                .disabled(shareText.isEmpty)
                Button {
                    writeShareFile()
                    showSystemShare = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(DuduTheme.pink)
                        Text(AppLocalized("common.share"))
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.duduText)
                    }
                }
                .disabled(shareText.isEmpty)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AppLocalized("apigroup.share.qr"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSystemShare) {
            if let url = shareURL {
                ProviderShareSheet(url: url)
            }
        }
    }

    private func providerRow(_ instance: ProviderInstance) -> some View {
        HStack(spacing: 12) {
            Image(systemName: instance.providerType.iconName)
                .font(.system(size: 15))
                .foregroundStyle(DuduTheme.pink)
                .frame(width: 30, height: 30)
                .background(DuduTheme.pinkSoft)
                .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.label)
                    .font(DuduTheme.bodyFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduText)
                Text(instance.providerType.displayName)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
    }

    private func writeShareFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dudu-provider-share.txt")
        try? shareText.write(to: url, atomically: true, encoding: .utf8)
        shareURL = url
    }
}

// MARK: - System share sheet (local; mirrors ThemePackShareView's pattern)

private struct ProviderShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
