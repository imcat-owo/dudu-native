import SwiftUI

// MARK: - SettingsRoute / SettingsNavigator

/// Phase-C navigation routes inside the Settings tab.
enum SettingsRoute: Hashable {
    case providerDetail(String)
    case qrScan
    case providerShare(String)
    case modelGroups
    case modelGroupDetail(String)
    // Wave 3 P1: 人设管理（PersonaListView）。
    case personas
    case appearance
    case fontScale
    case ttsSettings
    case mcpServers
    case backup
    case appLock
    case musicKit
    case sandbox
    case about
    // D22: Siri & Shortcuts hub (Dudu/Views/Intents/).
    case siriShortcuts
    // Wave 4 P2: Help center (Dudu/Views/Settings/HelpView.swift).
    case help
}

/// Owns the Settings tab's NavigationStack path so deep pushes
/// (e.g. add-provider → its detail page) work from sheets.
final class SettingsNavigator: ObservableObject {
    @Published var path = NavigationPath()
}

// MARK: - SettingsView · 设置

/// Lean Phase-C settings shell: rows for 模型服务 / 外观 / 字体 / 关于.
/// Phase D adds more sections here; no dead rows.

/// One navigable row in the settings list.
private struct SettingItem: Identifiable, Hashable {
    /// Routes are unique across the whole settings list, so the route is a
    /// stable identity.
    var id: SettingsRoute { route }
    let icon: String
    let title: String
    let route: SettingsRoute
}

struct SettingsView: View {
    @StateObject private var navigator = SettingsNavigator()
    @State private var searchText = ""

    /// All setting rows grouped by section, in display order.
    private var settingsSections: [[SettingItem]] {
        [
            [
                SettingItem(
                    icon: "cpu",
                    title: "模型服务",
                    route: .providerDetail("__list__")
                ),
                // Wave 3 P1: 人设管理
                SettingItem(
                    icon: "person.crop.circle",
                    title: "人设",
                    route: .personas
                ),
                // D24: 模型分组（编排）——分组切换器 + 成员编排
                SettingItem(
                    icon: "square.stack.3d.up",
                    title: AppLocalized("orchestration.title"),
                    route: .modelGroups
                ),
                SettingItem(
                    icon: "paintpalette",
                    title: "外观",
                    route: .appearance
                ),
                SettingItem(
                    icon: "textformat.size",
                    title: "字体大小",
                    route: .fontScale
                ),
                SettingItem(
                    icon: "speaker.wave.2.fill",
                    title: "语音",
                    route: .ttsSettings
                ),
                SettingItem(
                    icon: "server.rack",
                    title: "MCP 服务器",
                    route: .mcpServers
                ),
                // D19: Apple Music（developer token 她自己粘贴）
                SettingItem(
                    icon: "music.note",
                    title: "Apple Music",
                    route: .musicKit
                ),
                // D25: 沙箱（云端 Docker / 本地 iSH 双后端 + 在其他 App 里打开）
                SettingItem(
                    icon: "server.rack",
                    title: L10n.string("sandbox.title"),
                    route: .sandbox
                ),
                // D22: Siri & Shortcuts hub — the 8 App Intents, Siri
                // phrases, Add-to-Siri buttons, scheduled prompts link.
                SettingItem(
                    icon: "mic.fill",
                    title: AppLocalized("Siri & Shortcuts"),
                    route: .siriShortcuts
                ),
            ],
            // D8/D11: 备份与恢复 / 应用锁
            [
                SettingItem(
                    icon: "externaldrive.fill",
                    title: "备份与恢复",
                    route: .backup
                ),
                SettingItem(
                    icon: BiometricAuth.biometryIconName,
                    title: "应用锁",
                    route: .appLock
                ),
            ],
            [
                // Wave 4 P2: 帮助中心
                SettingItem(
                    icon: "lifepreserver.fill",
                    title: "帮助",
                    route: .help
                ),
                SettingItem(
                    icon: "info.circle",
                    title: "关于",
                    route: .about
                ),
            ],
        ]
    }

    /// Sections filtered by the current search query; sections with no
    /// matching rows are dropped.
    private var filteredSections: [[SettingItem]] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return settingsSections }
        return settingsSections.compactMap { section in
            let matches = section.filter { $0.title.localizedCaseInsensitiveContains(query) }
            return matches.isEmpty ? nil : matches
        }
    }

    private var hasResults: Bool { !filteredSections.isEmpty }

    var body: some View {
        NavigationStack(path: $navigator.path) {
            Group {
                if hasResults {
                    List {
                        ForEach(filteredSections.indices, id: \.self) { index in
                            Section {
                                ForEach(filteredSections[index]) { item in
                                    SettingsRow(
                                        icon: item.icon,
                                        title: item.title,
                                        route: item.route
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    // No results for the current query.
                    ContentUnavailableView {
                        Label("没有匹配的设置", systemImage: "magnifyingglass")
                    } description: {
                        Text("换个关键词试试")
                    }
                }
            }
            .navigationTitle("设置")
            .searchable(text: $searchText, prompt: "搜索设置")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .providerDetail("__list__"):
                    ProviderListView()
                case .providerDetail(let id):
                    ProviderDetailView(instanceId: id)
                case .qrScan:
                    ProviderQRScanView()
                case .providerShare(let id):
                    ProviderQRShareView(instanceId: id)
                case .modelGroups:
                    ModelGroupListView()
                case .modelGroupDetail(let id):
                    ModelGroupDetailView(groupId: id)
                case .personas:
                    PersonaListView()
                case .appearance:
                    AppearanceView()
                case .fontScale:
                    FontScaleView()
                case .ttsSettings:
                    TTSSettingsView()
                case .mcpServers:
                    MCPListView()
                case .backup:
                    BackupView()
                case .appLock:
                    AppLockView()
                case .musicKit:
                    AppleMusicSettingsView()
                case .sandbox:
                    SandboxSettingsView()
                case .about:
                    AboutView()
                case .siriShortcuts:
                    SiriShortcutsHubView()
                case .help:
                    HelpView()
                }
            }
            .onReceive(DeepLinkCoordinator.shared.$pendingSettingsTarget) { target in
                // D22: `dudu-clone://settings/siri` lands here. DuduTabView
                // already switched to the Settings tab; push the hub and clear
                // the one-shot target so a later plain navigation doesn't re-push.
                guard target == .siriShortcuts else { return }
                DeepLinkCoordinator.shared.pendingSettingsTarget = nil
                navigator.path.append(SettingsRoute.siriShortcuts)
            }
        }
        .environmentObject(navigator)
    }
}

// MARK: - Settings row

private struct SettingsRow: View {
    let icon: String
    let title: String
    let route: SettingsRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                DuduIcon(systemName: icon)
                    .font(DuduTheme.appFont(size: 15))
                    .foregroundStyle(DuduTheme.pink)
                    .frame(width: 30, height: 30)
                    .background(DuduTheme.pinkSoft)
                    .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                Text(title)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
            }
            .frame(minHeight: 44)
        }
    }
}

// MARK: - Font scale page

private struct FontScaleView: View {
    @ObservedObject private var fonts = FontSettings.shared

    var body: some View {
        List {
            Section {
                ForEach(FontScaleLevel.allCases) { level in
                    Button {
                        fonts.appBaseScale = level
                    } label: {
                        HStack {
                            Text(level.label)
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduText)
                            Spacer()
                            if fonts.appBaseScale == level {
                                DuduIcon(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(DuduTheme.pink)
                            }
                        }
                    }
                }
            } header: {
                Text("应用字体大小")
            } footer: {
                Text("跟随系统字号叠加应用内缩放。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("字体大小")
    }
}

// MARK: - About page (no fake data — reads the real bundle version)

private struct AboutView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (s?, b?): return "\(s) (\(b))"
        case let (s?, nil): return s
        default: return "—"
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("版本")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                    Spacer()
                    Text(version)
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                HStack {
                    Text("名称")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? "嘟嘟")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("关于")
    }
}
