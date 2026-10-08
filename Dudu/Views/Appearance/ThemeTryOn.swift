import SwiftUI

// MARK: - ThemeTryOn · 试穿
//
// Old-Dudu try-on flow (apps/mobile/src/theme/tools.ts), native edition:
//   preview_theme  -> stage()   — in-memory preview, try-on banner appears,
//                                 nothing persisted (colors + pack shape)
//   confirm_theme  -> commit()  — persist the staged preview
//   rollback_theme -> rollback()— discard staged preview, else restore the
//                                 theme from before the last AI theme change
//
// Mode applies live during a try-on (single int) but is recorded in the
// backup, so discard restores it. Colors, pack shape and custom-CSS stage
// fully in memory — nothing hits UserDefaults until commit.

@MainActor
final class ThemeTryOn: ObservableObject {
    static let shared = ThemeTryOn()

    /// Everything a staged preview may have touched.
    private struct Snapshot {
        var pack: AppearanceThemePack
        var colors: [String: String]
        var mode: Int
        var cssText: String
        var cssPriors: [String: String]
    }

    @Published private(set) var isStaged = false
    @Published private(set) var stagedLabel = ""

    private var backup: Snapshot?
    private var lastCommitted: Snapshot?
    /// CSS staged in-memory (persisted only on commit).
    private var stagedCSS: String?

    private init() {}

    // MARK: - Snapshot helpers

    private func takeSnapshot() -> Snapshot {
        let studio = AppearanceStudio.shared
        let snap = studio.tryOnSnapshot()
        return Snapshot(
            pack: snap.pack,
            colors: snap.colors,
            mode: UserDefaults.standard.integer(forKey: "appearanceMode"),
            cssText: ThemeCustomCSS.shared.cssText,
            cssPriors: ThemeCustomCSS.shared.appliedPriors
        )
    }

    // MARK: - Stage / commit / discard

    /// Stage a theme pack as an in-memory preview. `mode`: 1 = light,
    /// 2 = dark, 0 = system (nil = leave mode alone). `css`: restricted
    /// theme-CSS to preview (validated before staging; staged in memory,
    /// persisted only on commit).
    func stage(pack: AppearanceThemePack, label: String,
               mode: Int? = nil, css: String? = nil) throws {
        let cssTrimmed = css?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var cssOps: [ThemeCustomCSS.CSSOp] = []
        if !cssTrimmed.isEmpty {
            // Validate BEFORE touching anything — a bad CSS must not
            // leave a half-staged preview behind.
            let rules = try ThemeCustomCSS.shared.parse(cssTrimmed)
            cssOps = ThemeCustomCSS.shared.operations(rules)
        }
        let studio = AppearanceStudio.shared
        if !isStaged {
            backup = takeSnapshot()
        }
        // Merge staged CSS overrides into the staged colors/pack in-memory.
        var stagedPack = pack
        var light = pack.colorsLight
        var dark = pack.colorsDark
        if !cssOps.isEmpty {
            let staged = ThemeCustomCSS.shared.stageOperations(
                cssOps, variant: studio.activeVariant, pack: &stagedPack)
            for (k, v) in staged.light { light[k] = v }
            for (k, v) in staged.dark { dark[k] = v }
        }
        studio.tryOnStageColors(light: light, dark: dark)
        studio.tryOnStagePack(stagedPack)
        stagedCSS = cssTrimmed.isEmpty ? nil : cssTrimmed
        if let mode {
            UserDefaults.standard.set(mode, forKey: "appearanceMode")
            studio.objectWillChange.send()
            studio.configureUIKitSurfaces()
        }
        stagedLabel = label
        isStaged = true
    }

    /// Persist the staged preview. Returns false when nothing is staged.
    @discardableResult
    func commit() -> Bool {
        guard isStaged, let backup else { return false }
        let studio = AppearanceStudio.shared
        studio.tryOnCommitColors()
        studio.persistPack(studio.currentThemePack())
        if let css = stagedCSS {
            // Capture honest priors from the PRE-try-on snapshot so a later
            // delete_theme_css restores exactly the pre-preview colors.
            // backup.colors keys are "scope.variant.role".
            let variant = studio.activeVariant
            var priors: [String: String] = [:]
            if let rules = try? ThemeCustomCSS.shared.parse(css) {
                for op in ThemeCustomCSS.shared.operations(rules) {
                    if case .color(let role, _) = op {
                        let key = "\(variant.rawValue).\(role.rawValue)"
                        if priors[key] == nil {
                            priors[key] = backup.colors["global.\(key)"] ?? ""
                        }
                    }
                }
            }
            ThemeCustomCSS.shared.appliedPriors = priors
            ThemeCustomCSS.shared.persistText(css)
        }
        lastCommitted = backup
        clearStaging()
        return true
    }

    /// Throw away the staged preview and restore the pre-try-on theme.
    func discard() {
        guard isStaged, let backup else { return }
        let studio = AppearanceStudio.shared
        // CSS restore is a defensive no-op here: staged CSS never touched
        // the persisted text/priors (in-memory only), so this just
        // re-asserts the pre-try-on state.
        ThemeCustomCSS.shared.restore(text: backup.cssText, priors: backup.cssPriors)
        // …then colors + pack go back to the pre-try-on snapshot.
        studio.tryOnRestore(colors: backup.colors, pack: backup.pack)
        UserDefaults.standard.set(backup.mode, forKey: "appearanceMode")
        studio.objectWillChange.send()
        studio.configureUIKitSurfaces()
        clearStaging()
    }

    /// rollback_theme: discard a staged preview; otherwise restore the
    /// theme from before the most recent AI-driven theme change.
    /// Returns a message, or nil when there is nothing to roll back to.
    func rollback() -> String? {
        if isStaged {
            discard()
            return "试穿已放弃，回到原来的主题。"
        }
        guard let prev = lastCommitted else { return nil }
        let studio = AppearanceStudio.shared
        ThemeCustomCSS.shared.restore(text: prev.cssText, priors: prev.cssPriors)
        studio.tryOnRestore(colors: prev.colors, pack: prev.pack)
        UserDefaults.standard.set(prev.mode, forKey: "appearanceMode")
        studio.objectWillChange.send()
        studio.configureUIKitSurfaces()
        lastCommitted = nil
        return "已回到上一次确认的主题。"
    }

    /// Record the pre-change state before an AI tool applies a theme
    /// change directly (coordinates / preset / surface tokens), so
    /// rollback_theme can undo it. Mirrors old Dudu's previousBundle.
    func recordPreChange() {
        // Never overwrite the try-on backup mid-preview.
        guard !isStaged else { return }
        lastCommitted = takeSnapshot()
    }

    var hasRollbackTarget: Bool { isStaged || lastCommitted != nil }

    private func clearStaging() {
        isStaged = false
        stagedLabel = ""
        stagedCSS = nil
        backup = nil
    }
}

// MARK: - In-memory pack staging (extension; cachedThemePack is internal)

extension AppearanceStudio {
    /// Stage a pack in memory only (no UserDefaults write). The UI
    /// re-renders immediately via themePackRevision + objectWillChange.
    func tryOnStagePack(_ pack: AppearanceThemePack) {
        themePackLock.lock()
        cachedThemePack = pack
        themePackLoaded = true
        themePackLock.unlock()
        themePackRevision += 1
        objectWillChange.send()
    }
}

// MARK: - Try-on banner (global overlay)

/// Floating banner shown while a try-on preview is staged — old Dudu's
/// "试穿" banner. Mounted in DuduTabView's global overlay so it is
/// visible from chat (where the AI stages previews) and settings alike.
struct ThemeTryOnBanner: View {
    @ObservedObject private var tryOn = ThemeTryOn.shared

    var body: some View {
        if tryOn.isStaged {
            HStack(spacing: 10) {
                DuduIcon(systemName: "paintbrush.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DuduTheme.pink)
                    .frame(width: 28, height: 28)
                    .background(DuduTheme.pinkSoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("正在试穿")
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                    if !tryOn.stagedLabel.isEmpty {
                        Text(tryOn.stagedLabel)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button("放弃") { tryOn.discard() }
                    .font(DuduTheme.bodyFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(DuduTheme.duduIconChip)
                    .clipShape(Capsule())
                Button("保存试穿") {
                    if !tryOn.commit() {
                        tryOn.discard()
                    }
                }
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduCard)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(DuduTheme.pink)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DuduTheme.duduCard)
            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusCard,
                                        style: .continuous))
            .shadow(color: DuduTheme.kitty.opacity(0.08), radius: 8, y: 2)
            .padding(.horizontal, DuduTheme.pagePadding)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.85),
                       value: tryOn.isStaged)
        }
    }
}
