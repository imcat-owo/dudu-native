import SwiftUI

// MARK: - VoiceCallOverlay
//
// Rides above every tab (mounted in DuduTabView):
// - ringing banner (top): WHO + WHY — the consent basis — with 接听/挂断.
// - missed banner: a ring that timed out, transient, like a phone.
// - full-screen call: presented while a session is active.
// - handoff: after a call ends, refresh the chat so the call summary appears.
//
// Copy is the old Dudu's voicecall strings verbatim (zh-Hans).

struct VoiceCallOverlay: View {
    @EnvironmentObject private var vm: AIChatViewModel
    @StateObject private var center = CallProposalCenter.shared

    /// A ring that just timed out → show it briefly as missed.
    @State private var missedFlash: CallProposal?
    @State private var lastRingId: String?

    /// fullScreenCover binding driven by the center's active session.
    private var callPresented: Binding<Bool> {
        Binding(
            get: { center.activeSession != nil },
            set: { if !$0 { Task { @MainActor in await center.endActiveCall() } } }
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let proposal = center.ringingProposal {
                RingBanner(
                    proposal: proposal,
                    onAccept: {
                        Task { @MainActor in
                            await center.acceptProposal(
                                id: proposal.id,
                                entry: vm.resolveCurrentEntry(),
                                chatSessionId: vm.sessionId)
                        }
                    },
                    onDecline: {
                        Task { @MainActor in
                            await center.declineProposal(id: proposal.id)
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let missed = missedFlash {
                MissedBanner(proposal: missed) {
                    missedFlash = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: center.ringingProposal?.id)
        .fullScreenCover(isPresented: callPresented) {
            if let session = center.activeSession {
                VoiceCallScreen(session: session) {
                    Task { @MainActor in await center.endActiveCall() }
                }
            }
        }
        // Ring → gone with no accepted call = missed (timed out or declined
        // elsewhere): flash it briefly, like a phone's missed call.
        .onChange(of: center.ringingProposal?.id) { _, newId in
            if let old = lastRingId, newId == nil, center.activeSession == nil {
                if let p = CallProposalCenter.shared.recentProposals().first(where: { $0.id == old }),
                   p.status == .missed {
                    missedFlash = p
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        if missedFlash?.id == old { missedFlash = nil }
                    }
                }
            }
            lastRingId = newId
        }
        // Call summary landed in the chat store → refresh the visible chat.
        .onChange(of: center.handoffToken) { _, _ in
            let sid = center.handoffSessionId
            guard !sid.isEmpty, vm.sessionId == sid else { return }
            Task { @MainActor in
                await vm.reloadMessagesFromDB(reason: "voice-call-handoff")
            }
        }
    }
}

// MARK: - Ringing banner

private struct RingBanner: View {
    var proposal: CallProposal
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("来电")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            Text(proposal.personaName)
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)
            Text(proposal.reason)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
                .lineLimit(2)
            if let topic = proposal.topic, !topic.isEmpty {
                Text(topic)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                Button(action: onDecline) {
                    Text("挂断")
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(DuduTheme.duduIconChip, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous))
                }
                .accessibilityLabel("挂断")
                Button(action: onAccept) {
                    Text("接听")
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduCard)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(DuduTheme.pink, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous))
                }
                .accessibilityLabel("接听")
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DuduTheme.radiusCard, style: .continuous)
                .stroke(DuduTheme.duduDivider, lineWidth: 1)
        )
        .shadow(color: DuduTheme.duduTextDim.opacity(0.25), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Missed banner (transient)

private struct MissedBanner: View {
    var proposal: CallProposal
    var onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 8) {
                Image(systemName: "phone.down.fill")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduDestructive)
                VStack(alignment: .leading, spacing: 2) {
                    Text("未接来电")
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                    Text(proposal.reason)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(12)
            .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DuduTheme.radiusCard, style: .continuous)
                    .stroke(DuduTheme.duduDivider, lineWidth: 1)
            )
            .shadow(color: DuduTheme.duduTextDim.opacity(0.2), radius: 10, y: 3)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityLabel("未接来电，点击关闭")
    }
}
