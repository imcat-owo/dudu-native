import Foundation

// MARK: - ThemeCustomCSS · 受限主题 CSS
//
// Old Dudu's creative-mode theme-CSS (apps/mobile/src/theme/tools.ts),
// native edition. The restricted language is a token-override layer over
// the theme — never layout / interaction / business logic:
//
//   .surface-card {
//     bg: #FFE7E8;
//     border: #ECC7D6;
//     radius: 16;
//   }
//
// Selectors: .surface-<id>, id in canvas, card, input, userBubble,
// aiBubble, accent, text, overlay. Properties: bg, fg, accent, border
// (#rrggbb), radius (number, px). Anything else is rejected with a line
// number — nothing is applied on failure (same guarantee as old Dudu's
// parseThemeCss).
//
// Token mapping (documented, no silent remaps):
//   bg     -> canvas/surface/input/userBubble/assistantBubble/accent/raised
//             (per surface id; .surface-text has no bg)
//   fg     -> primaryText (only .surface-text supports fg)
//   accent -> accent role (only .surface-accent supports the accent token)
//   border -> border role (only .surface-card supports the border token)
//   radius -> pack bubble radius (userBubble/aiBubble/input only;
//             other surfaces: rejected with a clear message)
//
// The CSS text is stored in UserDefaults, OUTSIDE theme packs (packs only
// carry color overrides). Applied overrides remember their prior values so
// delete_theme_css restores exactly what was there before.

@MainActor
final class ThemeCustomCSS {
    static let shared = ThemeCustomCSS()

    enum CSSError: LocalizedError {
        case parse(line: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .parse(let line, let message):
                return "第 \(line) 行：\(message)"
            }
        }
    }

    struct Rule {
        var surface: ThemeSurfaceID
        var declarations: [(property: String, value: String, line: Int)]
    }

    private enum Keys {
        static let text = "themeCustomCSS.text.v1"
        static let priors = "themeCustomCSS.priors.v1"
    }

    private init() {}

    var cssText: String {
        UserDefaults.standard.string(forKey: Keys.text) ?? ""
    }

    /// Applied overrides: "light.canvas" -> prior hex ("" = no override
    /// existed, restore = clearOverride). Persisted so a relaunch does not
    /// lose the ability to delete cleanly.
    var appliedPriors: [String: String] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Keys.priors),
                  let map = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return map
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.priors)
            }
        }
    }

    var isEmpty: Bool { cssText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - Parse + validate

    /// Parse and validate. Throws CSSError(line:message) — nothing applied.
    func parse(_ css: String) throws -> [Rule] {
        var rules: [Rule] = []
        var current: ThemeSurfaceID?
        var declarations: [(String, String, Int)] = []
        var lineNumber = 0

        func finishRule() throws {
            guard let surface = current else { return }
            rules.append(Rule(surface: surface, declarations: declarations))
            current = nil
            declarations = []
        }

        for rawLine in css.components(separatedBy: "\n") {
            lineNumber += 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }

            if line.hasPrefix(".") {
                // Selector line: .surface-<id> {
                try finishRule()
                let body = line.hasSuffix("{") ? String(line.dropLast()) : line
                let name = body.trimmingCharacters(in: .whitespaces)
                guard name.hasPrefix(".surface-") else {
                    throw CSSError.parse(line: lineNumber,
                                         message: "选择器必须形如 .surface-card，这里是「\(name)」")
                }
                let id = String(name.dropFirst(".surface-".count))
                guard let surface = ThemeSurfaceID(rawValue: id) else {
                    throw CSSError.parse(line: lineNumber,
                                         message: "未知的 surface「\(id)」，可用：\(ThemeSurfaceID.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                if !line.hasSuffix("{") {
                    throw CSSError.parse(line: lineNumber, message: "选择器行末尾缺少 {")
                }
                current = surface
                continue
            }

            if line == "}" {
                guard current != nil else {
                    throw CSSError.parse(line: lineNumber, message: "多余的 }")
                }
                try finishRule()
                continue
            }

            guard current != nil else {
                throw CSSError.parse(line: lineNumber,
                                     message: "声明必须写在 .surface-<id> { } 里")
            }
            // Declaration: prop: value;
            guard line.hasSuffix(";") else {
                throw CSSError.parse(line: lineNumber, message: "声明末尾缺少分号")
            }
            let decl = String(line.dropLast())
            guard let colon = decl.firstIndex(of: ":") else {
                throw CSSError.parse(line: lineNumber, message: "声明缺少冒号")
            }
            let prop = decl[..<colon].trimmingCharacters(in: .whitespaces)
            let value = decl[decl.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard ["bg", "fg", "accent", "border", "radius"].contains(prop) else {
                throw CSSError.parse(line: lineNumber,
                                     message: "不支持的属性「\(prop)」，只允许 bg / fg / accent / border / radius")
            }
            guard !value.isEmpty else {
                throw CSSError.parse(line: lineNumber, message: "属性「\(prop)」的值是空的")
            }
            // Validate the value NOW so errors carry the right line number.
            try validateValue(prop: prop, surface: current!, value: value, line: lineNumber)
            declarations.append((prop, value, lineNumber))
        }
        try finishRule()
        return rules
    }

    /// Validate without applying (used by try-on staging).
    func validate(_ css: String) throws {
        _ = try parse(css)
    }

    private func validateValue(prop: String, surface: ThemeSurfaceID,
                               value: String, line: Int) throws {
        switch prop {
        case "bg", "fg", "accent", "border":
            guard ThemeCustomCSS.isHexColor(value) else {
                throw CSSError.parse(line: line,
                                     message: "「\(value)」不是 #rrggbb 颜色")
            }
            // Surface capability checks — fail loudly instead of silently remapping.
            switch prop {
            case "bg":
                guard surface.bgRole != nil else {
                    throw CSSError.parse(line: line,
                                         message: ".surface-\(surface.rawValue) 不支持 bg")
                }
            case "fg":
                guard surface == .text else {
                    throw CSSError.parse(line: line,
                                         message: "fg 只支持 .surface-text，其他 surface 没有独立文字色")
                }
            case "accent":
                guard surface == .accent else {
                    throw CSSError.parse(line: line,
                                         message: "accent 属性只支持 .surface-accent")
                }
            case "border":
                guard surface == .card else {
                    throw CSSError.parse(line: line,
                                         message: "border 属性只支持 .surface-card")
                }
            default: break
            }
        case "radius":
            let numeric = value.lowercased().hasSuffix("px")
                ? String(value.dropLast(2)) : value
            guard let number = Double(numeric.trimmingCharacters(in: .whitespaces)),
                  number.isFinite, number >= 0, number <= 64 else {
                throw CSSError.parse(line: line,
                                     message: "radius 必须是 0-64 的数字（px），这里是「\(value)」")
            }
            guard surface.radiusApplies else {
                throw CSSError.parse(line: line,
                                     message: ".surface-\(surface.rawValue) 不支持 radius（只支持 userBubble / aiBubble / input）")
            }
        default: break
        }
    }

    static func isHexColor(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespaces)
        let hex = t.hasPrefix("#") ? String(t.dropFirst()) : t
        guard hex.count == 6 || hex.count == 8 else { return false }
        return hex.allSatisfy { $0.isHexDigit }
    }

    static func normalizeHex(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        let hex = (t.hasPrefix("#") ? String(t.dropFirst()) : t).uppercased()
        return String(hex.prefix(6))
    }

    // MARK: - Apply / restore / clear

    /// A validated declaration, side-effect free. Shared by the persisted
    /// apply() path and the in-memory try-on staging path.
    enum CSSOp {
        case color(role: AppearanceColorRole, hex: String)
        case radius(surface: ThemeSurfaceID, value: Double)
    }

    func operations(_ rules: [Rule]) -> [CSSOp] {
        var ops: [CSSOp] = []
        for rule in rules {
            for (prop, value, _) in rule.declarations {
                switch prop {
                case "radius":
                    let numeric = value.lowercased().hasSuffix("px")
                        ? String(value.dropLast(2)) : value
                    let radius = min(32, max(4, Double(numeric) ?? 16))
                    ops.append(.radius(surface: rule.surface, value: radius))
                default:
                    let role: AppearanceColorRole? = {
                        switch prop {
                        case "bg": return rule.surface.bgRole
                        case "fg": return .primaryText // .text only (validated)
                        case "accent": return .accent // .surface-accent only (validated)
                        case "border": return .border // .surface-card only (validated)
                        default: return nil
                        }
                    }()
                    if let role {
                        ops.append(.color(role: role, hex: ThemeCustomCSS.normalizeHex(value)))
                    }
                }
            }
        }
        return ops
    }

    /// Apply parsed rules to a pack copy WITHOUT side effects: returns the
    /// mutated pack (radii) plus the color overrides for the active variant.
    /// Used by try-on staging — nothing is persisted here.
    func stageOperations(_ ops: [CSSOp], variant: AppearanceVariant,
                         pack: inout AppearanceThemePack) -> (light: [String: String], dark: [String: String]) {
        var light: [String: String] = [:], dark: [String: String] = [:]
        for op in ops {
            switch op {
            case .color(let role, let hex):
                if variant == .light { light[role.rawValue] = hex }
                else { dark[role.rawValue] = hex }
            case .radius(let surface, let value):
                switch surface {
                case .userBubble: pack.userBubbleRadius = value
                case .aiBubble: pack.assistantBubbleRadius = value
                case .input: pack.inputBarRadius = value
                default: break // validateValue already rejected the rest
                }
            }
        }
        return (light, dark)
    }

    /// Persist the CSS text without touching overrides (try-on commit —
    /// priors are captured separately from the pre-try-on snapshot).
    func persistText(_ css: String) {
        UserDefaults.standard.set(css, forKey: Keys.text)
    }

    /// Validate, store the text, and apply as token overrides on the ACTIVE
    /// variant (same rule as the 外观 page color pickers: you edit what you see).
    func apply(_ css: String) throws {
        let rules = try parse(css)
        let ops = operations(rules)
        let studio = AppearanceStudio.shared
        let variant = studio.activeVariant
        var priors = appliedPriors
        var pack = studio.currentThemePack()
        var packChanged = false

        for op in ops {
            switch op {
            case .radius(let surface, let value):
                switch surface {
                case .userBubble: pack.userBubbleRadius = value
                case .aiBubble: pack.assistantBubbleRadius = value
                case .input: pack.inputBarRadius = value
                default: break // validateValue already rejected the rest
                }
                packChanged = true
            case .color(let role, let hex):
                let key = "\(variant.rawValue).\(role.rawValue)"
                if priors[key] == nil {
                    priors[key] = studio.hasOverride(role, scope: .global, variant: variant)
                        ? studio.hex(role, scope: .global, variant: variant)
                        : ""
                }
                studio.setColor(Color(hex: hex), role: role, scope: .global, variant: variant)
            }
        }
        if packChanged {
            studio.persistPack(pack)
        }
        appliedPriors = priors
        persistText(css)
    }

    /// Restore a previously snapshotted CSS state (try-on discard/rollback).
    func restore(text: String, priors: [String: String]) {
        let studio = AppearanceStudio.shared
        // Revert every override applied since the snapshot.
        for (key, prior) in appliedPriors {
            let parts = key.split(separator: ".").map(String.init)
            guard parts.count == 2,
                  let variant = AppearanceVariant(rawValue: parts[0]),
                  let role = AppearanceColorRole(rawValue: parts[1])
            else { continue }
            if priors[key] == nil {
                // This override did not exist at snapshot time — remove it.
                if prior.isEmpty {
                    studio.clearOverride(role, scope: .global, variant: variant)
                } else {
                    studio.setColor(Color(hex: prior), role: role,
                                    scope: .global, variant: variant)
                }
            }
        }
        // Then re-apply overrides that existed at snapshot time but were
        // clobbered since (defensive; normally a no-op).
        for (key, prior) in priors where appliedPriors[key] == nil {
            let parts = key.split(separator: ".").map(String.init)
            guard parts.count == 2,
                  let variant = AppearanceVariant(rawValue: parts[0]),
                  let role = AppearanceColorRole(rawValue: parts[1]),
                  !prior.isEmpty
            else { continue }
            studio.setColor(Color(hex: prior), role: role,
                            scope: .global, variant: variant)
        }
        appliedPriors = priors
        UserDefaults.standard.set(text, forKey: Keys.text)
    }

    /// delete_theme_css: remove the whole layer, restoring priors.
    func clear() {
        restore(text: "", priors: [:])
    }
}

// MARK: - ThemeSurfaceID · CSS / token 的 surface 口径

/// Old-Dudu surface ids (apps/mobile/src/theme/tools.ts SURFACE_IDS),
/// mapped onto native AppearanceColorRoles. Documented in the tool
/// descriptions so the model never has to guess.
enum ThemeSurfaceID: String, CaseIterable {
    case canvas, card, input, userBubble, aiBubble, accent, text, overlay

    /// bg token -> native role (nil = this surface has no bg mapping).
    var bgRole: AppearanceColorRole? {
        switch self {
        case .canvas: return .canvas
        case .card: return .surface
        case .input: return .input
        case .userBubble: return .userBubble
        case .aiBubble: return .assistantBubble
        case .accent: return .accent
        case .text: return nil
        case .overlay: return .raised
        }
    }

    /// radius token applies to a pack field on these surfaces only.
    var radiusApplies: Bool {
        switch self {
        case .userBubble, .aiBubble, .input: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .canvas: return "页面背景"
        case .card: return "卡片"
        case .input: return "输入框"
        case .userBubble: return "用户气泡"
        case .aiBubble: return "AI 气泡"
        case .accent: return "强调色"
        case .text: return "文字"
        case .overlay: return "浮层"
        }
    }
}
