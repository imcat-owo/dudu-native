import Foundation
import SwiftUI
import UIKit

// MARK: - AIChatViewModel+ThemeTools (D12)
//
// The 16 AI theme tools, ported from old Dudu
// (~/workspace/openmuse/apps/mobile/src/theme/tools.ts):
//   set_wallpaper, set_theme, set_ai_avatar, get_theme,
//   apply_theme_coordinates, apply_surface_tokens, apply_preset,
//   preview_theme, confirm_theme, rollback_theme,
//   read_theme_css, replace_theme_css, append_theme_css,
//   edit_theme_css, insert_theme_css, delete_theme_css
//
// Every handler calls the REAL engine — AppearanceStudio (the same engine
// ThemeOffloadBridge's @objc entry points wrap; those use
// DispatchSemaphore and would deadlock on this @MainActor view model),
// ThemeTryOn (in-memory try-on staging), or ThemeCustomCSS. No stubs:
// a tool that cannot do its job returns an honest error.
//
// Registration: makeAgentTools() appends themeToolDefinitions().
// Dispatch: the tool-execution switch calls handleThemeTool(name:args:).

extension AIChatViewModel {

    // MARK: - Definitions

    func themeToolDefinitions() -> [AgentToolDefinition] {
        let surfaceList = ThemeSurfaceID.allCases.map(\.rawValue).joined(separator: ", ")
        return [
            AgentToolDefinition(
                name: "set_wallpaper",
                description: "Set the app wallpaper to an image. uri: a dudu-clone:// URL or /var/dudu/ Linux path (from a photo she shared in chat, or an image you generated). Empty string removes the wallpaper. Applies immediately to the whole app.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                    "uri": AgentToolParam(type: .string, description: "Image URI (dudu-clone://… or /var/dudu/… path). Empty string removes the wallpaper."),
                ],
                required: ["tool_title"],
                propertyOrdering: ["tool_title", "uri"]
            ),
            AgentToolDefinition(
                name: "set_theme",
                description: "Switch the app theme mode. mode: light | dark | system. Applies immediately.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                    "mode": AgentToolParam(type: .string, description: "light | dark | system — which theme mode to use."),
                ],
                required: ["tool_title", "mode"],
                propertyOrdering: ["tool_title", "mode"]
            ),
            AgentToolDefinition(
                name: "set_ai_avatar",
                description: "Change the AI assistant's avatar image. uri: a dudu-clone:// URL or /var/dudu/ Linux path of the image she shared or picked. Empty string resets to the default avatar. Applies immediately.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                    "uri": AgentToolParam(type: .string, description: "Image URI for the new avatar. Empty string resets to default."),
                ],
                required: ["tool_title"],
                propertyOrdering: ["tool_title", "uri"]
            ),
            AgentToolDefinition(
                name: "get_theme",
                description: "Read the current theme as JSON. Call this BEFORE changing anything so you know what the theme looks like now. section: 'all' or one surface id (\(surfaceList)).",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                    "section": AgentToolParam(type: .string, description: "'all' or one surface id. Defaults to 'all'."),
                ],
                required: ["tool_title"],
                propertyOrdering: ["tool_title", "section"]
            ),
            AgentToolDefinition(
                name: "apply_theme_coordinates",
                description: "Recolor the theme from a FEELING: the engine derives a whole coherent light+dark palette from it. hue: a feeling word (粉嫩, 樱花粉, 薄荷, 晚霞, 天空蓝, 薰衣草, mint, sakura, ocean…) or a #rrggbb hex — unknown words are rejected, never guessed. hueCount 1-5: color complexity, 1 = monochrome anchor. emotion -5..5: vivid/warm (+) vs calm/muted (-). meaning -5..5: deep/tactile (+) vs airy (-). targets: 'all' or comma-separated surface ids (\(surfaceList)) — only those surfaces are recolored. Applies immediately and persists. For a no-commit preview, use preview_theme first, then confirm_theme.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                    "hue": AgentToolParam(type: .string, description: "Feeling word or #rrggbb hex. Required."),
                    "targets": AgentToolParam(type: .string, description: "'all' or comma-separated surface ids. Defaults to 'all'."),
                    "hueCount": AgentToolParam(type: .integer, description: "Color complexity 1-5. Defaults to 3."),
                    "emotion": AgentToolParam(type: .integer, description: "Emotional intensity -5..5. Defaults to 0."),
                    "meaning": AgentToolParam(type: .integer, description: "Presence direction -5..5. Defaults to 0."),
                    "label": AgentToolParam(type: .string, description: "Optional label for this theme."),
                ],
                required: ["tool_title", "hue"],
                propertyOrdering: ["tool_title", "hue", "targets", "hueCount", "emotion", "meaning", "label"]
            ),
            AgentToolDefinition(
                name: "apply_surface_tokens",
                description: "Fine-tune ONE theme surface (single-region precision). target: a surface id (\(surfaceList)). tokens: a JSON object with any of bg, fg, accent, border (#rrggbb) and radius (number, px). Token mapping: bg paints the surface's background role; fg only works on 'text' (primary text); accent only on 'accent'; border only on 'card'; radius only on userBubble/aiBubble/input. Only the given tokens change; everything else stays. Applies to the currently active light/dark variant, immediately, and persists.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                    "target": AgentToolParam(type: .string, description: "Surface id. Required."),
                    "tokens": AgentToolParam(type: .string, description: "JSON object, e.g. {\"bg\":\"#FFE7E8\",\"radius\":18}. Required."),
                ],
                required: ["tool_title", "target", "tokens"],
                propertyOrdering: ["tool_title", "target", "tokens"]
            ),
            AgentToolDefinition(
                name: "apply_preset",
                description: "Apply a built-in theme preset by id. Never invent an id — unknown ids are rejected. Valid: warmPaper, cleanAir, nightCocoa. Applies immediately and persists.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                    "id": AgentToolParam(type: .string, description: "Preset id. Required."),
                ],
                required: ["tool_title", "id"],
                propertyOrdering: ["tool_title", "id"]
            ),
            AgentToolDefinition(
                name: "preview_theme",
                description: "Try-on: stage a theme change as a PREVIEW without saving it. She sees it immediately with a try-on banner (with Save/Discard buttons); nothing is persisted until confirm_theme. seed: a #rrggbb hex, or a JSON object {\"primary\":\"#…\",\"secondary\":\"#…\",\"tertiary\":\"#…\"} — a coherent palette is derived from it. mode: light | dark | system to preview. css: restricted theme-CSS to preview (same language as the theme_css tools). This is the preferred flow — preview first, save second, zero silent changes.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                    "seed": AgentToolParam(type: .string, description: "#rrggbb hex or JSON {\"primary\":\"#…\",\"secondary\":\"#…\",\"tertiary\":\"#…\"}."),
                    "mode": AgentToolParam(type: .string, description: "light | dark | system."),
                    "css": AgentToolParam(type: .string, description: "Restricted theme-CSS to preview."),
                    "label": AgentToolParam(type: .string, description: "Optional label shown on the try-on banner."),
                ],
                required: ["tool_title"],
                propertyOrdering: ["tool_title", "seed", "mode", "css", "label"]
            ),
            AgentToolDefinition(
                name: "confirm_theme",
                description: "Save the staged try-on preview (from preview_theme) permanently. Fails honestly when nothing is staged — call preview_theme first.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                ],
                required: ["tool_title"],
                propertyOrdering: ["tool_title"]
            ),
            AgentToolDefinition(
                name: "rollback_theme",
                description: "One-click rollback: discard any staged try-on preview, or undo the most recent AI-driven theme change and restore the previously confirmed theme. Use when she says the new look is wrong or asks to change it back.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                ],
                required: ["tool_title"],
                propertyOrdering: ["tool_title"]
            ),
            AgentToolDefinition(
                name: "read_theme_css",
                description: "Read the current custom theme-CSS. Returns the raw CSS text, or says there is none. Read before editing.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                ],
                required: ["tool_title"],
                propertyOrdering: ["tool_title"]
            ),
            AgentToolDefinition(
                name: "replace_theme_css",
                description: "Replace the ENTIRE custom theme-CSS with new text. Restricted language: selectors must be .surface-<id> with id in \(surfaceList); properties: bg, fg, accent, border (#rrggbb), radius (number, px). Token rules: bg paints the surface background (no bg on 'text'); fg only on 'text'; accent only on 'accent'; border only on 'card'; radius only on userBubble/aiBubble/input. Invalid CSS is rejected with a line number — nothing is applied on failure. Applies to the active light/dark variant.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                    "css": AgentToolParam(type: .string, description: "Complete replacement CSS. Required."),
                ],
                required: ["tool_title", "css"],
                propertyOrdering: ["tool_title", "css"]
            ),
            AgentToolDefinition(
                name: "append_theme_css",
                description: "Append new CSS rules to the existing custom theme-CSS. Same restricted language as replace_theme_css. The combined result is validated before applying.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                    "css": AgentToolParam(type: .string, description: "CSS rules to append. Required."),
                ],
                required: ["tool_title", "css"],
                propertyOrdering: ["tool_title", "css"]
            ),
            AgentToolDefinition(
                name: "edit_theme_css",
                description: "Replace a snippet of the existing custom theme-CSS. oldText must match exactly; newText replaces it. Same restricted language as replace_theme_css. Validated before applying.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                    "oldText": AgentToolParam(type: .string, description: "Exact text to find. Required."),
                    "newText": AgentToolParam(type: .string, description: "Replacement text. Required."),
                ],
                required: ["tool_title", "oldText", "newText"],
                propertyOrdering: ["tool_title", "oldText", "newText"]
            ),
            AgentToolDefinition(
                name: "insert_theme_css",
                description: "Insert new CSS rules right after the rule containing the anchor text. Same restricted language as replace_theme_css. Validated before applying.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                    "anchor": AgentToolParam(type: .string, description: "Anchor text to insert after. Required."),
                    "css": AgentToolParam(type: .string, description: "CSS rules to insert. Required."),
                ],
                required: ["tool_title", "anchor", "css"],
                propertyOrdering: ["tool_title", "anchor", "css"]
            ),
            AgentToolDefinition(
                name: "delete_theme_css",
                description: "Remove ALL custom theme-CSS, restoring exactly the colors from before the CSS was applied.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user."),
                ],
                required: ["tool_title"],
                propertyOrdering: ["tool_title"]
            ),
        ]
    }

    // MARK: - Dispatch

    func handleThemeTool(name: String, args: [String: Any]) async -> (String, Bool) {
        switch name {
        case "set_wallpaper": return await themeSetWallpaper(args)
        case "set_theme": return themeSetTheme(args)
        case "set_ai_avatar": return await themeSetAIAvatar(args)
        case "get_theme": return themeGetTheme(args)
        case "apply_theme_coordinates": return themeApplyCoordinates(args)
        case "apply_surface_tokens": return themeApplySurfaceTokens(args)
        case "apply_preset": return themeApplyPreset(args)
        case "preview_theme": return themePreview(args)
        case "confirm_theme": return themeConfirm()
        case "rollback_theme": return themeRollback()
        case "read_theme_css": return themeReadCSS()
        case "replace_theme_css": return themeReplaceCSS(args)
        case "append_theme_css": return themeAppendCSS(args)
        case "edit_theme_css": return themeEditCSS(args)
        case "insert_theme_css": return themeInsertCSS(args)
        case "delete_theme_css": return themeDeleteCSS()
        default: return ("Error: Unknown theme tool '\(name)'", false)
        }
    }

    // MARK: - Arg helpers

    private func themeStr(_ args: [String: Any], _ key: String) -> String {
        (args[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func themeInt(_ args: [String: Any], _ key: String, _ fallback: Int) -> Int {
        if let n = args[key] as? Int { return n }
        if let s = args[key] as? String, let n = Int(s.trimmingCharacters(in: .whitespaces)) { return n }
        if let d = args[key] as? Double, d.isFinite { return Int(d) }
        return fallback
    }

    private func themeValidHex(_ raw: String) -> String? {
        ThemeCustomCSS.isHexColor(raw) ? ThemeCustomCSS.normalizeHex(raw) : nil
    }

    /// Surface ids -> the derived-palette keys they recolor (for targets).
    /// Returns [] for "all"/empty (= every surface), nil for invalid input.
    private func themeTargetKeys(_ raw: String) -> [String]? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.lowercased() == "all" { return [] }
        var keys: [String] = []
        for part in text.split(separator: ",") {
            let id = part.trimmingCharacters(in: .whitespaces)
            guard let surface = ThemeSurfaceID(rawValue: id) else { return nil }
            keys.append(contentsOf: surface.paletteKeys)
        }
        return keys
    }

    /// Every palette key any surface maps to (the "all" target set).
    private var themeAllPaletteKeys: [String] {
        Array(Set(ThemeSurfaceID.allCases.flatMap(\.paletteKeys))).sorted()
    }

    /// Resolve an image URI (dudu-clone:// or /var/dudu/ path) to a UIImage.
    private func themeResolveImage(_ uri: String) async -> UIImage? {
        guard !uri.isEmpty,
              let url = await resolveDuduPath(uri),
              FileManager.default.fileExists(atPath: url.path),
              let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        return image
    }

    /// Refresh the stored pack's color maps from the live overrides so a
    /// later pack apply/export stays consistent with direct recolors.
    private func themeSyncPackMaps() {
        let studio = AppearanceStudio.shared
        var pack = studio.currentThemePack()
        var light: [String: String] = [:], dark: [String: String] = [:]
        for role in AppearanceColorRole.allCases {
            light[role.rawValue] = studio.hex(role, scope: .global, variant: .light)
            dark[role.rawValue] = studio.hex(role, scope: .global, variant: .dark)
        }
        pack.colorsLight = light
        pack.colorsDark = dark
        studio.persistPack(pack)
    }

    // MARK: - Handlers

    private func themeSetWallpaper(_ args: [String: Any]) async -> (String, Bool) {
        let studio = AppearanceStudio.shared
        let uri = themeStr(args, "uri")
        if uri.isEmpty {
            studio.removeWallpaper(.global)
            return ("壁纸已清除。", true)
        }
        guard let image = await themeResolveImage(uri) else {
            return ("Error: 找不到这张图片（\(uri)）。请确认图片已发送到聊天中，或换一张。", false)
        }
        studio.setWallpaper(image, for: .global)
        return ("壁纸已更新。", true)
    }

    private func themeSetTheme(_ args: [String: Any]) -> (String, Bool) {
        let mode = themeStr(args, "mode").lowercased()
        let value: Int
        switch mode {
        case "light": value = 1
        case "dark": value = 2
        case "system": value = 0
        default:
            return ("Error: mode 必须是 light、dark 或 system，这里是「\(themeStr(args, "mode"))」。", false)
        }
        UserDefaults.standard.set(value, forKey: "appearanceMode")
        let studio = AppearanceStudio.shared
        studio.objectWillChange.send()
        studio.configureUIKitSurfaces()
        let label = mode == "light" ? "浅色" : mode == "dark" ? "深色" : "跟随系统"
        return ("主题模式已切换为\(label)。", true)
    }

    private func themeSetAIAvatar(_ args: [String: Any]) async -> (String, Bool) {
        let studio = AppearanceStudio.shared
        let uri = themeStr(args, "uri")
        if uri.isEmpty {
            do {
                try studio.removeAssistantAvatar()
                return ("AI 头像已恢复默认。", true)
            } catch {
                return ("Error: 重置头像失败：\(error.localizedDescription)", false)
            }
        }
        guard let image = await themeResolveImage(uri) else {
            return ("Error: 找不到这张图片（\(uri)）。请确认图片已发送到聊天中，或换一张。", false)
        }
        do {
            try studio.setAssistantAvatar(image)
            // SoulStore.save posts .soulMdChanged — the avatar views refresh.
            return ("AI 头像已更新。", true)
        } catch {
            return ("Error: 头像更新失败：\(error.localizedDescription)", false)
        }
    }

    private func themeGetTheme(_ args: [String: Any]) -> (String, Bool) {
        let studio = AppearanceStudio.shared
        let section = themeStr(args, "section")
        let sid = section.isEmpty ? "all" : section
        if sid == "all" {
            // Same payload as ThemeOffloadBridge.currentPack().
            var obj = studio.exportThemePack(includeWallpaper: false).asJSONObject()
            obj["ok"] = true
            guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else {
                return ("Error: 主题读取失败。", false)
            }
            return (json, true)
        }
        guard let surface = ThemeSurfaceID(rawValue: sid) else {
            return ("Error: 未知的 section「\(sid)」。用 all 或：\(ThemeSurfaceID.allCases.map(\.rawValue).joined(separator: ", ")).", false)
        }
        let variant = studio.activeVariant
        var colors: [String: String] = [:]
        for key in surface.paletteKeys {
            if let role = AppearanceColorRole(rawValue: key) {
                colors[key] = studio.hex(role, scope: .global, variant: variant)
            }
        }
        let out: [String: Any] = [
            "section": sid,
            "variant": variant.rawValue,
            "colors": colors,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return ("Error: 主题读取失败。", false)
        }
        return (json, true)
    }

    private func themeApplyCoordinates(_ args: [String: Any]) -> (String, Bool) {
        let hue = themeStr(args, "hue")
        guard !hue.isEmpty else {
            return ("Error: hue 必填（感觉词或 #rrggbb）。", false)
        }
        guard let base = ThemeRecolor.baseHex(from: hue) else {
            return ("Error: 不认识这个颜色「\(hue)」。感觉词如：\(ThemeRecolor.knownFeelingWords.prefix(12).joined(separator: "、"))…，或直接给 #rrggbb。", false)
        }
        guard let keys = themeTargetKeys(themeStr(args, "targets")) else {
            return ("Error: targets 里有未知的 surface。用 all 或：\(ThemeSurfaceID.allCases.map(\.rawValue).joined(separator: ", ")).", false)
        }
        let targetKeys = keys.isEmpty ? themeAllPaletteKeys : keys
        let palettes = ThemeRecolor.derivePalettes(
            baseHex: base,
            hueCount: themeInt(args, "hueCount", 3),
            emotion: Double(themeInt(args, "emotion", 0)),
            meaning: Double(themeInt(args, "meaning", 0)))
        let studio = AppearanceStudio.shared
        ThemeTryOn.shared.recordPreChange()
        for key in targetKeys {
            guard let role = AppearanceColorRole(rawValue: key) else { continue }
            if let hex = palettes.light[key] {
                studio.setColor(Color(hex: hex), role: role, scope: .global, variant: .light)
            }
            if let hex = palettes.dark[key] {
                studio.setColor(Color(hex: hex), role: role, scope: .global, variant: .dark)
            }
        }
        let label = themeStr(args, "label")
        var pack = studio.currentThemePack()
        pack.id = "ai-coordinates"
        pack.name = label.isEmpty ? "AI 配色" : label
        studio.persistPack(pack)
        themeSyncPackMaps()
        let where_ = themeStr(args, "targets").isEmpty
            || themeStr(args, "targets").lowercased() == "all"
            ? "整个主题" : "surface：\(themeStr(args, "targets"))"
        return ("已按「\(hue)」重新配色（\(where_)），浅色/深色两套都已更新。", true)
    }

    private func themeApplySurfaceTokens(_ args: [String: Any]) -> (String, Bool) {
        let target = themeStr(args, "target")
        guard let surface = ThemeSurfaceID(rawValue: target) else {
            return ("Error: 未知的 surface「\(target)」。可用：\(ThemeSurfaceID.allCases.map(\.rawValue).joined(separator: ", ")).", false)
        }
        let tokensStr = themeStr(args, "tokens")
        guard !tokensStr.isEmpty,
              let data = tokensStr.data(using: .utf8),
              let tokens = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !tokens.isEmpty else {
            return ("Error: tokens 必须是 JSON 对象，如 {\"bg\":\"#FFE7E8\",\"radius\":18}。", false)
        }
        // Validate everything BEFORE applying (old Dudu did the same).
        enum Op { case color(role: AppearanceColorRole, hex: String); case radius(Double) }
        var ops: [Op] = []
        for (key, value) in tokens {
            switch key {
            case "bg":
                guard let hex = (value as? String).flatMap(themeValidHex),
                      let role = surface.bgRole else {
                    return ("Error: bg 无效——「\(value)」不是 #rrggbb，或 .surface-\(target) 不支持 bg。", false)
                }
                ops.append(.color(role: role, hex: hex))
            case "fg":
                guard surface == .text,
                      let hex = (value as? String).flatMap(themeValidHex) else {
                    return ("Error: fg 只支持 .surface-text（主文字色），或「\(value)」不是 #rrggbb。", false)
                }
                ops.append(.color(role: .primaryText, hex: hex))
            case "accent":
                guard surface == .accent,
                      let hex = (value as? String).flatMap(themeValidHex) else {
                    return ("Error: accent 属性只支持 .surface-accent，或「\(value)」不是 #rrggbb。", false)
                }
                ops.append(.color(role: .accent, hex: hex))
            case "border":
                guard surface == .card,
                      let hex = (value as? String).flatMap(themeValidHex) else {
                    return ("Error: border 属性只支持 .surface-card，或「\(value)」不是 #rrggbb。", false)
                }
                ops.append(.color(role: .border, hex: hex))
            case "radius":
                let number: Double? = {
                    if let n = value as? Double, n.isFinite { return n }
                    if let n = value as? Int { return Double(n) }
                    if let s = value as? String { return Double(s) }
                    return nil
                }()
                guard let n = number, n >= 0, n <= 64, surface.radiusApplies else {
                    return ("Error: radius 必须是 0-64 的数字，且只支持 userBubble / aiBubble / input。", false)
                }
                ops.append(.radius(min(32, max(4, n))))
            default:
                return ("Error: 不支持的 token「\(key)」，只允许 bg / fg / accent / border / radius。", false)
            }
        }
        guard !ops.isEmpty else {
            return ("Error: tokens 是空的，没有可改的。", false)
        }
        let studio = AppearanceStudio.shared
        let variant = studio.activeVariant
        ThemeTryOn.shared.recordPreChange()
        var pack = studio.currentThemePack()
        var packChanged = false
        for op in ops {
            switch op {
            case .color(let role, let hex):
                studio.setColor(Color(hex: hex), role: role, scope: .global, variant: variant)
            case .radius(let n):
                switch surface {
                case .userBubble: pack.userBubbleRadius = n
                case .aiBubble: pack.assistantBubbleRadius = n
                case .input: pack.inputBarRadius = n
                default: break
                }
                packChanged = true
            }
        }
        if packChanged { studio.persistPack(pack) }
        themeSyncPackMaps()
        let variantName = variant == .dark ? "深色" : "浅色"
        return ("surface「\(target)」已更新（\(variantName)模式，\(ops.count) 个 token）。", true)
    }

    private func themeApplyPreset(_ args: [String: Any]) -> (String, Bool) {
        let id = themeStr(args, "id")
        guard let preset = AppearancePreset(rawValue: id) else {
            return ("Error: 未知的 preset「\(id)」。可用：\(AppearancePreset.allCases.map(\.rawValue).joined(separator: ", ")).", false)
        }
        ThemeTryOn.shared.recordPreChange()
        AppearanceStudio.shared.applyPreset(preset)
        themeSyncPackMaps()
        return ("预设「\(preset.title)」已应用。", true)
    }

    private func themePreview(_ args: [String: Any]) -> (String, Bool) {
        let studio = AppearanceStudio.shared
        let seedStr = themeStr(args, "seed")
        let modeStr = themeStr(args, "mode").lowercased()
        let css = themeStr(args, "css")
        let label = themeStr(args, "label")

        var pack: AppearanceThemePack? = nil
        if !seedStr.isEmpty {
            guard let primary = themeParseSeed(seedStr) else {
                return ("Error: seed 无效。用 #rrggbb，或 JSON {\"primary\":\"#…\",\"secondary\":\"#…\",\"tertiary\":\"#…\"}。", false)
            }
            let palettes = ThemeRecolor.derivePalettes(baseHex: primary, hueCount: 3,
                                                       emotion: 0, meaning: 0)
            pack = ThemeRecolor.previewPack(from: palettes,
                                            label: label.isEmpty ? "AI 试穿" : label)
        }
        var mode: Int? = nil
        if !modeStr.isEmpty {
            switch modeStr {
            case "light": mode = 1
            case "dark": mode = 2
            case "system": mode = 0
            default:
                return ("Error: mode 必须是 light、dark 或 system。", false)
            }
        }
        guard pack != nil || mode != nil || !css.isEmpty else {
            return ("Error: 没有可预览的内容——至少给 seed、mode 或 css 其中之一。", false)
        }
        do {
            try ThemeTryOn.shared.stage(pack: pack ?? studio.currentThemePack(),
                                        label: label.isEmpty ? "AI 试穿" : label,
                                        mode: mode,
                                        css: css.isEmpty ? nil : css)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return ("Error: 试穿失败：\(msg)", false)
        }
        return ("试穿已开始，她现在能看到效果（屏幕下方有试穿横幅）。调用 confirm_theme 保存，rollback_theme 放弃。", true)
    }

    /// seed: #rrggbb or JSON {"primary":..,"secondary":..,"tertiary":..}.
    /// Returns the primary hex.
    private func themeParseSeed(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if ThemeCustomCSS.isHexColor(t) { return ThemeCustomCSS.normalizeHex(t) }
        guard let data = t.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let primary = (obj["primary"] as? String).flatMap(themeValidHex) else {
            return nil
        }
        return primary
    }

    private func themeConfirm() -> (String, Bool) {
        if ThemeTryOn.shared.commit() {
            return ("试穿已保存，主题已更新。", true)
        }
        return ("Error: 没有正在试穿的主题。先调用 preview_theme 开始试穿。", false)
    }

    private func themeRollback() -> (String, Bool) {
        if let msg = ThemeTryOn.shared.rollback() {
            return (msg, true)
        }
        return ("Error: 没有可回退的主题（没有试穿中的预览，也没有 AI 改过的主题记录）。", false)
    }

    private func themeReadCSS() -> (String, Bool) {
        let css = ThemeCustomCSS.shared.cssText
        return (css.isEmpty ? "没有自定义主题 CSS。" : css, true)
    }

    private func themeReplaceCSS(_ args: [String: Any]) -> (String, Bool) {
        let css = themeStr(args, "css")
        guard !css.isEmpty else { return ("Error: css 必填。", false) }
        ThemeTryOn.shared.recordPreChange()
        do {
            try ThemeCustomCSS.shared.apply(css)
            themeSyncPackMaps()
            return ("主题 CSS 已整体替换。", true)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return ("Error: CSS 被拒绝：\(msg)", false)
        }
    }

    private func themeAppendCSS(_ args: [String: Any]) -> (String, Bool) {
        let fragment = themeStr(args, "css")
        guard !fragment.isEmpty else { return ("Error: css 必填。", false) }
        let existing = ThemeCustomCSS.shared.cssText
        let combined = existing.isEmpty ? fragment : existing + "\n" + fragment
        ThemeTryOn.shared.recordPreChange()
        do {
            try ThemeCustomCSS.shared.apply(combined)
            themeSyncPackMaps()
            return ("主题 CSS 已追加。", true)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return ("Error: CSS 被拒绝：\(msg)", false)
        }
    }

    private func themeEditCSS(_ args: [String: Any]) -> (String, Bool) {
        let oldText = themeStr(args, "oldText")
        let newText = themeStr(args, "newText")
        guard !oldText.isEmpty else { return ("Error: oldText 必填。", false) }
        let existing = ThemeCustomCSS.shared.cssText
        guard existing.contains(oldText) else {
            return ("Error: oldText 在当前主题 CSS 里找不到。先用 read_theme_css 看看。", false)
        }
        ThemeTryOn.shared.recordPreChange()
        do {
            try ThemeCustomCSS.shared.apply(existing.replacingOccurrences(of: oldText, with: newText))
            themeSyncPackMaps()
            return ("主题 CSS 已修改。", true)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return ("Error: CSS 被拒绝：\(msg)", false)
        }
    }

    private func themeInsertCSS(_ args: [String: Any]) -> (String, Bool) {
        let anchor = themeStr(args, "anchor")
        let fragment = themeStr(args, "css")
        guard !anchor.isEmpty else { return ("Error: anchor 必填。", false) }
        guard !fragment.isEmpty else { return ("Error: css 必填。", false) }
        let existing = ThemeCustomCSS.shared.cssText
        guard let anchorRange = existing.range(of: anchor) else {
            return ("Error: anchor 在当前主题 CSS 里找不到。先用 read_theme_css 看看。", false)
        }
        // Insert after the closing brace of the rule containing the anchor.
        let searchFrom = anchorRange.lowerBound
        guard let closeIdx = existing[searchFrom...].firstIndex(of: "}") else {
            return ("Error: anchor 所在的规则没有闭合的 }。", false)
        }
        let insertAt = existing.index(after: closeIdx)
        let combined = String(existing[..<insertAt]) + "\n" + fragment + String(existing[insertAt...])
        ThemeTryOn.shared.recordPreChange()
        do {
            try ThemeCustomCSS.shared.apply(combined)
            themeSyncPackMaps()
            return ("主题 CSS 已插入。", true)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return ("Error: CSS 被拒绝：\(msg)", false)
        }
    }

    private func themeDeleteCSS() -> (String, Bool) {
        if ThemeCustomCSS.shared.isEmpty {
            return ("没有自定义主题 CSS 可删。", true)
        }
        ThemeTryOn.shared.recordPreChange()
        ThemeCustomCSS.shared.clear()
        themeSyncPackMaps()
        return ("自定义主题 CSS 已删除，恢复到之前的颜色。", true)
    }
}

// MARK: - ThemeSurfaceID palette mapping

extension ThemeSurfaceID {
    /// Derived-palette keys this surface recolors (for apply_theme_coordinates targets).
    var paletteKeys: [String] {
        switch self {
        case .canvas: return ["canvas"]
        case .card: return ["surface", "mutedSurface", "raised"]
        case .input: return ["input", "searchField"]
        case .userBubble: return ["userBubble"]
        case .aiBubble: return ["assistantBubble"]
        case .accent: return ["accent", "toolCard"]
        case .text: return ["primaryText", "secondaryText"]
        case .overlay: return ["raised"]
        }
    }
}
