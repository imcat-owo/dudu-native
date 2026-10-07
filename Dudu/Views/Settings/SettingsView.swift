import SwiftUI

// MARK: - SettingsRoute / SettingsNavigator

/// Phase-C navigation routes inside the Settings tab.
enum SettingsRoute: Hashable {
    case providerDetail(String)
    case appearance
    case fontScale
    case about
}

/// Owns the Settings tab's NavigationStack path so deep pushes
/// (e.g. add-provider → its detail page) work from sheets.
final class SettingsNavigator: ObservableObject {
    @Published var path = NavigationPath()
}

// MARK: - SettingsView · 设置

/// Lean Phase-C settings shell: rows for 模型服务 / 外观 / 字体 / 关于.
/// Phase D adds more sections here; no dead rows.

struct SettingsView: View {
    @StateObject private var navigator = SettingsNavigator()

    var body: some View {
        NavigationStack(path: $navigator.path) {
            List {
                Section {
                    SettingsRow(
                        icon: "cpu",
                        title: "模型服务",
                        route: .providerDetail("__list__")
                    )
                    SettingsRow(
                        icon: "paintpalette",
                        title: "外观",
                        route: .appearance
                    )
                    SettingsRow(
                        icon: "textformat.size",
                        title: "字体大小",
                        route: .fontScale
                    )
                }
                Section {
                    SettingsRow(
                        icon: "info.circle",
                        title: "关于",
                        route: .about
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .providerDetail("__list__"):
                    ProviderListView()
                case .providerDetail(let id):
                    ProviderDetailView(instanceId: id)
                case .appearance:
                    AppearanceView()
                case .fontScale:
                    FontScaleView()
                case .about:
                    AboutView()
                }
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
                Image(systemName: icon)
                    .font(.system(size: 15))
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
                                Image(systemName: "checkmark.circle.fill")
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
