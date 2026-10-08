import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Phase C2 — the message composer.
///
/// Wave 2 Item 5 (html-2 定稿): the composer is a FLOATING GLASS CAPSULE —
/// 22pt corner radius, iOS native Liquid Glass
/// (`.glassEffect`, `.ultraThinMaterial` fallback on older toolchains),
/// soft shadow (DuduTheme.capsuleShadow), 12pt side margins. It rides in
/// ChatView's bottom safe-area inset: 8pt above the floating tab bar
/// (59pt bar + 10pt margin), i.e. 77pt clearance, and the keyboard pushes
/// it up automatically via the safe-area inset.
///
/// - Multiline TextField bound to vm.inputText (grows to 5 lines).
/// - Pink send button, disabled while the draft is empty; while the AI is
///   busy it stays live next to a stop button (vm.cancel()) — send queues a
///   follow-up via vm.send(), stop ends the current turn AND clears the queue.
/// - The input is NEVER locked while processing: she can send follow-ups
///   anytime (the engine queues them; a badge shows how many are queued).
/// - Photo attach button → PhotosPicker → vm.addImageAttachment (real).
/// - File attach button (paperclip) → UIDocumentPickerViewController →
///   vm.addFileAttachment (real); document chips show the filename and can
///   be removed; on send the file reaches the AI via the existing
///   processAttachments() <user-attached-files> block.
/// - Sticker button → StickerPickerView sheet → tap inserts the sticker into
///   the draft as an image attachment via vm.addImageAttachment (real,
///   bundled mascot art); she still presses send herself.
/// - Mic button → SpeechRecognitionManager (SFSpeechRecognizer) — live
///   transcript lands in the input field (Phase D1).
struct ChatInputBar: View {
    @EnvironmentObject private var vm: AIChatViewModel
    @StateObject private var stt = SpeechRecognitionManager.shared

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showStickerPicker = false
    @State private var showFilePicker = false
    @State private var recordStart: Date? = nil

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
                Text(L10n.format("chat.queued.followups", vm.queuedFollowUpCount))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .accessibilityLabel("\(vm.queuedFollowUpCount) 条消息排队中")
            }
            if let notice = vm.queueClearedNotice {
                Text(notice)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }

            // [D1-stt] Live recording panel while the speech engine runs:
            // elapsed time, audio levels, live transcript, stop hint.
            if stt.state == .recording {
                recordingPanel
            }

            // Wave 2 Item 5 — floating glass capsule (html-2 定稿): the
            // composer row is the capsule. Native Liquid Glass, 22pt
            // radius, soft shadow. The attachment strip, queue badge and
            // recording panel stay above it, outside the glass.
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    DuduIcon(systemName: "photo")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("添加图片")

                // [D17-stickers] Sticker button: opens the sticker picker
                // sheet; a tap there inserts the sticker into the draft as
                // an image attachment via vm.addImageAttachment — the same
                // pipeline the photo button uses.
                Button {
                    showStickerPicker = true
                } label: {
                    DuduIcon(systemName: "face.smiling")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("表情包")

                // [D1-stt] Mic: tap to record (SFSpeechRecognizer), tap again
                // to stop — the transcript lands in the input field.
                Button {
                    toggleRecording()
                } label: {
                    DuduIcon(systemName: stt.state == .recording ? "mic.fill" : "mic")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(stt.state == .recording ? DuduTheme.pink : DuduTheme.duduTextDim)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(stt.state == .recording ? "停止录音" : "语音输入")

                // [Wave3-P1-file-picker] File attach: opens the iOS document
                // picker; picked files land in vm.attachments as document
                // chips (filename shown, removable) via the existing
                // addFileAttachment pipeline — Kelivo/Claude Code/OpenMinis
                // parity.
                Button {
                    showFilePicker = true
                } label: {
                    DuduIcon(systemName: "paperclip")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("添加文件")

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
                        DuduIcon(systemName: "stop.fill")
                            .font(DuduTheme.bodyFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduText)
                            .frame(width: 32, height: 32)
                            .background(DuduTheme.pink, in: Circle())
                    }
                    .accessibilityLabel("停止生成")

                    Button {
                        vm.send()
                    } label: {
                        DuduIcon(systemName: "arrow.up")
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
                        DuduIcon(systemName: "arrow.up")
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
            .floatingBarGlass(cornerRadius: DuduTheme.radiusCard)
            .shadow(color: DuduTheme.capsuleShadow, radius: 35, x: 0, y: 12)
        }
        .padding(.horizontal, 12)
        // [D17-stickers] Sticker picker sheet. StickerPickerView reads
        // vm (AIChatViewModel) from the environment, inherited through the
        // sheet like the rest of this view hierarchy.
        .sheet(isPresented: $showStickerPicker) {
            StickerPickerView()
        }
        // [Wave3-P1-file-picker] Document picker sheet. The picked URLs go
        // straight into vm.addFileAttachment (Caches staging + kind
        // classification); document chips appear in the attachment strip
        // above, and processAttachments() includes them on send.
        .sheet(isPresented: $showFilePicker) {
            ChatDocumentPicker { urls in
                for url in urls {
                    vm.addFileAttachment(from: url)
                }
            }
        }
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

    // MARK: - File picker (Wave 3 P1)

    /// Filename chip for a document attachment: doc glyph + name, Q萌 solid
    /// style, DuduTheme colors only.
    private func documentChip(_ fileName: String) -> some View {
        HStack(spacing: 6) {
            DuduIcon(systemName: "doc")
                .font(DuduTheme.bodyFont())
            Text(fileName)
                .font(DuduTheme.captionFont())
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(DuduTheme.duduTextDim)
        .padding(.horizontal, 10)
        .frame(maxWidth: 220, maxHeight: 56, alignment: .leading)
    }

    // MARK: - STT recording (Phase D1)

    /// Mic tap handler. Starts SFSpeechRecognizer capture (after the system
    /// permission prompts) or stops an in-flight recording and drops the
    /// transcript into the input field.
    private func toggleRecording() {
        if stt.state == .recording {
            finishRecording()
            return
        }
        Task { @MainActor in
            guard await stt.requestPermissions() else {
                ShareFeedbackToast.show("需要麦克风和语音识别权限")
                return
            }
            do {
                try stt.startRecording()
                SpeechRecognitionManager.saveInputModePreference("voice")
                recordStart = Date()
            } catch {
                ShareFeedbackToast.show("录音启动失败")
            }
        }
    }

    /// Stop capture; append the final transcript to the draft.
    private func finishRecording() {
        stt.stopRecording()
        recordStart = nil
        let text = stt.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            vm.inputText = text
        } else {
            vm.inputText += "\n" + text
        }
        stt.recognizedText = ""
    }

    /// Live panel above the input row while recording: pulsing dot,
    /// elapsed time, audio level bars, live transcript, stop hint.
    private var recordingPanel: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(DuduTheme.pink)
                .frame(width: 8, height: 8)
                .opacity(recordPulse ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                           value: recordPulse)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsedString(since: recordStart ?? context.date, at: context.date))
                    .font(DuduTheme.captionFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .monospacedDigit()
            }

            // Audio level bars from the engine's live RMS meter.
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<min(24, stt.audioLevels.count), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DuduTheme.pink)
                        .frame(width: 3, height: 2 + CGFloat(stt.audioLevels[i]) * 22)
                }
            }
            .frame(height: 24)

            if !stt.recognizedText.isEmpty {
                Text(stt.recognizedText)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Text(L10n.string("chat.inputBar.tapAgainToStop"))
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DuduTheme.duduIconChip, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous))
        .onAppear { recordPulse = true }
    }

    @State private var recordPulse = false

    private func elapsedString(since start: Date, at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
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
                        DuduIcon(systemName: "exclamationmark.triangle")
                            .font(DuduTheme.captionFont())
                        Text(L10n.string("chat.inputBar.loadFailed"))
                            .font(DuduTheme.captionFont())
                    }
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .frame(width: 56, height: 56)
                case .ready:
                    // [Wave3-P1-file-picker] Document chips show the filename
                    // so the user can tell attached files apart; the same
                    // remove button handles dismissal.
                    if attachment.kind == .document {
                        documentChip(attachment.fileName)
                    } else if let uiImage = UIImage(contentsOfFile: attachment.cacheURL.path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipped()
                    } else {
                        DuduIcon(systemName: "doc")
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
                DuduIcon(systemName: "xmark.circle.fill")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .background(DuduTheme.duduCard, in: Circle())
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel("移除附件")
        }
    }
}

// MARK: - File picker (Wave 3 P1)

/// UIDocumentPickerViewController wrapper for attaching arbitrary files to
/// the chat draft. `forOpeningContentTypes: [.data]` covers every file type;
/// multiple selection is on. `addFileAttachment(from:)` sniffs images/videos
/// (extension / UTType / magic bytes) so media picked from Files still gets
/// the visual chip; everything else becomes a document chip with the filename.
private struct ChatDocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
