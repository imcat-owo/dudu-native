import SwiftUI

// MARK: - D17 · Sticker picker (表情包选择器)
//
// WeChat-style panel: pack tabs on top, sticker grid below — the same
// layout as old Dudu's StickerPanel (apps/mobile/src/sticker/sticker-ui.tsx).
// Tapping a sticker inserts it into the chat draft as an image attachment
// via the existing attachment pipeline
// (AIChatViewModel.addImageAttachment(data:fileExtension:)): the sticker
// lands in the attachment strip and she sends it like any photo — nothing
// sends on its own. Every control is wired; there is deliberately no
// pack-manager UI yet (future work builds on the extensible StickerPack).
struct StickerPickerView: View {
    @EnvironmentObject private var vm: AIChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var activePackId: String = StickerStore.builtInPackId
    @State private var failedLoads: Set<String> = []

    private var activePack: StickerPack {
        StickerStore.packs.first(where: { $0.id == activePackId })
            ?? StickerStore.builtInPack
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pack tabs (built-in pack first; future her-packs slot in behind).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(StickerStore.packs) { pack in
                        let selected = pack.id == activePackId
                        Button {
                            activePackId = pack.id
                        } label: {
                            Text(pack.name)
                                .font(selected
                                      ? DuduTheme.bodyFont(weight: .semibold)
                                      : DuduTheme.bodyFont())
                                .foregroundStyle(selected
                                                 ? DuduTheme.brandBrown
                                                 : DuduTheme.duduTextDim)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selected ? DuduTheme.pink : DuduTheme.duduIconChip,
                                    in: Capsule()
                                )
                        }
                        .accessibilityLabel("表情包分组：\(pack.name)")
                    }
                }
                .padding(.horizontal, DuduTheme.pagePadding)
                .padding(.vertical, 8)
            }

            Divider()
                .background(DuduTheme.duduDivider)

            // Sticker grid.
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 84), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(activePack.stickers) { sticker in
                        stickerCell(sticker)
                    }
                }
                .padding(12)
            }
        }
        .background(DuduTheme.duduBackground)
    }

    private func stickerCell(_ sticker: Sticker) -> some View {
        Button {
            pick(sticker)
        } label: {
            Group {
                if failedLoads.contains(sticker.id) {
                    Text("加载失败")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                } else if let uiImage = StickerStore.uiImage(for: sticker) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    // Bundled reads are synchronous: nil here means the
                    // resource is genuinely missing, not still loading.
                    Text("加载失败")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
            .frame(minWidth: 84, minHeight: 84)
            .padding(6)
            .background(
                DuduTheme.duduCard,
                in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous)
            )
        }
        .accessibilityLabel("插入表情：\(sticker.name)")
    }

    /// Insert the sticker into the draft as an image attachment through the
    /// existing pipeline, then dismiss. Send stays in her control.
    private func pick(_ sticker: Sticker) {
        guard let data = StickerStore.imageData(for: sticker) else {
            failedLoads.insert(sticker.id)
            ShareFeedbackToast.show("表情加载失败")
            return
        }
        vm.addImageAttachment(data: data, fileExtension: sticker.fileExtension)
        dismiss()
    }
}
