import Foundation

// MARK: - ThemeRecolor · 感觉词换肤
//
// Old Dudu's "stable four-axis recolor" (apps/mobile/src/theme/tools.ts
// apply_theme_coordinates + coordinates.ts), native edition.
//
//   hue        — feeling word (粉嫩, 樱花粉, 薄荷, 晚霞, 天空蓝, 薰衣草,
//                mint, sakura, ocean…) or a #rrggbb hex
//   hueCount   — 1-5 color complexity (1 = monochrome anchor)
//   emotion    — -5..5 warm/bold (+) vs calm/muted (-)
//   meaning    — -5..5 tactile/material (+) vs airy (-)
//
// The engine derives coherent light + dark role palettes from the base
// hue and applies them through AppearanceStudio — a REAL recolor, not a
// preset lookup. preview_theme reuses the same derivation for try-on.

enum ThemeRecolor {

    // MARK: Feeling words (ported from old Dudu coordinates.ts)

    static let feelingHues: [String: String] = [
        "粉嫩": "F4A7C3", "粉色": "F4A7C3", "粉": "F4A7C3", "pink": "F4A7C3",
        "樱花粉": "F8B4D0", "樱花": "F8B4D0", "sakura": "F8B4D0",
        "少女粉": "F9A8D4",
        "晚霞": "F9A875", "晚霞粉": "F6A5A5", "蜜桃": "F9B08C", "桃色": "F9B08C",
        "peach": "F9B08C", "橙色": "F6AD55", "橙": "F6AD55", "orange": "F6AD55",
        "薄荷": "7FE0B8", "薄荷绿": "7FE0B8", "青绿": "7FE0B8", "mint": "7FE0B8",
        "抹茶": "A8D5A2", "抹茶绿": "A8D5A2", "草绿": "9AE6A0",
        "绿色": "86D68A", "绿": "86D68A", "green": "86D68A",
        "天空蓝": "8ECAE6", "天空": "8ECAE6", "蓝色": "7FB8E8", "蓝": "7FB8E8",
        "blue": "7FB8E8", "sky": "8ECAE6",
        "海洋": "5B9BD5", "深海": "4A7FB5", "海蓝": "5B9BD5", "ocean": "5B9BD5",
        "雾蓝": "93A8B8", "灰蓝": "93A8B8", "青瓷": "8FC7C0", "青色": "8FC7C0",
        "teal": "8FC7C0",
        "薰衣草": "B8A9E0", "淡紫": "C4B5FD", "紫色": "B39DDB", "紫": "B39DDB",
        "purple": "B39DDB", "lavender": "B8A9E0", "葡萄紫": "9D7BD8",
        "柠檬": "F5D67B", "柠檬黄": "F5D67B", "黄色": "F0D060", "黄": "F0D060",
        "yellow": "F0D060", "lemon": "F5D67B", "鹅黄": "F7E08B",
        "玫瑰": "E08A9B", "玫瑰红": "E08A9B", "红色": "E0707F", "红": "E0707F",
        "red": "E0707F", "rose": "E08A9B", "樱桃红": "D86A7A",
        "穹妹灰": "AAA7AA", "灰色": "9AA0A6", "灰": "9AA0A6",
        "gray": "9AA0A6", "grey": "9AA0A6", "雾灰": "B0B5BA",
        "石墨": "6E6E73", "深灰": "6E6E73",
        "奶油": "E8DCC8", "米色": "E8DCC8", "燕麦": "DDD0B8",
        "cream": "E8DCC8", "beige": "E8DCC8",
        "墨色": "4A4A4E", "黑": "3A3A3E", "black": "3A3A3E",
        "白色": "F5F5F4", "白": "F5F5F4", "white": "F5F5F4",
    ]

    static var knownFeelingWords: [String] { feelingHues.keys.sorted() }

    /// Resolve a hue argument to a base hex (RRGGBB), or nil.
    static func baseHex(from hue: String) -> String? {
        let trimmed = hue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if ThemeCustomCSS.isHexColor(trimmed) {
            return ThemeCustomCSS.normalizeHex(trimmed)
        }
        let key = trimmed.lowercased()
        if let hit = feelingHues[key] { return hit }
        if let hit = feelingHues[trimmed] { return hit }
        return nil
    }

    // MARK: - Derivation

    struct HSL { var h: Double; var s: Double; var l: Double }

    static func hexToHSL(_ hex: String) -> HSL? {
        let t = hex.trimmingCharacters(in: .whitespaces)
        let h = t.hasPrefix("#") ? String(t.dropFirst()) : t
        guard h.count >= 6 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: String(h.prefix(6))).scanHexInt64(&value) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        guard maxV != minV else { return HSL(h: 0, s: 0, l: l) }
        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var hh: Double
        if maxV == r { hh = (g - b) / d + (g < b ? 6 : 0) }
        else if maxV == g { hh = (b - r) / d + 2 }
        else { hh = (r - g) / d + 4 }
        return HSL(h: hh * 60, s: s, l: l)
    }

    static func hslToHex(_ hsl: HSL) -> String {
        let h = ((hsl.h.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360) / 360
        let s = min(1, max(0, hsl.s))
        let l = min(1, max(0, hsl.l))
        func hue2rgb(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1/6 { return p + (q - p) * 6 * t }
            if t < 1/2 { return q }
            if t < 2/3 { return p + (q - p) * (2/3 - t) * 6 }
            return p
        }
        let (r, g, b): (Double, Double, Double)
        if s == 0 {
            (r, g, b) = (l, l, l)
        } else {
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s
            let p = 2 * l - q
            (r, g, b) = (hue2rgb(p, q, h + 1/3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1/3))
        }
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// Derive coherent light + dark palettes (role rawValue -> RRGGBB).
    /// - hueCount 1..5: distinct hues used (1 = monochrome anchor)
    /// - emotion -5..5: + = vivid/warm, - = muted/calm
    /// - meaning -5..5: + = deep/tactile, - = airy/light
    static func derivePalettes(baseHex: String, hueCount: Int,
                               emotion: Double, meaning: Double) -> (light: [String: String], dark: [String: String]) {
        let base = hexToHSL(baseHex) ?? HSL(h: 340, s: 0.45, l: 0.72)
        let count = min(5, max(1, hueCount))
        let emo = min(5, max(-5, emotion)) / 5      // -1..1
        let mea = min(5, max(-5, meaning)) / 5      // -1..1

        // Companion hues: analogous spread, wider when hueCount is high.
        func companion(_ index: Int) -> HSL {
            guard count > 1, index > 0 else { return base }
            let spread = Double(28 + 14 * (count - 2)) // 28°..70°
            var c = base
            c.h += spread * Double(index) / Double(count - 1)
            return c
        }

        // Saturation energy: emotion pushes vividness, meaning deepens it.
        func energized(_ hsl: HSL, boost: Double = 0) -> HSL {
            var c = hsl
            c.s = min(0.95, max(0.04, c.s * (1 + 0.35 * emo) + 0.08 * boost))
            return c
        }

        let accentL = energized(base)
        let secondL = energized(companion(1))

        // Airy (-) lifts the canvas toward white; tactile (+) deepens it.
        let canvasLift = 0.94 - 0.05 * mea
        // Muted emotion (-) pulls text toward neutral warm gray.
        let textSat = max(0.05, 0.14 * (1 + 0.6 * emo))

        func light() -> [String: String] {
            var m: [String: String] = [:]
            m["canvas"] = hslToHex(HSL(h: base.h, s: 0.16, l: canvasLift))
            m["surface"] = hslToHex(HSL(h: base.h, s: 0.10, l: min(1, canvasLift + 0.03)))
            m["raised"] = hslToHex(HSL(h: base.h, s: 0.08, l: 1.0))
            m["mutedSurface"] = hslToHex(HSL(h: base.h, s: 0.18, l: canvasLift - 0.05))
            m["primaryText"] = hslToHex(HSL(h: 20, s: textSat, l: 0.24 - 0.02 * mea))
            m["secondaryText"] = hslToHex(HSL(h: 20, s: textSat * 0.8, l: 0.45))
            m["accent"] = hslToHex(HSL(h: accentL.h, s: accentL.s, l: 0.62 + 0.06 * emo))
            m["userBubble"] = hslToHex(HSL(h: secondL.h, s: min(0.6, secondL.s + 0.1), l: 0.88))
            m["assistantBubble"] = hslToHex(HSL(h: base.h, s: 0.06, l: 1.0))
            m["input"] = hslToHex(HSL(h: base.h, s: 0.08, l: 1.0))
            m["border"] = hslToHex(HSL(h: base.h, s: 0.14, l: 0.88))
            m["searchField"] = m["input"]!
            m["toolCard"] = m["mutedSurface"]!
            m["success"] = "638F76"; m["warning"] = "C9A36A"; m["destructive"] = "BC6262"
            return m
        }

        func dark() -> [String: String] {
            var m: [String: String] = [:]
            // Deep base-tinted canvas; tactile (+) goes darker.
            let depth = 0.13 - 0.03 * mea
            m["canvas"] = hslToHex(HSL(h: base.h, s: 0.16, l: depth))
            m["surface"] = hslToHex(HSL(h: base.h, s: 0.14, l: depth + 0.05))
            m["raised"] = hslToHex(HSL(h: base.h, s: 0.14, l: depth + 0.08))
            m["mutedSurface"] = hslToHex(HSL(h: base.h, s: 0.16, l: depth + 0.10))
            m["primaryText"] = hslToHex(HSL(h: base.h, s: 0.18, l: 0.92))
            m["secondaryText"] = hslToHex(HSL(h: base.h, s: 0.12, l: 0.66))
            m["accent"] = hslToHex(HSL(h: accentL.h, s: min(0.8, accentL.s + 0.05), l: 0.70))
            m["userBubble"] = hslToHex(HSL(h: secondL.h, s: 0.30, l: 0.30))
            m["assistantBubble"] = m["surface"]!
            m["input"] = hslToHex(HSL(h: base.h, s: 0.12, l: depth + 0.06))
            m["border"] = hslToHex(HSL(h: base.h, s: 0.14, l: depth + 0.14))
            m["searchField"] = m["surface"]!
            m["toolCard"] = m["mutedSurface"]!
            m["success"] = "82AF91"; m["warning"] = "D4B07A"; m["destructive"] = "DA8181"
            return m
        }

        // Monochrome anchor: collapse the companion back onto the base hue.
        if count == 1 {
            var l = light(), d = dark()
            for key in ["userBubble"] {
                if var hsl = hexToHSL(l[key] ?? "") {
                    hsl.h = base.h
                    l[key] = hslToHex(hsl)
                }
                if var hsl = hexToHSL(d[key] ?? "") {
                    hsl.h = base.h
                    d[key] = hslToHex(hsl)
                }
            }
            return (l, d)
        }
        return (light(), dark())
    }

    /// Build a preview pack from a derivation, keeping the current pack's
    /// shape (radii / bubble styles / images stay untouched).
    /// @MainActor: reads the live pack via AppearanceStudio (MainActor).
    @MainActor
    static func previewPack(from palettes: (light: [String: String], dark: [String: String]),
                            label: String) -> AppearanceThemePack {
        var pack = AppearanceStudio.shared.currentThemePack()
        pack.id = "ai-preview"
        pack.name = label.isEmpty ? "AI 试穿" : label
        pack.colorsLight = palettes.light
        pack.colorsDark = palettes.dark
        return pack
    }
}
