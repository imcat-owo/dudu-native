import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - ThemePackShareView · 主题包导入 / 导出 / 分享
//
// Old Dudu ("主题包可以导出分享（JSON/二维码）", theme-design.md §7),
// native edition. The share format is the theme-pack JSON itself
// (AppearanceThemePack.asJSONObject); unknown fields are ignored on
// import (forward compatibility — decode fills from .default).
//
//   导出：复制 JSON / 系统分享 / 存到文件 / 二维码（小包才有）
//   导入：粘贴 JSON / 从文件导入 → 验证 → 试穿（横幅里保存/放弃）
//   已保存：保存当前 / 应用 / 重命名 / 删除（走保存主题库）
//
// QR 说明（诚实版）：只做导出二维码（系统相机扫码可复制 JSON 文本，
// 再粘贴到下方导入）；App 内扫码直达导入暂不支持。

struct ThemePackShareView: View {
    @State private var includeWallpaper = false
    @State private var exportJSON = ""
    @State private var importText = ""
    @State private var importError: String?
    @State private var importStagedName: String?
    @State private var showShare = false
    @State private var showExportPicker = false
    @State private var showImportPicker = false
    @State private var exportFileURL: URL?
    @State private var savedThemes: [AppearanceSavedTheme] = []
    @State private var saveName = ""
    @State private var showSaveAlert = false
    @State private var renameTarget: AppearanceSavedTheme?
    @State private var renameText = ""
    @State private var deleteTarget: AppearanceSavedTheme?

    private let qrMaxBytes = 2400 // old Dudu share.ts QR_MAX_BYTES

    var body: some View {
        List {
            exportSection
            importSection
            savedSection
        }
        .duduCardList()
        .navigationTitle("主题包")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshExport()
            refreshSaved()
        }
        .onChange(of: includeWallpaper) { refreshExport() }
        .sheet(isPresented: $showShare) {
            if let url = exportFileURL {
                ThemePackShareSheet(url: url)
            }
        }
        .sheet(isPresented: $showExportPicker) {
            if let url = exportFileURL {
                ThemePackDocumentExportPicker(url: url)
            }
        }
        .sheet(isPresented: $showImportPicker) {
            ThemePackDocumentImportPicker { url in
                importFromFile(url)
            }
        }
        .alert("保存当前主题", isPresented: $showSaveAlert) {
            TextField("名字", text: $saveName)
            Button("取消", role: .cancel) {}
            Button("保存") { saveCurrent() }
        }
        .alert("重命名", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("新名字", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("确定") { renameSaved() }
        }
        .alert("删除这个主题？", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteSaved() }
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            Toggle("导出时包含壁纸", isOn: $includeWallpaper)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
                .tint(DuduTheme.pink)
            HStack {
                Text("大小")
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Text(byteCount(exportJSON))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            HStack(spacing: 10) {
                shareButton("复制 JSON", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = exportJSON
                }
                shareButton("分享", systemImage: "square.and.arrow.up") {
                    writeExportFile()
                    showShare = true
                }
                shareButton("存到文件", systemImage: "folder") {
                    writeExportFile()
                    showExportPicker = true
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
            if qrFits {
                VStack(alignment: .leading, spacing: 8) {
                    if let image = qrImage(from: exportJSON) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 168, height: 168)
                            .background(DuduTheme.duduCard)
                            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                            .overlay(RoundedRectangle(cornerRadius: DuduTheme.radiusChip)
                                .stroke(DuduTheme.duduDivider, lineWidth: 1))
                    }
                    Text("用系统相机扫码可复制 JSON 文本，再粘贴到下方导入。App 内扫码直达导入暂不支持。")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                Text(includeWallpaper
                     ? "含壁纸的主题包太大，放不进二维码。关掉「包含壁纸」可生成二维码。"
                     : "主题包太大，放不进二维码。")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        } header: {
            DuduSectionTitle("导出")
        } footer: {
            DuduSectionFooter {
                Text("导出的 JSON 可直接分享给别人，对方在导入区粘贴即可试穿。未知字段会被忽略（向前兼容）。")
            }
        }
    }

    private func shareButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                DuduIcon(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DuduTheme.pink)
                    .frame(width: 40, height: 40)
                    .background(DuduTheme.pinkSoft)
                    .clipShape(Circle())
                Text(title)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduText)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Import

    private var importSection: some View {
        Section {
            TextEditor(text: $importText)
                .font(DuduTheme.monoFont(size: 11))
                .foregroundStyle(DuduTheme.duduText)
                .frame(minHeight: 120)
                .overlay(
                    Group {
                        if importText.isEmpty {
                            Text("粘贴主题包 JSON…")
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
            if let err = importError {
                Text(err)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduDestructive)
            }
            if let name = importStagedName {
                Text("「\(name)」已进入试穿，屏幕下方横幅可保存/放弃。")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            HStack(spacing: 10) {
                Button("验证并试穿") { importFromText() }
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduCard)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(DuduTheme.pink)
                    .clipShape(Capsule())
                Button("从文件导入") { showImportPicker = true }
                    .font(DuduTheme.bodyFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(DuduTheme.duduIconChip)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        } header: {
            DuduSectionTitle("导入")
        } footer: {
            DuduSectionFooter {
                Text("导入先试穿：验证通过后主题立即预览，不满意在横幅里点放弃，什么都不会留下。")
            }
        }
    }

    // MARK: - Saved themes

    private var savedSection: some View {
        Section {
            Button {
                saveName = AppearanceStudio.shared.currentThemePack().name
                showSaveAlert = true
            } label: {
                HStack {
                    DuduIcon(systemName: "bookmark.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DuduTheme.pink)
                        .frame(width: 28, height: 28)
                        .background(DuduTheme.pinkSoft)
                        .clipShape(Circle())
                    Text("保存当前主题")
                        .font(DuduTheme.bodyFont(weight: .medium))
                        .foregroundStyle(DuduTheme.duduText)
                    Spacer()
                    DuduIcon(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
            .buttonStyle(.plain)
            if savedThemes.isEmpty {
                Text("还没有保存的主题。调好一个喜欢的主题后点上方保存。")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            ForEach(savedThemes) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.duduText)
                            .lineLimit(1)
                        Text(Self.dateString(item.savedAt))
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    Spacer()
                    Button("应用") { applySaved(item) }
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.pink)
                    Button {
                        renameTarget = item
                        renameText = item.name
                    } label: {
                        DuduIcon(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    .buttonStyle(.plain)
                    Button {
                        deleteTarget = item
                    } label: {
                        DuduIcon(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(DuduTheme.duduDestructive)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            DuduSectionTitle("已保存")
        }
    }

    // MARK: - Logic

    private func refreshExport() {
        let pack = AppearanceStudio.shared.exportThemePack(includeWallpaper: includeWallpaper)
        var obj = pack.asJSONObject()
        obj["ok"] = true
        if let data = try? JSONSerialization.data(withJSONObject: obj,
                                                 options: [.sortedKeys, .prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            exportJSON = json
        } else {
            exportJSON = ""
        }
    }

    private var qrFits: Bool {
        !includeWallpaper
            && !exportJSON.isEmpty
            && exportJSON.utf8.count <= qrMaxBytes
    }

    private func byteCount(_ s: String) -> String {
        let bytes = s.utf8.count
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    private func qrImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func writeExportFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dudu-theme-pack.json")
        try? exportJSON.write(to: url, atomically: true, encoding: .utf8)
        exportFileURL = url
    }

    private func importFromText() {
        importError = nil
        importStagedName = nil
        do {
            let pack = try validateImport(importText)
            try ThemeTryOn.shared.stage(pack: pack, label: "导入试穿：\(pack.name)")
            importStagedName = pack.name
        } catch {
            importError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func importFromFile(_ url: URL) {
        importError = nil
        importStagedName = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            importError = "读不到这个文件。"
            return
        }
        importText = text
        importFromText()
    }

    enum ImportError: LocalizedError {
        case empty, notJSON, notPack(String)
        var errorDescription: String? {
            switch self {
            case .empty: return "粘贴的内容是空的。"
            case .notJSON: return "不是有效的 JSON。"
            case .notPack(let why): return "不是主题包：\(why)"
            }
        }
    }

    /// Same validation the ObjC offload path uses (decode fills missing
    /// fields from .default; rejects non-pack JSON).
    private func validateImport(_ text: String) throws -> AppearanceThemePack {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.empty }
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ImportError.notJSON }
        do {
            return try AppearanceThemePack.decode(obj)
        } catch {
            throw ImportError.notPack("缺少主题包字段（如 userBubbleRadius / colorsLight 等）。")
        }
    }

    private func refreshSaved() {
        savedThemes = AppearanceStudio.shared.savedThemes()
    }

    private func saveCurrent() {
        let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = AppearanceStudio.shared.saveCurrentTheme(name: name.isEmpty ? nil : name)
        refreshSaved()
    }

    private func applySaved(_ item: AppearanceSavedTheme) {
        if AppearanceStudio.shared.applySavedTheme(id: item.id) {
            importError = nil
        } else {
            importError = "应用失败：找不到这个主题的数据文件。"
        }
    }

    private func renameSaved() {
        guard let item = renameTarget else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = AppearanceStudio.shared.renameSavedTheme(id: item.id, name: name)
        renameTarget = nil
        refreshSaved()
    }

    private func deleteSaved() {
        guard let item = deleteTarget else { return }
        _ = AppearanceStudio.shared.deleteSavedTheme(id: item.id)
        deleteTarget = nil
        refreshSaved()
    }

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: date)
    }
}

// MARK: - Share sheet / pickers (local; mirrors BackupDelivery's pattern)

private struct ThemePackShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ThemePackDocumentExportPicker: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url])
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

private struct ThemePackDocumentImportPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .plainText])
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
