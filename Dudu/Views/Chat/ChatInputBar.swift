import PhotosUI
import SwiftUI
import UIKit

/// Phase C2 — the message composer.
///
/// - Multiline TextField bound to vm.inputText (grows to 5 lines).
/// - Pink send button, disabled while the draft is empty; while the AI is
///   busy it stays live next to a stop button (vm.cancel()) — send queues a
///   follow-up via vm.send(), stop ends the current turn AND clears the queue.
/// - The input is NEVER locked while processing: she can send follow-ups
///   anytime (the engine queues them; a badge shows how many are queued).
/// - Photo attach button → PhotosPicker → vm.addImageAttachment (real).
/// - No voice button: STT UI is a Phase-D surface (plan §8), and dead
///   buttons are not shipped.
struct ChatInputBar: View {
    @EnvironmentObject private var vm: AIChatViewModel

    @State private var selectedPhoto: PhotosPickerItem?

    private var canSend: Bool {
        !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !vm.attachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            if !vm.attachments.isEmpty {
                attachmentStrip
            }

            // [C2-followup-queue] Queue status above the input: how many
            // follow-ups are queued, or what a Stop just cleared.
            if vm.queuedFollowUpCount > 0 {
                Text("\(vm.queuedFollowUpCount) 条排队中")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .accessibilityLabel("\(vm.queuedFollowUpCount) 条消息排队中")
            }
            if let notice = vm.queueClearedNotice {
                Text(notice)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("添加图片")

                TextField("输入消息", text: $vm.inputText, axis: .vertical)
                    .font(DuduTheme.inputFont())
                    .foregroundStyle(DuduTheme.duduText)
                    .lineLimit(1...5)
                    .padding(.vertical, 8)

                // [C2-followup-queue] While the AI is busy BOTH buttons stay
                // live: stop ends the current turn (and clears any queued
                // follow-ups — Stop = stop everything), send queues a
                // follow-up via vm.send() which never drops. The input is
                // never locked.
                if vm.isProcessing {
                    Button {
                        vm.cancel()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(DuduTheme.bodyFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduText)
                            .frame(width: 32, height: 32)
                            .background(DuduTheme.pink, in: Circle())
                    }
                    .accessibilityLabel("停止生成")

                    Button {
                        vm.send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(DuduTheme.bodyFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduText)
                            .frame(width: 32, height: 32)
                            .background(DuduTheme.pink, in: Circle())
                            .opacity(canSend ? 1 : 0.4)
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("发送，AI 忙时排队")
                } else {
                    Button {
                        vm.send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(DuduTheme.bodyFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduText)
                            .frame(width: 32, height: 32)
                            .background(DuduTheme.pink, in: Circle())
                            .opacity(canSend ? 1 : 0.4)
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("发送")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                DuduTheme.duduCard,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .padding(.horizontal, DuduTheme.pagePadding)
        .padding(.vertical, 10)
        // iOS system material only — no custom blur overlays.
        .background(.ultraThinMaterial)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            selectedPhoto = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                await MainActor.run {
                    vm.addImageAttachment(data: data, fileExtension: ext)
                }
            }
        }
    }

    // MARK: - Attachment strip

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.attachments) { attachment in
                    attachmentChip(attachment)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func attachmentChip(_ attachment: InputAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch attachment.loadState {
                case .loading:
                    ProgressView()
                        .frame(width: 56, height: 56)
                case .failed:
                    VStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(DuduTheme.captionFont())
                        Text("加载失败")
                            .font(DuduTheme.captionFont())
                    }
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .frame(width: 56, height: 56)
                case .ready:
                    if let uiImage = UIImage(contentsOfFile: attachment.cacheURL.path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipped()
                    } else {
                        Image(systemName: "doc")
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .frame(width: 56, height: 56)
                    }
                }
            }
            .background(
                DuduTheme.duduIconChip,
                in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous))

            Button {
                vm.removeAttachment(attachment)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .background(DuduTheme.duduCard, in: Circle())
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel("移除附件")
        }
    }
}
