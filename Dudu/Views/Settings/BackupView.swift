import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - BackupView · 备份与恢复
//
// D8. Settings UI for the P7 backup engine:
// BackupExporter / BackupImporter / BackupHistory / BackupRunController /
// BackupDestinations / RcloneRemoteStore. Every button is wired to the real
// engine — no dead controls, no fake data.
//
// Honesty rules (kept from the old Dudu user manual):
// - API 密钥不备份：key 只存在本机安全区（Keychain），不进备份文件，恢复后要重填。
//   The exporter CAN embed credentials (stage 3a, base64 in secrets.json —
//   encoding, not protection), but this UI always passes
//   includeCredentials=false: keys never enter a package, and the UI says so
//   plainly instead of burying it in fine print.

// MARK: - View model

/// Drives backup / restore against the real engine. Observed by BackupView.
@MainActor
final class BackupCenterModel: ObservableObject {
    @Published var notice: String?
    @Published var noticeIsError = false
    @Published var showPackagePicker = false
    @Published var showFolderPicker = false
    @Published var showRemoteAdd = false
    @Published var showRestoreSheet = false
    @Published var restoreFlow: RestoreFlow = .idle
    /// Bumped after any out-of-band mutation (destination add/remove, package
    /// delete) so the list re-reads the engine's static stores.
    @Published var refreshTick: UInt64 = 0

    var controller: BackupRunController { BackupRunController.shared }
    var history: BackupHistory { BackupHistory.shared }

    // MARK: Backup now

    /// Full pipeline: export → local delivery → destination delivery →
    /// history. Mirrors the engine's own ordering: the local copy in
    /// Dudu ▸ Backups is written first and is never affected by what the
    /// remote/mounted delivery does afterwards.
    func startBackup() {
        let controller = BackupRunController.shared
        guard !controller.isRunning else { return }
        notice = nil
        let categories = BackupCategory.backupable
        let task = Task { @MainActor in
            guard !Task.isCancelled else { return }
            let token = controller.currentToken
            let recordId = BackupHistory.shared.begin(
                backupId: "",
                categories: categories.map(\.rawValue),
                encrypted: false)
            controller.attach(recordId: recordId)
            defer { controller.finished(token: token) }
            do {
                let exporter = BackupExporter()
                let summary = try await exporter.export(
                    options: BackupExporter.Options(
                        categories: Set(categories),
                        // Honesty rule: keys never enter the backup. The user
                        // re-enters them after a restore; the UI says so.
                        includeCredentials: false),
                    onBackupId: { backupId in
                        Task { @MainActor in
                            BackupHistory.shared.setBackupId(recordId, backupId)
                        }
                    },
                    progressDetailed: { text, transient in
                        Task { @MainActor in
                            BackupHistory.shared.log(
                                recordId, text, isTransient: transient)
                            BackupRunController.shared.update(status: text)
                        }
                    })
                // Local first: the canonical copy. Remote failures must never
                // take it down with them.
                let localURL: URL
                do {
                    localURL = try BackupDelivery.moveToVisibleStorage(summary.packageURL)
                } catch {
                    BackupHistory.shared.fail(
                        recordId, "备份已生成，但保存到本机失败：\(error.localizedDescription)")
                    self.notice = "保存到本机失败：\(error.localizedDescription)"
                    self.noticeIsError = true
                    return
                }
                BackupHistory.shared.log(recordId, "已保存到本机备份目录")
                // Then the user's chosen destinations (mounted folders +
                // enabled rclone remotes). Each destination is independent;
                // one unreachable NAS must not fail the others.
                let results = await BackupDestinations.deliver(
                    packageURL: localURL, backupId: summary.backupId)
                let outcomes = results.map { r in
                    BackupHistory.DestinationOutcome(
                        name: r.folderName,
                        succeeded: r.succeeded,
                        detail: r.error ?? r.destination?.lastPathComponent,
                        kind: r.kind,
                        path: r.remotePath)
                }
                let skipped = summary.skippedPaths.map { sp in
                    BackupHistory.SkippedEntry(
                        path: sp.path, size: sp.size, sessionTitle: nil)
                }
                BackupHistory.shared.finish(
                    recordId,
                    totalBytes: summary.totalBytes,
                    skippedFiles: summary.skippedFiles,
                    packageName: localURL.lastPathComponent,
                    destinations: outcomes,
                    skippedEntries: skipped)
                let size = ByteCountFormatter.string(
                    fromByteCount: summary.totalBytes, countStyle: .file)
                let failed = outcomes.filter { !$0.succeeded }
                if failed.isEmpty {
                    self.notice = "备份完成（\(size)），已保存到本机。"
                    self.noticeIsError = false
                } else {
                    self.notice = "备份已生成（\(size)），但 \(failed.count) 个目的地投递失败，详见历史记录。"
                    self.noticeIsError = true
                }
            } catch is CancellationError {
                BackupHistory.shared.fail(recordId, "备份已取消")
                self.notice = "备份已取消。"
                self.noticeIsError = false
            } catch {
                BackupHistory.shared.fail(recordId, error.localizedDescription)
                self.notice = "备份失败：\(error.localizedDescription)"
                self.noticeIsError = true
            }
            self.refreshTick &+= 1
        }
        // Refused when a run is already in flight — the task is cancelled and
        // its body exits before touching history (guard at the top).
        if !controller.started(task: task) {
            notice = "已有备份正在进行。"
            noticeIsError = false
        }
    }

    func stopBackup() {
        BackupRunController.shared.stop()
    }

    // MARK: Local packages

    struct LocalPackage: Identifiable {
        var id: String { url.path }
        let url: URL
        let size: Int64
        let date: Date
    }

    var localPackages: [LocalPackage] {
        let dir = BackupDelivery.backupsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "dudubak" }
            .compactMap { url -> LocalPackage? in
                let vals = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey])
                return LocalPackage(
                    url: url,
                    size: Int64(vals?.fileSize ?? 0),
                    date: vals?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.date > $1.date }
    }

    func deletePackage(_ pkg: LocalPackage) {
        try? FileManager.default.removeItem(at: pkg.url)
        refreshTick &+= 1
    }

    // MARK: Destinations

    func addMountedFolder(_ url: URL) {
        do {
            _ = try BackupDestinations.addDestination(pickedURL: url)
            notice = nil
        } catch {
            notice = "添加目的地失败：\(error.localizedDescription)"
            noticeIsError = true
        }
        refreshTick &+= 1
    }

    // MARK: Restore

    enum RestoreFlow {
        case idle
        case reading
        case confirming(manifest: BackupManifest, url: URL)
        case restoring(lines: [String])
        case done(report: BackupImporter.Report)
        case failed(message: String)
    }

    /// A package picked from the Files browser (copied into tmp by the
    /// picker) or tapped from the local list. Inspected first so the user
    /// sees WHAT is inside before anything is written.
    func restorePicked(_ url: URL) {
        restoreFlow = .reading
        showRestoreSheet = true
        Task {
            do {
                let importer = BackupImporter()
                let manifest = try await importer.inspect(packageURL: url)
                self.restoreFlow = .confirming(manifest: manifest, url: url)
            } catch {
                self.restoreFlow = .failed(message: error.localizedDescription)
            }
        }
    }

    func confirmRestore(url: URL, passphrase: String?) {
        restoreFlow = .restoring(lines: [])
        Task {
            do {
                let importer = BackupImporter()
                var options = BackupImporter.Options()
                let trimmed = (passphrase ?? "").trimmingCharacters(in: .whitespaces)
                options.passphrase = trimmed.isEmpty ? nil : trimmed
                let report = try await importer.import(
                    from: url,
                    options: options,
                    progress: { text in
                        Task { @MainActor in self.appendRestoreLine(text) }
                    })
                self.restoreFlow = .done(report: report)
            } catch {
                self.restoreFlow = .failed(message: error.localizedDescription)
            }
            self.refreshTick &+= 1
        }
    }

    private func appendRestoreLine(_ text: String) {
        if case .restoring(var lines) = restoreFlow {
            // Keep the sheet readable: collapse repeats, cap length.
            if lines.last != text { lines.append(text) }
            if lines.count > 60 { lines.removeFirst(lines.count - 60) }
            restoreFlow = .restoring(lines: lines)
        }
    }

    func closeRestoreSheet() {
        showRestoreSheet = false
        restoreFlow = .idle
    }
}

// MARK: - Document pickers

/// Picks a `.dudubak` package for restore. asCopy:true gives us a stable
/// tmp copy — no security-scope dance, and the original stays untouched.
struct BackupPackagePicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(
            forOpeningContentTypes: [BackupDelivery.contentType], asCopy: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController,
                                context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: BackupPackagePicker
        init(_ parent: BackupPackagePicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { parent.onPick(url) }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

/// Picks a folder to register as a backup destination. Reuses the engine's
/// `BackupDestinations.addDestination`, so the folder becomes an ordinary
/// mounted folder (same bookmark lifecycle) that is additionally tagged as
/// a place backups may go.
struct BackupFolderPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.folder], asCopy: false)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController,
                                context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: BackupFolderPicker
        init(_ parent: BackupFolderPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { parent.onPick(url) }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

// MARK: - Category labels

/// Display names for backup categories (engine rawValues are wire format).
func backupCategoryLabel(_ rawValue: String) -> String {
    switch rawValue {
    case "chats": return "聊天记录"
    case "shared_files": return "共享文件"
    case "skills": return "技能"
    case "memory": return "记忆"
    case "providers": return "模型服务"
    case "mcp_servers": return "MCP 服务器"
    case "environment_variables": return "环境变量"
    case "appearance": return "外观"
    case "voice_corrections": return "语音修正"
    default: return rawValue
    }
}

// MARK: - BackupView · page

struct BackupView: View {
    @StateObject private var model = BackupCenterModel()
    @ObservedObject private var controller = BackupRunController.shared
    @ObservedObject private var history = BackupHistory.shared

    var body: some View {
        List {
            backupActionSection
            destinationSection
            localPackagesSection
            restoreSection
            historySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("备份与恢复")
        .onAppear {
            // Runs left `.running` by a killed process must not spin forever.
            history.reconcileInterrupted()
        }
        .sheet(isPresented: $model.showPackagePicker) {
            BackupPackagePicker(onPick: { url in
                model.showPackagePicker = false
                model.restorePicked(url)
            }, onCancel: {
                model.showPackagePicker = false
            })
        }
        .sheet(isPresented: $model.showFolderPicker) {
            BackupFolderPicker(onPick: { url in
                model.showFolderPicker = false
                model.addMountedFolder(url)
            }, onCancel: {
                model.showFolderPicker = false
            })
        }
        .sheet(isPresented: $model.showRemoteAdd) {
            RemoteAddSheet(onDone: { model.refreshTick &+= 1 })
        }
        .sheet(isPresented: $model.showRestoreSheet, onDismiss: {
            model.restoreFlow = .idle
        }) {
            RestoreSheet(model: model)
        }
    }

    // MARK: Backup action

    private var backupActionSection: some View {
        Section {
            if controller.isRunning {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ProgressView()
                            .tint(DuduTheme.pink)
                        Text(controller.statusText.isEmpty ? "正在备份…" : controller.statusText)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                            .lineLimit(3)
                    }
                    Button(role: .destructive) {
                        model.stopBackup()
                    } label: {
                        Text("停止备份")
                            .font(DuduTheme.bodyFont(weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(DuduTheme.pink)
                }
                .padding(.vertical, 6)
            } else {
                Button {
                    model.startBackup()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.fill.badge.plus")
                            .font(.system(size: 20))
                            .foregroundStyle(DuduTheme.pink)
                            .frame(width: 36, height: 36)
                            .background(DuduTheme.duduIconChip)
                            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("立即备份")
                                .font(DuduTheme.bodyFont(weight: .semibold))
                                .foregroundStyle(DuduTheme.duduText)
                            Text("聊天、文件、技能、记忆、设置全部打包")
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                        Spacer()
                    }
                    .frame(minHeight: 52)
                }
            }
            if let notice = model.notice {
                HStack(spacing: 8) {
                    Image(systemName: model.noticeIsError
                          ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(DuduTheme.pink)
                    Text(notice)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
        } footer: {
            // The honesty rule, stated plainly on the page — not in fine print.
            Text("密钥不进备份：API 密钥与各类密码只保存在本机的安全区里，从不写入备份文件。从备份恢复后，需要重新填写密钥。")
        }
    }

    // MARK: Destinations

    private var destinationSection: some View {
        Section {
            // Local: always on — the engine writes the canonical copy here
            // before any destination delivery runs.
            HStack(spacing: 12) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(DuduTheme.pink)
                    .frame(width: 30, height: 30)
                    .background(DuduTheme.duduIconChip)
                    .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                VStack(alignment: .leading, spacing: 2) {
                    Text("本机")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                    Text("备份包自动保存在此 App 的备份目录（\(model.localPackages.count) 个）")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DuduTheme.pink)
            }
            .frame(minHeight: 44)

            // Mounted folders registered as destinations.
            let _ = model.refreshTick // re-read the engine stores on change
            ForEach(BackupDestinations.eligibleFolders) { folder in
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(DuduTheme.pink)
                        .frame(width: 30, height: 30)
                        .background(DuduTheme.duduIconChip)
                        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                    Text(folder.name)
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { BackupDestinations.isSelected(folder.id) },
                        set: {
                            BackupDestinations.toggle(folder.id, on: $0)
                            model.refreshTick &+= 1
                        }))
                        .labelsHidden()
                        .tint(DuduTheme.pink)
                }
                .frame(minHeight: 44)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        BackupDestinations.forget(folder.id)
                        model.refreshTick &+= 1
                    } label: {
                        Label("移除", systemImage: "trash")
                    }
                }
            }
            Button {
                model.showFolderPicker = true
            } label: {
                Label("添加文件夹…", systemImage: "plus.circle.fill")
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.pink)
            }

            // Rclone remotes (S3 / WebDAV / SMB / SFTP / FTP).
            ForEach(RcloneRemoteStore.remotes) { remote in
                HStack(spacing: 12) {
                    Image(systemName: RcloneBackendCatalog.all
                        .first(where: { $0.type == remote.backend })?.icon ?? "network")
                        .font(.system(size: 15))
                        .foregroundStyle(DuduTheme.pink)
                        .frame(width: 30, height: 30)
                        .background(DuduTheme.duduIconChip)
                        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(remote.name)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                        Text(remoteBackendTitle(remote.backend))
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { remote.enabled },
                        set: {
                            RcloneRemoteStore.setEnabled(remote.name, $0)
                            model.refreshTick &+= 1
                        }))
                        .labelsHidden()
                        .tint(DuduTheme.pink)
                }
                .frame(minHeight: 44)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        RcloneRemoteStore.remove(name: remote.name)
                        model.refreshTick &+= 1
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            Button {
                model.showRemoteAdd = true
            } label: {
                Label("添加远端…", systemImage: "plus.circle.fill")
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.pink)
            }
        } header: {
            Text("备份目的地")
        } footer: {
            Text("本机之外的目的地都是可选项：备份包会逐一投递，某个目的地连不上不会影响其他。移除文件夹目的地不会删除文件夹本身；删除远端会同时删掉保存在钥匙串里的密码。")
        }
    }

    private func remoteBackendTitle(_ type: String) -> String {
        RcloneBackendCatalog.all.first(where: { $0.type == type })?.title ?? type
    }

    // MARK: Local packages

    private var localPackagesSection: some View {
        Section {
            let _ = model.refreshTick
            let packages = model.localPackages
            if packages.isEmpty {
                Text("还没有备份包。点「立即备份」生成第一个。")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            ForEach(packages) { pkg in
                Button {
                    model.restorePicked(pkg.url)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(DuduTheme.pink)
                            .frame(width: 30, height: 30)
                            .background(DuduTheme.duduIconChip)
                            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pkg.url.deletingPathExtension().lastPathComponent)
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduText)
                                .lineLimit(1)
                            Text("\(ByteCountFormatter.string(fromByteCount: pkg.size, countStyle: .file)) · \(Self.dateText(pkg.date))")
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    .frame(minHeight: 44)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        model.deletePackage(pkg)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("本机备份包")
        } footer: {
            Text("点一个备份包可以直接恢复。备份包是普通的 .dudubak 文件，也可以在「文件」App 里找到、拷走。")
        }
    }

    // MARK: Restore

    private var restoreSection: some View {
        Section {
            Button {
                model.showPackagePicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(DuduTheme.pink)
                        .frame(width: 30, height: 30)
                        .background(DuduTheme.duduIconChip)
                        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("从文件恢复…")
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                        Text("选择一个 .dudubak 备份包，先预览再恢复")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    Spacer()
                }
                .frame(minHeight: 52)
            }
        } footer: {
            Text("恢复采用合并语义：备份里有的数据写回来，本机独有的数据保留。密钥不在备份里，恢复后需要重新填写。")
        }
    }

    // MARK: History

    private var historySection: some View {
        Section {
            if history.records.isEmpty {
                Text("还没有备份记录。")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            ForEach(history.records) { record in
                NavigationLink {
                    BackupRecordDetailView(record: record)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: historyIcon(for: record.status))
                            .font(.system(size: 15))
                            .foregroundStyle(historyTint(for: record.status))
                            .frame(width: 30, height: 30)
                            .background(DuduTheme.duduIconChip)
                            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.dateText(record.startedAt))
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduText)
                            Text(historySubtitle(for: record))
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .frame(minHeight: 44)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        history.remove(record.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("历史记录")
        }
    }

    private func historyIcon(for status: BackupHistory.Status) -> String {
        switch status {
        case .running: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .completedWithIssues: return "exclamationmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func historyTint(for status: BackupHistory.Status) -> Color {
        switch status {
        case .running: return DuduTheme.duduTextDim
        case .succeeded: return DuduTheme.pink
        case .completedWithIssues: return DuduTheme.pink
        case .failed: return DuduTheme.pink
        }
    }

    private func historySubtitle(for record: BackupHistory.Record) -> String {
        switch record.status {
        case .running:
            return "进行中…"
        case .succeeded:
            let size = ByteCountFormatter.string(
                fromByteCount: record.totalBytes, countStyle: .file)
            return "成功 · \(size)"
        case .completedWithIssues:
            return "完成，但有 \(record.destinations.filter { !$0.succeeded }.count) 个目的地失败"
        case .failed:
            return record.errorMessage ?? "失败"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "zh_Hans_CN")
        return f
    }()

    static func dateText(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

// MARK: - RemoteAddSheet · 添加远端

/// Catalog-driven "add remote" form. Backends and their fields come from
/// `RcloneBackendCatalog` (the engine's own definitions), so the form can
/// never ask for a parameter rclone doesn't understand. The secret field
/// goes to the Keychain via `RcloneRemoteStore.add`, never to UserDefaults.
struct RemoteAddSheet: View {
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var backendType: String = "s3"
    @State private var name: String = ""
    @State private var values: [String: String] = [:]
    @State private var path: String = ""
    @State private var error: String?

    private var backend: RcloneBackendCatalog.Backend {
        RcloneBackendCatalog.all.first(where: { $0.type == backendType })
            ?? RcloneBackendCatalog.all[0]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $backendType) {
                        ForEach(RcloneBackendCatalog.all) { b in
                            Text(b.title).tag(b.type)
                        }
                    }
                    Text(backend.subtitle)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                Section("名称与目录") {
                    TextField("名称（字母、数字、-、_）", text: $name)
                        .font(DuduTheme.bodyFont())
                        .autocapitalization(.none)
                    TextField("备份目录（可选，如 backups）", text: $path)
                        .font(DuduTheme.bodyFont())
                        .autocapitalization(.none)
                }
                Section("连接信息") {
                    ForEach(backend.fields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            fieldInput(field)
                            if !field.hint.isEmpty {
                                Text(field.hint)
                                    .font(DuduTheme.captionFont())
                                    .foregroundStyle(DuduTheme.duduTextDim)
                            }
                        }
                    }
                }
                if let error {
                    Section {
                        Text(error)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.pink)
                    }
                }
                Section {
                    Button("保存远端") { save() }
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.pink)
                } footer: {
                    Text("密码只进系统钥匙串，不进备份、不进配置文件。")
                }
            }
            .navigationTitle("添加远端")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func fieldInput(_ field: RcloneBackendCatalog.Field) -> some View {
        let binding = Binding(
            get: { values[field.key] ?? "" },
            set: { values[field.key] = $0 })
        let label = field.label + (field.isOptional ? "（可选）" : "")
        if field.isSecret {
            SecureField(label, text: binding)
                .font(DuduTheme.bodyFont())
        } else {
            TextField(label, text: binding,
                      prompt: Text(field.placeholder)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim))
                .font(DuduTheme.bodyFont())
                .keyboardType(keyboardType(for: field.keyboard))
                .autocapitalization(.none)
                .textContentType(.none)
        }
    }

    private func keyboardType(
        for kind: RcloneBackendCatalog.Field.KeyboardKind) -> UIKeyboardType {
        switch kind {
        case .url: return .URL
        case .numeric: return .numberPad
        case .email: return .emailAddress
        case .default: return .default
        }
    }

    private func save() {
        error = nil
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        // Split the secret out: the Keychain holds it, params must not.
        var params: [String: String] = [:]
        var secret: String?
        for field in backend.fields {
            let v = (values[field.key] ?? "").trimmingCharacters(in: .whitespaces)
            if field.isSecret {
                if secret == nil { secret = v.isEmpty ? nil : v }
                continue
            }
            if v.isEmpty {
                if !field.isOptional {
                    error = "请填写「\(field.label)」。"
                    return
                }
            } else {
                params[field.key] = v
            }
        }
        do {
            try RcloneRemoteStore.add(
                name: trimmedName,
                backend: backend.type,
                params: params,
                path: path.trimmingCharacters(in: .whitespaces),
                secret: secret)
            // Make rclone see it now, not just after the next launch.
            RcloneRemoteStore.syncToRclone()
            onDone()
            dismiss()
        } catch {
            error = error.localizedDescription
        }
    }
}

// MARK: - RestoreSheet · 恢复流程

/// Restore is a deliberate act: pick → inspect (see what's inside) →
/// confirm → run → report. Nothing is written before the user confirms.
struct RestoreSheet: View {
    @ObservedObject var model: BackupCenterModel
    @State private var passphrase: String = ""

    var body: some View {
        NavigationStack {
            Group {
                switch model.restoreFlow {
                case .idle:
                    EmptyView()
                case .reading:
                    ProgressView("正在读取备份包…")
                        .tint(DuduTheme.pink)
                case .confirming(let manifest, let url):
                    confirmView(manifest: manifest, url: url)
                case .restoring(let lines):
                    restoringView(lines: lines)
                case .done(let report):
                    doneView(report: report)
                case .failed(let message):
                    failedView(message: message)
                }
            }
            .navigationTitle("从备份恢复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { model.closeRestoreSheet() }
                }
            }
        }
    }

    private func confirmView(manifest: BackupManifest, url: URL) -> some View {
        List {
            Section("备份包") {
                row("文件名", url.lastPathComponent)
                row("来源设备", manifest.deviceName)
                row("备份时间", BackupView.dateText(manifest.createdAt))
                row("加密", manifest.encryption == nil ? "未加密" : "已加密")
            }
            Section("包含内容") {
                ForEach(manifest.categories.keys.sorted(), id: \.self) { key in
                    let stat = manifest.categories[key]
                    HStack {
                        Text(backupCategoryLabel(key))
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                        Spacer()
                        Text("\(stat?.entries ?? 0) 项")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
            }
            if manifest.encryption != nil {
                Section("密码") {
                    SecureField("备份包密码", text: $passphrase)
                        .font(DuduTheme.bodyFont())
                } footer: {
                    Text("这个备份包是加密的，需要当时设置的密码才能恢复。")
                }
            }
            Section {
                Button("开始恢复") {
                    model.confirmRestore(url: url, passphrase: passphrase)
                }
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.pink)
            } footer: {
                Text("恢复采用合并语义：备份里有的数据写回来，本机独有的数据保留。密钥不在备份里，恢复后需要重新填写。")
            }
        }
    }

    private func restoringView(lines: [String]) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(DuduTheme.pink)
            Text(lines.last ?? "正在恢复…")
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.suffix(12).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
                .padding(.horizontal, 24)
            }
            Spacer()
        }
        .padding(.top, 32)
    }

    private func doneView(report: BackupImporter.Report) -> some View {
        List {
            Section("恢复完成") {
                row("来源设备", report.sourcePlatform ?? "—")
                row("导入", "\(report.totalImported) 项")
                row("更新", "\(report.totalUpdated) 项")
                row("跳过", "\(report.totalSkipped) 项")
                if report.wasEncrypted {
                    row("加密包", "已用密码解密")
                }
            }
            if !report.categories.isEmpty {
                Section("各分类") {
                    ForEach(report.categories, id: \.category) { c in
                        HStack {
                            Text(backupCategoryLabel(c.category))
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduText)
                            Spacer()
                            Text("\(c.imported + c.updated) 项")
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                }
            }
            if !report.warnings.isEmpty {
                Section("提醒") {
                    ForEach(Array(report.warnings.enumerated()), id: \.offset) { _, w in
                        Text(w)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
            }
            if !report.integrityFailed.isEmpty {
                Section("完整性问题") {
                    ForEach(Array(report.integrityFailed.enumerated()), id: \.offset) { _, p in
                        Text(p)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.pink)
                    }
                }
            }
            Section {
                Button("完成") { model.closeRestoreSheet() }
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.pink)
            }
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(DuduTheme.pink)
            Text("恢复失败")
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)
            Text(message)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("关闭") { model.closeRestoreSheet() }
                .buttonStyle(.bordered)
                .tint(DuduTheme.pink)
            Spacer()
        }
        .padding(.top, 48)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
            Spacer()
            Text(value)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .lineLimit(1)
        }
    }
}

// MARK: - BackupRecordDetailView · 历史记录详情

/// One run's full story: log lines, destination outcomes, skipped files.
struct BackupRecordDetailView: View {
    let record: BackupHistory.Record

    var body: some View {
        List {
            Section("概况") {
                detailRow("开始", BackupView.dateText(record.startedAt))
                if let finished = record.finishedAt {
                    detailRow("结束", BackupView.dateText(finished))
                }
                detailRow("状态", statusText)
                if record.totalBytes > 0 {
                    detailRow("大小", ByteCountFormatter.string(
                        fromByteCount: record.totalBytes, countStyle: .file))
                }
                if !record.categories.isEmpty {
                    detailRow("分类", record.categories
                        .map(backupCategoryLabel).joined(separator: "、"))
                }
                if let name = record.packageName {
                    detailRow("备份包", name)
                }
                if let error = record.errorMessage {
                    Text(error)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.pink)
                }
            }
            if !record.destinations.isEmpty {
                Section("投递结果") {
                    ForEach(record.destinations) { d in
                        HStack(spacing: 10) {
                            Image(systemName: d.succeeded
                                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(d.succeeded
                                                 ? DuduTheme.pink : DuduTheme.pink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name)
                                    .font(DuduTheme.bodyFont())
                                    .foregroundStyle(DuduTheme.duduText)
                                if let detail = d.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(DuduTheme.captionFont())
                                        .foregroundStyle(DuduTheme.duduTextDim)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
            if record.skippedFiles > 0 {
                Section("未备份的文件（\(record.skippedFiles) 个）") {
                    ForEach(record.skippedEntries) { e in
                        HStack {
                            Text(e.fileName)
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduText)
                                .lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(
                                fromByteCount: e.size, countStyle: .file))
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                    if record.skippedEntries.count < record.skippedFiles {
                        Text("仅显示体积最大的 \(record.skippedEntries.count) 个。")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
            }
            if !record.log.isEmpty {
                Section("日志") {
                    ForEach(record.log) { entry in
                        Text(entry.message)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(entry.isProblem
                                             ? DuduTheme.pink : DuduTheme.duduTextDim)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("备份详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusText: String {
        switch record.status {
        case .running: return "进行中"
        case .succeeded: return "成功"
        case .completedWithIssues: return "完成（有目的地失败）"
        case .failed: return "失败"
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
            Spacer()
            Text(value)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .lineLimit(2)
        }
    }
}
