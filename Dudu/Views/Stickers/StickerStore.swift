import Foundation
import UIKit

// MARK: - D17 · Sticker packs (表情包)
//
// Pack model: the 10 devil mascot images she approved (2026-10-06) are the
// built-in "ai" pack, bundled verbatim under Dudu/Resources/Stickers/.
// Extensible: future her-packs append to `StickerStore.packs` without
// touching the picker — pack ids are STABLE and never reused.
//
// Behavior intent ported from openmuse apps/mobile/src/sticker/
// (types.ts + store.ts):
// - The built-in pack is always present and can never be deleted.
// - Sent messages keep rendering: the picker inserts the sticker's bytes
//   into the draft as an image attachment (via
//   AIChatViewModel.addImageAttachment(data:fileExtension:)), which the
//   attachment pipeline copies into its own cache dir — the sent bubble
//   never points at a pack file that can disappear.

/// A sticker pack: stable id, display name, stickers in display order.
struct StickerPack: Identifiable, Equatable {
    /// Stable pack id, never reused. The built-in pack uses "ai"
    /// (mirrors old Dudu's AI_PACK_ID).
    let id: String
    /// Display name.
    let name: String
    /// Stickers in display order.
    let stickers: [Sticker]
}

/// A single sticker. Bundled stickers resolve to files in the app bundle;
/// future user packs can point at files in the app's data dir instead.
struct Sticker: Identifiable, Equatable {
    /// "<packId>/<resourceName>" — stable.
    let id: String
    let packId: String
    /// Display name ("devil-03" style for the built-in pack).
    let name: String
    /// Bundle resource name without extension, e.g. "devil-03".
    let resourceName: String
    /// Lowercase extension without the dot, e.g. "jpg".
    let fileExtension: String
}

/// The sticker library.
enum StickerStore {
    /// Built-in pack id — mirrors old Dudu's AI_PACK_ID ("ai"), stable forever.
    static let builtInPackId = "ai"

    /// The built-in pack, seeded with the 10 devil mascot images in their
    /// approved numbered order. Never deleted, never reordered.
    static let builtInPack: StickerPack = {
        let stickers = (1...10).map { n -> Sticker in
            let base = String(format: "devil-%02d", n)
            return Sticker(
                id: "\(builtInPackId)/\(base)",
                packId: builtInPackId,
                name: base,
                resourceName: base,
                fileExtension: "jpg"
            )
        }
        // Matches old Dudu's zh-Hans name for the AI pack ("AI 表情库").
        return StickerPack(id: builtInPackId, name: "AI 表情库", stickers: stickers)
    }()

    /// All packs: the built-in pack first, then any future packs in
    /// creation order. (Future: her own packs backed by a store; today
    /// only the built-in pack exists.)
    static var packs: [StickerPack] { [builtInPack] }

    /// Raw file bytes for a sticker. Bundled stickers read from the app
    /// bundle — Copy Bundle Resources copies them flat into the bundle
    /// root, so a plain forResource lookup finds them.
    static func imageData(for sticker: Sticker) -> Data? {
        if let url = Bundle.main.url(forResource: sticker.resourceName,
                                     withExtension: sticker.fileExtension),
           let data = try? Data(contentsOf: url) {
            return data
        }
        // Fallback: scan the bundle tree in case resources ever land in a
        // subfolder. Returns nil when the file genuinely isn't there.
        let fileName = "\(sticker.resourceName).\(sticker.fileExtension)"
        guard let enumerator = FileManager.default.enumerator(
            at: Bundle.main.bundleURL,
            includingPropertiesForKeys: nil)
        else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == fileName {
            if let data = try? Data(contentsOf: url) { return data }
        }
        return nil
    }

    static func uiImage(for sticker: Sticker) -> UIImage? {
        guard let data = imageData(for: sticker) else { return nil }
        return UIImage(data: data)
    }
}
