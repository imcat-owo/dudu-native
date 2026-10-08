import SwiftUI
import UIKit

// MARK: - DuduTheme · design tokens
//
// The single theme access point for all Dudu UI. Values below are extracted
// from ~/workspace/openmuse/design-tokens.css (嘟嘟 UI 定妆, 2026-10-06).
//
// [Wave 3 P1] One unified system: every semantic color token reads its
// AppearanceStudio role live (see the token docs below). The 外观 page,
// try-on staging, theme-pack import and the AI theme tools all write into
// AppearanceStudio.shared — and DuduTabView (the app root) already owns it
// as @StateObject, so any write re-renders the whole tree and these tokens
// resolve to the new colors with zero per-view changes. Views must NEVER
// call AppearanceStudio.color directly — always go through DuduTheme.
//
// Layers:
//   1. Live semantic tokens (this file): background/card/text/accent/… —
//      user-customizable through the 外观 page or the AI theme tools.
//      With no overrides they resolve to the 定妆 values, pinned in
//      AppearancePaletteBook (Dudu/Shared/AppearanceStudio.swift).
//   2. Fixed brand anchors: brandBrown / cream / kitty / kittyInk /
//      capsuleShadow. Identity, never user-overridable.
//
// Rules for builders:
//   - No hardcoded colors anywhere. Every color comes from DuduTheme.
//   - Type always via the font helpers below (they route through
//     FontSettings.shared scaling). No literal point sizes in views.
//   - Dark mode follows the iOS system setting (plus the studio's
//     appearanceMode override); AppearanceStudio resolves the variant.

extension DuduTheme {
    // MARK: Brand anchors · 品牌锚点 (fixed, both schemes)
    //
    // Deliberately NOT themeable: the black-cat silhouette, the cream page
    // base and the brand brown are identity, not theme. Everything else in
    // this file routes through AppearanceStudio so the 外观 page, try-on
    // and the AI theme tools visibly recolor the app.

    /// #8B736C — brand brown. Never pure black. Fixed identity anchor
    /// (not the themeable primary-text role; see duduText).
    static var brandBrown: Color { Color(hex: "8B736C") }
    /// #FBF8EA — page background (light). Fixed brand anchor; the live
    /// page background is duduBackground (themeable).
    static var cream: Color { Color(hex: "FBF8EA") }
    /// #2A2A2E — black-cat silhouette (fixed, both modes).
    static var kitty: Color { Color(hex: "2A2A2E") }
    /// rgba(86,60,62,0.10) — soft drop shadow under floating glass
    /// capsules (html-2 定稿: 0 12px 35px). Fixed, both schemes.
    static var capsuleShadow: Color { Color(hex: "563C3E").opacity(0.10) }
    /// #171518 (light) / #09090b (dark) — black-cat ink for BlackCatView's
    /// solid fills. Dynamic: follows the iOS system appearance (plus the
    /// studio's appearanceMode override) via adaptive(), never hardcoded.
    static var kittyInk: Color { adaptive(light: "171518", dark: "09090b") }

    // MARK: Semantic tokens · 语义色 (live)
    //
    // [Wave 3 P1] Each token reads its AppearanceStudio role at access time.
    // Writes from the 外观 page, try-on staging, theme-pack import and the
    // AI theme tools land in AppearanceStudio.shared; DuduTabView owns it as
    // @StateObject, so the tree re-renders and these resolve to the new
    // colors. No-override defaults are the 定妆 values (see
    // AppearancePaletteBook): light cream #FBF8EA / pink #ECC7D6 /
    // brown-black #8B736C, dark per the first-draft values noted below.

    /// Page background. → canvas role. Default light #FBF8EA · dark #1C1917.
    static var duduBackground: Color { color(.canvas) }
    /// Card surface. → surface role. Default light #FFFFFF · dark #2A2523.
    static var duduCard: Color { color(.surface) }
    /// Primary text. → primaryText role. Default light #8B736C · dark #E8D9D2.
    static var duduText: Color { color(.primaryText) }
    /// Dim/secondary text. → secondaryText role. Default light #A89890 · dark #8A7A74.
    static var duduTextDim: Color { color(.secondaryText) }
    /// Icon chip background. → mutedSurface role. Default light #FFE7E8 · dark #4A3A36.
    static var duduIconChip: Color { color(.mutedSurface) }
    /// Soft tinted chip/highlight background. Fixed #FFE7E8 in both schemes
    /// (was fixed before the System A/B unification; not theme-customizable).
    static var pinkSoft: Color { Color(hex: "FFE7E8") }
    /// Dividers. → border role. Default light #F1E7E2 · dark #38302C.
    static var duduDivider: Color { color(.border) }
    /// Accent: selected states, completed checks, solid icon glyphs.
    /// → accent role. Default #ECC7D6 (both schemes).
    static var pink: Color { color(.accent) }

    /// Destructive red. Theme role (user-customizable via the 外观 page),
    /// not a fixed token — defaults light #C75D5D / dark #E18484.
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
