import SwiftUI
import UniformTypeIdentifiers

// MARK: - FilesBrowserView · Wave 2 Item 7
//
// iOS-Files-simple browser over the app's user-visible directories,
// in the html-2 定稿 cream + white-card style (duduCardList pattern).
//
// Two scopes:
//   - 我的文件 (library.scopeShared): DuduPaths.duduSharedPersistentDir —
//     FileProvider-visible ("On My iPhone → Dudu → shared"). Full actions:
//     preview, ShareLink, 导入 (fileImporter copies in), delete (confirmed).
//   - 聊天附件 (library.scopeAttachments): every session's
//     duduAttachmentsPersistentDir + duduUploadsDir, aggregated read-only.
//     Deleting chat attachments is deliberately not offered: it would break
//     message references in the chat they belong to.
//
// Preview is a built-in sheet, no QuickLook bridging: images render,
// text files render, everything else shows file info + a working Share
// button. Every button is wired — no dead UI.
//
// i18n via AppLocalized (keys listed for the coordinator — do NOT edit
// Localizable.xcstrings). New keys: library.knowledgeSection,
// library.scope, library.scopeShared, library.scopeAttachments,
// library.import, library.importFailed, library.emptyFilesTitle,
// library.emptyFilesHint, library.emptyAttachmentsTitle,
// library.emptyAttachmentsHint, library.deleteConfirmTitle,
// library.deleteConfirmMessage, library.delete, library.cancel,
// library.share, library.previewUnavailable.

// MARK: - Model

/// One row in the browser. Hashable so the sheet/confirmation state can
/// hold it directly.
struct DuduFileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let size: Int64
    let modified: Date
    let isDirectory: Bool
    let canDelete: Bool

    var id: String { url.path }

    /// SF Symbol name for the file type, rendered via DuduIcon.
    var iconName: String {
        if isDirectory { return "folder" }
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff":
            return "photo"
        case "mp4", "mov", "m4v", "avi", "mkv":
            return "video"
        case "mp3", "m4a", "wav", "aac", "flac", "ogg", "opus", "aiff":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "txt", "md", "markdown", "json", "xml", "csv", "log", "yaml", "yml":
            return "doc.text"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox"
        default:
            return "doc"
        }
    }

    var isPreviewableImage: Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff"]
            .contains(url.pathExtension.lowercased())
    }

    var isPreviewableText: Bool {
        ["txt", "md", "markdown", "json", "xml", "csv", "log", "yaml", "yml"]
            .contains(url.pathExtension.lowercased())
    }
}

enum FilesScope: Hashable {
    case shared
    case attachments
}

@MainActor
final class FilesBrowserModel: ObservableObject {
    @Published var scope: FilesScope = .shared
    @Published var files: [DuduFileItem] = []
    @Published var notice: String?

    /// The user-visible imports directory. Created on demand so the
    /// browser never shows a phantom-missing folder.
    var sharedDir: URL {
        let dir = DuduPaths.duduSharedPersistentDir
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    func refresh() {
        notice = nil
        switch scope {
        case .shared:
            files = listFiles(in: sharedDir, canDelete: true)
        case .attachments:
            files = attachmentFiles()
        }
    }

    func delete(_ item: DuduFileItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
        } catch {
            notice = error.localizedDescription
        }
        refresh()
    }

    /// Copy picked files into the shared directory, de-duplicating names
    /// ("report.pdf" → "report 2.pdf") instead of overwriting.
    func importFiles(_ urls: [URL]) {
        let fm = FileManager.default
        let dir = sharedDir
        var failures = 0
        for url in urls {
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            let dest = uniqueDestination(for: url.lastPathComponent, in: dir)
            do {
                try fm.copyItem(at: url, to: dest)
            } catch {
                failures += 1
            }
        }
        if failures > 0 {
            notice = AppLocalized("library.importFailed")
        }
        refresh()
    }

    // MARK: - Scanning

    private func listFiles(in dir: URL, canDelete: Bool) -> [DuduFileItem] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { makeItem(url: $0, canDelete: canDelete) }
            .sorted { $0.modified > $1.modified }
    }

    private func attachmentFiles() -> [DuduFileItem] {
        let fm = FileManager.default
        let base = DuduPaths.duduPersistentBase
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: base.path, isDirectory: &isDir),
              isDir.boolValue,
              let sessions = try? fm.contentsOfDirectory(
                at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        var out: [DuduFileItem] = []
        for sessionDir in sessions {
            var sessionIsDir: ObjCBool = false
            guard fm.fileExists(atPath: sessionDir.path, isDirectory: &sessionIsDir),
                  sessionIsDir.boolValue
            else { continue }
            let sid = sessionDir.lastPathComponent
            out += listFiles(in: DuduPaths.duduAttachmentsPersistentDir(for: sid), canDelete: false)
            out += listFiles(in: DuduPaths.duduUploadsDir(for: sid), canDelete: false)
        }
        return out.sorted { $0.modified > $1.modified }
    }

    private func makeItem(url: URL, canDelete: Bool) -> DuduFileItem? {
        let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
        return DuduFileItem(
            url: url,
            name: url.lastPathComponent,
            size: Int64(values?.fileSize ?? 0),
            modified: values?.contentModificationDate ?? .distantPast,
            isDirectory: values?.isDirectory ?? false,
            canDelete: canDelete && !(values?.isDirectory ?? false)
        )
    }

    private func uniqueDestination(for name: String, in dir: URL) -> URL {
        let ns = name as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var candidate = dir.appendingPathComponent(name)
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            candidate = dir.appendingPathComponent(numbered)
            i += 1
        }
        return candidate
    }
}

// MARK: - View

struct FilesBrowserView: View {
    @StateObject private var model = FilesBrowserModel()
    @State private var showImporter = false
    @State private var pendingDelete: DuduFileItem?
    @State private var previewItem: DuduFileItem?

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbarRow
            if let notice = model.notice {
                Text(notice)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .padding(.horizontal, DuduTheme.pagePadding)
            }
            if model.files.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.importFiles(urls)
            case .failure(let error):
                model.notice = error.localizedDescription
            }
        }
        .confirmationDialog(
            AppLocalized("library.deleteConfirmTitle"),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppLocalized("library.delete"), role: .destructive) {
                if let item = pendingDelete { model.delete(item) }
                pendingDelete = nil
            }
            Button(AppLocalized("library.cancel"), role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text(AppLocalized("library.deleteConfirmMessage"))
        }
        .sheet(item: $previewItem) { item in
            FilePreviewSheet(item: item)
        }
        .onAppear { model.refresh() }
        .onChange(of: model.scope) { _, _ in model.refresh() }
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            Picker(AppLocalized("library.scope"), selection: $model.scope) {
                Text(AppLocalized("library.scopeShared")).tag(FilesScope.shared)
                Text(AppLocalized("library.scopeAttachments")).tag(FilesScope.attachments)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            Spacer()
            if model.scope == .shared {
                Button {
                    showImporter = true
                } label: {
                    HStack(spacing: 4) {
                        DuduIcon(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text(AppLocalized("library.import"))
                            .font(DuduTheme.bodyFont(weight: .semibold))
                    }
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DuduTheme.pinkSoft, in: Capsule())
                }
                .accessibilityLabel(AppLocalized("library.import"))
            }
        }
        .padding(.horizontal, DuduTheme.pagePadding)
    }

    // MARK: - List

    private var fileList: some View {
        List {
            ForEach(model.files) { item in
                fileRow(item)
            }
        }
        .duduCardList()
        .frame(height: 300)
    }

    private func fileRow(_ item: DuduFileItem) -> some View {
        HStack(spacing: 12) {
            DuduIcon(systemName: item.iconName)
                .font(.system(size: 15))
                .foregroundStyle(DuduTheme.pink)
                .frame(width: 30, height: 30)
                .background(DuduTheme.pinkSoft)
                .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(DuduTheme.bodyFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduText)
                    .lineLimit(1)
                Text("\(Self.byteFormatter.string(fromByteCount: item.size)) · \(Self.dateString(item.modified))")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .lineLimit(1)
            }
            Spacer()
            ShareLink(item: item.url, preview: SharePreview(item.name)) {
                DuduIcon(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            .accessibilityLabel(AppLocalized("library.share"))
            if item.canDelete {
                Button {
                    pendingDelete = item
                } label: {
                    DuduIcon(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(DuduTheme.duduDestructive)
                }
                .accessibilityLabel(AppLocalized("library.delete"))
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { previewItem = item }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            DuduIcon(systemName: "folder")
                .font(.system(size: 28))
                .foregroundStyle(DuduTheme.duduTextDim)
            Text(model.scope == .shared
                ? AppLocalized("library.emptyFilesTitle")
                : AppLocalized("library.emptyAttachmentsTitle"))
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
            Text(model.scope == .shared
                ? AppLocalized("library.emptyFilesHint")
                : AppLocalized("library.emptyAttachmentsHint"))
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, DuduTheme.pagePadding)
    }

    private static func dateString(_ date: Date) -> String {
        DateFormatter.localizedString(
            from: date, dateStyle: .medium, timeStyle: .short)
    }
}

// MARK: - Preview sheet

/// Built-in file preview: images render, text files render (capped at
/// 200 KB), anything else shows file info + a working Share button.
/// Plain SwiftUI, no QuickLook bridging to go stale.
struct FilePreviewSheet: View {
    let item: DuduFileItem
    @Environment(\.dismiss) private var dismiss
    @State private var loadedImage: UIImage?
    @State private var loadedText: String?
    @State private var loadFailed = false

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if let loadedImage {
                    Image(uiImage: loadedImage)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else if let loadedText {
                    ScrollView {
                        Text(loadedText)
                            .font(DuduTheme.monoFont(size: 12))
                            .foregroundStyle(DuduTheme.duduText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    infoFallback
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("library.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !item.isDirectory {
                        ShareLink(item: item.url, preview: SharePreview(item.name)) {
                            DuduIcon(systemName: "square.and.arrow.up")
                                .foregroundStyle(DuduTheme.pink)
                        }
                        .accessibilityLabel(AppLocalized("library.share"))
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private var infoFallback: some View {
        VStack(spacing: 10) {
            DuduIcon(systemName: item.iconName)
                .font(.system(size: 40))
                .foregroundStyle(DuduTheme.duduTextDim)
            Text(item.name)
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
                .multilineTextAlignment(.center)
            Text("\(Self.byteFormatter.string(fromByteCount: item.size)) · \(DateFormatter.localizedString(from: item.modified, dateStyle: .medium, timeStyle: .short))")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            if !item.isDirectory && !loadFailed {
                ProgressView()
            } else if !item.isDirectory {
                Text(AppLocalized("library.previewUnavailable"))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
        .padding()
    }

    private func load() {
        guard !item.isDirectory else { return }
        if item.isPreviewableImage {
            if let img = UIImage(contentsOfFile: item.url.path) {
                loadedImage = img
            } else {
                loadFailed = true
            }
        } else if item.isPreviewableText, item.size <= 200 * 1024 {
            // Read off-main; text decode can take a beat on large files.
            let url = item.url
            Task.detached(priority: .userInitiated) {
                let text = try? String(contentsOf: url, encoding: .utf8)
                await MainActor.run {
                    if let text {
                        loadedText = text
                    } else {
                        loadFailed = true
                    }
                }
            }
        } else {
            loadFailed = true
        }
    }
}
