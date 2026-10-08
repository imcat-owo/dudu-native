import SwiftUI
import UIKit

// MARK: - DuduIcon · Q萌 solid SF Symbol
//
// Shared drop-in replacement for Image(systemName:) across Dudu/Views,
// per the html-2 定稿 (Q萌 rounded SOLID icons).
//
// - Renders the glyph SOLID via .symbolVariant(.fill) when SF Symbols
//   ships a fill variant for the name (e.g. "trash" renders "trash.fill").
//   Names already ending in ".fill" pass through unchanged.
// - When no fill variant exists (e.g. "chevron.right", "plus", "xmark"),
//   thickens the line glyph with .fontWeight(.bold) + a slight scale so
//   it still reads chunky/Q萌 instead of thin.
// - The pink chip structure (DuduTheme.duduIconChip rounded bg + glyph)
//   already exists at the call sites and is left untouched — this view
//   only swaps the glyph weight, never adds its own background.
// - Fill-variant detection is a runtime UIImage(systemName:) check, not
//   a hardcoded table, so it stays correct as SF Symbols evolves.
//
// NOT migrated (per plan): DuduTabBar icons (already custom solid) and
// BlackCatView.
struct DuduIcon: View {
    let systemName: String
    private let useFill: Bool

    init(systemName: String) {
        self.systemName = systemName
        self.useFill = UIImage(systemName: systemName + ".fill") != nil
    }

    var body: some View {
        if useFill {
            Image(systemName: systemName)
                .symbolVariant(.fill)
        } else {
            Image(systemName: systemName)
                .fontWeight(.bold)
                .scaleEffect(1.08)
        }
    }
}
