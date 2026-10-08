import SwiftUI
import UIKit

// MARK: - DuduTheme · fixed design tokens
//
// The single theme access point for all Dudu UI. Values below are extracted
// VERBATIM from ~/workspace/openmuse/design-tokens.css (嘟嘟 UI 定妆, 2026-10-06).
//
// Two layers:
//   1. Fixed tokens (this file): brand pinks, kitty, radii, spacing, base type
//      sizes. Never user-overridable. Light/dark variants follow the CSS
//      [data-theme="dark"] first-draft values.
//   2. Dynamic roles: the existing DuduTheme.color(_:scope:) (defined in
//      Dudu/Shared/AppearanceStudio.swift) resolves through AppearanceStudio,
//      so user customization keeps working. Views must NEVER call
//      AppearanceStudio.color directly — always go through DuduTheme.
//
// Rules for builders:
//   - No hardcoded colors anywhere. Every color comes from DuduTheme.
//   - Type always via the font helpers below (they route through
//     FontSettings.shared scaling). No literal point sizes in views.
//   - Dark mode follows the iOS system setting (plus the studio's
//     appearanceMode override). The adaptive() helper below resolves both.

extension DuduTheme {
    // MARK: Brand four · 品牌四色 (fixed, both schemes)

    /// #8B736C — primary text. Never pure black.
    static var brandBrown: Color { Color(hex: "8B736C") }
    /// #FFE7E8 — icon chip background, accents on white.
    static var pinkSoft: Color { Color(hex: "FFE7E8") }
    /// #FBF8EA — page background (light).
    static var cream: Color { Color(hex: "FBF8EA") }
    /// #ECC7D6 — accent, solid icon glyphs.
    static var pink: Color { Color(hex: "ECC7D6") }
    /// #2A2A2E — black-cat silhouette (fixed, both modes).
    static var kitty: Color { Color(hex: "2A2A2E") }
    /// rgba(86,60,62,0.10) — soft drop shadow under floating glass
    /// capsules (html-2 定稿: 0 12px 35px). Fixed, both schemes.
    static var capsuleShadow: Color { Color(hex: "563C3E").opacity(0.10) }
    /// #171518 (light) / #09090b (dark) — black-cat ink for BlackCatView's
    /// solid fills. Dynamic: follows the iOS system appearance (plus the
    /// studio's appearanceMode override) via adaptive(), never hardcoded.
    static var kittyInk: Color { adaptive(light: "171518", dark: "09090b") }

    // MARK: Semantic tokens · 语义色 (light/dark variants)

    /// Page background. Light #FBF8EA · dark #1C1917 (first draft).
    static var duduBackground: Color { adaptive(light: "FBF8EA", dark: "1C1917") }
    /// Card surface. Light #FFFFFF · dark #2A2523 (first draft).
    static var duduCard: Color { adaptive(light: "FFFFFF", dark: "2A2523") }
    /// Primary text. Light #8B736C · dark #E8D9D2 (first draft).
    static var duduText: Color { adaptive(light: "8B736C", dark: "E8D9D2") }
    /// Dim/secondary text. Light #A89890 · dark #8A7A74 (derived, pending her review).
    static var duduTextDim: Color { adaptive(light: "A89890", dark: "8A7A74") }
    /// Icon chip background. Light #FFE7E8 · dark #4A3A36 (first draft).
    static var duduIconChip: Color { adaptive(light: "FFE7E8", dark: "4A3A36") }
    /// Dividers. Light #F1E7E2 · dark #38302C (derived, pending her review).
    static var duduDivider: Color { adaptive(light: "F1E7E2", dark: "38302C") }

    /// Destructive red. Theme role (user-customizable via the 外观 page),
    /// not a fixed token — defaults light #BC6262 / dark #DA8181.
    static var duduDestructive: Color {
        AppearanceStudio.shared.color(.destructive, scope: .global)
    }

    /// Resolves a fixed token for the current scheme: iOS system setting,
    /// honoring the studio's appearanceMode override (1 = force light,
    /// 2 = force dark). Implemented as a dynamic UIColor provider so the
    /// color adapts without requiring views to re-render on scheme change.
    private static func adaptive(light lightHex: String, dark darkHex: String) -> Color {
        Color(uiColor: UIColor { traits in
            let forced = UserDefaults.standard.integer(forKey: "appearanceMode")
            if forced == 1 { return UIColor(hex: lightHex) }
            if forced == 2 { return UIColor(hex: darkHex) }
            return UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
        })
    }

    // MARK: Radii · 圆角
    // Per html-2 定稿 (Wave 2 Item 10): 22pt large cards, 17pt rows/chips.
    // design-tokens.css still says 16/12 (stale, predates the black-cat rounds).

    static let radiusCard: CGFloat = 22
    static let radiusChip: CGFloat = 17
    static let radiusPill: CGFloat = 999

    // MARK: Spacing · 留白

    static let pagePadding: CGFloat = 16
    static let groupSpacing: CGFloat = 28
    static let rowHeight: CGFloat = 56

    // MARK: Type · 字号 (base sizes; scaled through FontSettings)

    static let titleSize: CGFloat = 15
    static let bodySize: CGFloat = 13
    static let captionSize: CGFloat = 11

    /// General UI title text (settings rows, nav titles). → FontSettings app axis.
    static func titleFont(weight: Font.Weight = .semibold) -> Font {
        baseFont(scaledSize: FontSettings.shared.scaledApp(titleSize), weight: weight)
    }
    /// General UI body text. → FontSettings app axis.
    static func bodyFont(weight: Font.Weight = .regular) -> Font {
        baseFont(scaledSize: FontSettings.shared.scaledApp(bodySize), weight: weight)
    }
    /// Captions, timestamps, hints. → FontSettings app axis.
    static func captionFont(weight: Font.Weight = .regular) -> Font {
        baseFont(scaledSize: FontSettings.shared.scaledApp(captionSize), weight: weight)
    }
    /// Chat message body (markdown base size). → FontSettings message axis.
    static func messageFont(weight: Font.Weight = .regular) -> Font {
        baseFont(scaledSize: FontSettings.shared.scaledMessage(bodySize), weight: weight)
    }
    /// Chat input field text. → FontSettings chat-input axis.
    static func inputFont(weight: Font.Weight = .regular) -> Font {
        baseFont(scaledSize: FontSettings.shared.scaledChatInput(bodySize), weight: weight)
    }
    /// Monospace for code. Size is explicit at the call site (still scaled).
    /// Always the system mono — an uploaded custom font never applies here,
    /// so code stays readable.
    static func monoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: FontSettings.shared.scaledMessage(size), weight: weight, design: .monospaced)
    }
    /// Heading H1: title base size plus a delta, semibold. → FontSettings app axis.
    static func headingFont(delta: CGFloat) -> Font {
        baseFont(scaledSize: FontSettings.shared.scaledApp(titleSize + delta), weight: .semibold)
    }

    /// Base font constructor (D12): an uploaded custom font wins over the
    /// system font. The registered file is a single face, so weight is
    /// synthesized by the OS. Sizes keep flowing through FontSettings —
    /// upload changes the FAMILY, never the scale.
    private static func baseFont(scaledSize: CGFloat, weight: Font.Weight) -> Font {
        if let family = CustomFontManager.shared.activePostScriptName {
            return Font.custom(family, size: scaledSize)
        }
        return .system(size: scaledSize, weight: weight)
    }
}
