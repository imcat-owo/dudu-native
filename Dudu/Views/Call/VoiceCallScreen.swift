import SwiftUI

// MARK: - Voice call screen
//
// Full-screen call: connecting → live (turn state, live transcript, live
// mic waveform) → ended. Every button works: mute, WaveformKey hold-to-talk,
// speaker toggle, hang up. No dead buttons.
//
// Copy is the old Dudu's voicecall strings verbatim (zh-Hans), restrained
// and cute — never oily.

struct VoiceCallScreen: View {
    @ObservedObject var session: VoiceCallSession
    /// Hang up / close → the center ends the session and clears it.
    var onClose: () -> Void = {}

    var body: some View {
        Group {
            switch session.phase {
            case .live:
                liveView
            case .ended where session.errorMessage != nil:
                errorView
            default:
                connectingView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DuduTheme.duduBackground)
    }

    // MARK: - Connecting

    private var connectingView: some View {
        VStack(spacing: 12) {
            Spacer()
            avatarView
            Text(session.personaName)
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)
            Text("接通中…")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            ProgressView()
                .padding(.top, 4)
            Spacer()
            endButton(size: 56)
                .padding(.bottom, 40)
        }
    }

    // MARK: - Error (failed to start — never a fake call)

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(session.errorMessage ?? "")
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduDestructive)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                onClose()
            } label: {
                Text("关闭")
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 36)
                    .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous))
            }
            .accessibilityLabel("关闭")
            Spacer()
        }
    }

    // MARK: - Live

    private var liveView: some View {
        VStack(spacing: 0) {
            // Header: who + state + duration.
            VStack(spacing: 5) {
                avatarView
                Text(session.personaName)
                    .font(DuduTheme.titleFont())
                    .foregroundStyle(DuduTheme.duduText)
                Text(turnStatusText)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                Text(durationText)
                    .font(DuduTheme.captionFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .monospacedDigit()
            }
            .padding(.top, 56)

            // Live mic waveform (real metering).
            CallWaveformBars(levelDb: session.levelDb, barCount: 28, color: DuduTheme.pink, barHeight: 36)
                .padding(.top, 18)

            // Live transcript.
            transcriptView
                .padding(.top, 8)

            // Controls: mute · hold-to-talk · speaker · hang up.
            HStack(spacing: 22) {
                controlButton(
                    systemName: session.isMuted ? "mic.slash.fill" : "mic.fill",
                    active: session.isMuted,
                    label: "静音"
                ) {
                    session.setMuted(!session.isMuted)
                }

                VStack(spacing: 4) {
                    WaveformKey(
                        levelDb: session.levelDb,
                        muted: session.isMuted,
                        onHoldBegin: { session.beginPushToTalk() },
                        onHoldEnd: { session.endPushToTalk() }
                    )
                    Text("按住说话")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }

                controlButton(
                    systemName: session.isSpeakerOn ? "speaker.wave.2.fill" : "speaker.fill",
                    active: session.isSpeakerOn,
                    label: session.isSpeakerOn ? "扬声器开" : "扬声器"
                ) {
                    session.setSpeakerOn(!session.isSpeakerOn)
                }

                Button {
                    onClose()
                } label: {
                    DuduIcon(systemName: "phone.down.fill")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduCard)
                        .frame(width: 48, height: 48)
                        .background(DuduTheme.duduDestructive, in: Circle())
                }
                .accessibilityLabel("挂断")
            }
            .padding(.top, 14)
            .padding(.bottom, 36)
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(DuduTheme.duduIconChip)
                .frame(width: 64, height: 64)
            Text(String(session.personaName.prefix(1)))
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)
        }
    }

    private var turnStatusText: String {
        switch session.turnState {
        case .listening: return "在听…"
        case .capturing: return "听到你了…"
        case .thinking: return "想一下…"
        case .speaking: return "说话中…（直接开口就能打断我）"
        }
    }

    private var durationText: String {
        let s = session.durationSec
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Transcript

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    if session.transcript.isEmpty {
                        Text("说话吧，我在听。")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .padding(.top, 24)
                    } else {
                        ForEach(session.transcript) { entry in
                            transcriptBubble(entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .onChange(of: session.transcript.count) { _, _ in
                if let last = session.transcript.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func transcriptBubble(_ entry: CallTranscriptEntry) -> some View {
        let isUser = entry.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(entry.text)
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    isUser ? DuduTheme.duduIconChip : DuduTheme.duduCard,
                    in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous)
                )
            if !isUser { Spacer(minLength: 40) }
        }
    }

    // MARK: - Controls

    private func controlButton(
        systemName: String,
        active: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            DuduIcon(systemName: systemName)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(active ? DuduTheme.duduCard : DuduTheme.duduText)
                .frame(width: 48, height: 48)
                .background(
                    active ? DuduTheme.pink : DuduTheme.duduCard,
                    in: Circle()
                )
        }
        .accessibilityLabel(label)
    }

    private func endButton(size: CGFloat) -> some View {
        Button {
            onClose()
        } label: {
            DuduIcon(systemName: "phone.down.fill")
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduCard)
                .frame(width: size, height: size)
                .background(DuduTheme.duduDestructive, in: Circle())
        }
        .accessibilityLabel("挂断")
    }
}
