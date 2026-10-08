import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - FontUploadView · 字体
//
// Old Dudu ("appearance.fontUpload", Kelivo-style): upload a ttf/otf/ttc
// in Appearance → Font. Native edition, wired to the existing
// FontSettings engine:
//
// - The uploaded file is the font FAMILY; sizes still scale through the
//   three FontSettings axes (输入框 / 消息 / 界面), which you tune in
//   设置 → 字号. Upload changes the family, not the scale.
// - The font lives outside theme packs and applies app-wide (code keeps
//   the system monospace so it stays readable).

struct FontUploadView: View {
    @ObservedObject private var fonts = CustomFontManager.shared
    @State private var showPicker = false
    @State private var notice: String?
    @State private var noticeIsError = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    DuduIcon(systemName: "textformat")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DuduTheme.pink)
                        .frame(width: 32, height: 32)
                        .background(DuduTheme.pinkSoft)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前字体")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                        Text(fonts.displayName ?? "系统默认")
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.duduText)
                            .lineLimit(1)
                    }
                    Spacer()
                    if fonts.isCustomActive {
                        Button("恢复系统字体") {
                            fonts.clear()
                            flash("已恢复系统字体。", error: false)
                        }
                        .font(DuduTheme.captionFont(weight: .medium))
                        .foregroundStyle(DuduTheme.duduDestructive)
                    }
                }
                .padding(.vertical, 4)

                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Spacer()
                        Text("选择字体文件")
                            .font(DuduTheme.bodyFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduCard)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .background(DuduTheme.pink)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)

                if let notice {
                    Text(notice)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(noticeIsError ? DuduTheme.duduDestructive : DuduTheme.duduTextDim)
                }
            } header: {
                DuduSectionTitle("上传字体")
            } footer: {
                DuduSectionFooter {
                    Text("支持 .ttf / .otf / .ttc。上传后 App 内文字都换成这个字体（代码仍用系统等宽字体）。字号大小去「设置 → 字号」调，那里管缩放、这里管字体。")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("嘟嘟把 App 打扮成你的样子")
                        .font(previewFont(size: 15, weight: .semibold))
                    Text("先试穿，满意了再存档。The quick brown fox jumps over the lazy dog. 1234567890")
                        .font(previewFont(size: 13, weight: .regular))
                    Text("上传的字体只管字形，不管大小。")
                        .font(previewFont(size: 11, weight: .regular))
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .padding(.vertical, 6)
            } header: {
                DuduSectionTitle("预览")
            }
        }
        .duduCardList()
        .navigationTitle("字体")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            FontDocumentPicker { url in
                pickFont(url)
            }
        }
    }

    private func previewFont(size: CGFloat, weight: Font.Weight) -> Font {
        if let family = fonts.activePostScriptName {
            return Font.custom(family, size: size)
        }
        return .system(size: size, weight: weight)
    }

    private func pickFont(_ url: URL) {
        do {
            let name = try fonts.importFont(from: url)
            flash("已应用字体「\(name)」。", error: false)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            flash(msg, error: true)
        }
    }

    private func flash(_ text: String, error: Bool) {
        notice = text
        noticeIsError = error
    }
}

// MARK: - Font file picker

private struct FontDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.font])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
