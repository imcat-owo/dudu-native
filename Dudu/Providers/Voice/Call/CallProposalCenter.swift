import Foundation
import UserNotifications

// MARK: - CallProposalCenter
//
// AI-proposed calls + outgoing calls, one @MainActor home.
//
// Consent design (her authorization model — a call is the most intrusive
// proactive act, so it gets the highest bar):
// - The AI may only PROPOSE. It can never auto-start audio or auto-answer.
// - The proposal carries WHO (persona) and WHY (reason) — the consent basis.
// - Ringing = a local notification + an in-app ringing banner if foreground.
// - She taps Accept → the call screen opens and the session starts.
//   She taps Decline (or it times out) → logged as declined/missed and the
//   proposal is NEVER silently retried. A new proposal needs a new decision.
// - Missed-call entries stay visible in the call UI (honest, like a phone).
//
// Ported from ~/workspace/openmuse/apps/mobile/src/voice-call/propose.ts.

@MainActor
final class CallProposalCenter: ObservableObject {

    static let shared = CallProposalCenter()

    /// The currently ringing AI proposal (nil = nothing ringing).
    @Published private(set) var ringingProposal: CallProposal?
    /// The live call session (nil = no active call).
    @Published private(set) var activeSession: VoiceCallSession?
    /// Bumped each time a call ends AND a summary was handed to chat —
    /// the shell overlay uses it to refresh the chat view.
    @Published private(set) var handoffToken = 0
    /// Chat session id the last handoff targeted ("" = none).
    @Published private(set) var handoffSessionId = ""

    private static let storeKey = "dudu.voice-call.v1.proposals"
    private static let maxProposals = 30
    /// A proposal rings this long, then becomes "missed".
    static let ringTimeoutSec: Double = 60

    private let logger = AppLogger(category: "VoiceCall")
    private var ringTasks: [String: Task<Void, Never>] = [:]
    private var activeChatSessionId: String?

    private init() {
        sweepExpired()
    }

    // MARK: - Proposal store (UserDefaults, newest first, capped)

    private func loadProposals() -> [CallProposal] {
        guard let data = UserDefaults.standard.data(forKey: Self.storeKey),
              let list = try? JSONDecoder().decode([CallProposal].self, from: data)
        else { return [] }
        return list
    }

    private func saveProposals(_ list: [CallProposal]) {
        let trimmed = Array(list.prefix(Self.maxProposals))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    func recentProposals() -> [CallProposal] {
        loadProposals()
    }

    // MARK: - Propose (AI only proposes — never auto-starts)

    /// Create a proposal and start ringing. Throws on empty reason —
    /// "call me" with no why is not allowed.
    @discardableResult
    func propose(reason: String, topic: String?, personaId: String, personaName: String) async throws -> CallProposal {
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !why.isEmpty else {
            throw VoiceProviderError.unsupported("A call proposal needs a reason — she decides based on the why.")
        }
        // One ring at a time: a new proposal replaces a stale ringing one
        // (the old one is marked missed — honest, like a phone).
        if let ringing = ringingProposal {
            await setStatus(id: ringing.id, status: .missed)
        }
        let proposal = CallProposal(
            id: UUID().uuidString,
            personaId: personaId,
            personaName: personaName,
            reason: why,
            topic: topic?.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date(),
            status: .ringing)
        var list = loadProposals()
        list.insert(proposal, at: 0)
        saveProposals(list)
        ringingProposal = proposal
        scheduleRingNotification(for: proposal)
        armRingTimeout(for: proposal)
        logger.info("call proposed by \(personaName): \(why.prefix(60))")
        return proposal
    }

    // MARK: - Accept / decline / expire

    /// She accepted → the call may start. Only from "ringing".
    /// Returns the started session, or nil if the proposal is gone.
    func acceptProposal(id: String, entry: ModelEntry?, chatSessionId: String?) async -> VoiceCallSession? {
        guard let proposal = await setStatus(id: id, status: .accepted),
              ringingProposal?.id == id else { return nil }
        // Never stack calls: end any live one first (honest, like a phone).
        if activeSession != nil { await endActiveCall() }
        cancelRingNotification(id: id)
        ringingProposal = nil
        ringTasks[id]?.cancel()
        ringTasks[id] = nil
        let session = VoiceCallSession(personaName: proposal.personaName, entry: entry)
        activeChatSessionId = chatSessionId
        activeSession = session
        await session.start(fromPhase: .ringing)
        return session
    }

    /// She declined → logged, never retried. Terminal: the AI must make a
    /// NEW proposal (new decision) to ring again.
    func declineProposal(id: String) async {
        await setStatus(id: id, status: .declined)
        cancelRingNotification(id: id)
        if ringingProposal?.id == id { ringingProposal = nil }
        ringTasks[id]?.cancel()
        ringTasks[id] = nil
    }

    /// Ring timed out with no answer → "missed" (visible, like a phone).
    func expireProposal(id: String) async {
        let proposal = await setStatus(id: id, status: .missed)
        guard proposal != nil else { return }
        cancelRingNotification(id: id)
        if ringingProposal?.id == id { ringingProposal = nil }
        ringTasks[id]?.cancel()
        ringTasks[id] = nil
        logger.info("call proposal missed (timeout)")
    }

    @discardableResult
    private func setStatus(id: String, status: ProposalStatus) async -> CallProposal? {
        var list = loadProposals()
        guard let i = list.firstIndex(where: { $0.id == id }),
              list[i].status == .ringing else { return nil }
        list[i].status = status
        saveProposals(list)
        return list[i]
    }

    /// Mark stale "ringing" proposals missed on launch.
    private func sweepExpired() {
        var list = loadProposals()
        var changed = false
        let cutoff = Date().addingTimeInterval(-Self.ringTimeoutSec)
        for i in list.indices where list[i].status == .ringing && list[i].createdAt < cutoff {
            list[i].status = .missed
            changed = true
        }
        if changed { saveProposals(list) }
    }

    private func armRingTimeout(for proposal: CallProposal) {
        ringTasks[proposal.id]?.cancel()
        ringTasks[proposal.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.ringTimeoutSec * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.expireProposal(id: proposal.id)
        }
    }

    // MARK: - Outgoing call (she tapped "call")

    /// Start an outgoing call. Returns the session (already connecting).
    func startOutgoingCall(personaName: String, entry: ModelEntry?, chatSessionId: String?) async -> VoiceCallSession {
        // Never stack calls: end any live one first (honest, like a phone).
        if activeSession != nil { await endActiveCall() }
        let session = VoiceCallSession(personaName: personaName, entry: entry)
        activeChatSessionId = chatSessionId
        activeSession = session
        await session.start(fromPhase: .outgoing)
        return session
    }

    /// End the active call and hand its summary to the chat transcript.
    /// No info loss: the full call transcript lands in the chat as one
    /// assistant message — unless the chat is incognito (nothing is
    /// persisted there, by the incognito contract).
    func endActiveCall() async {
        guard let session = activeSession else { return }
        session.end(reason: "user-ended")
        let summary = session.makeSummary()
        let sid = activeChatSessionId
        activeSession = nil
        activeChatSessionId = nil
        guard let summary, let sid, !sid.isEmpty,
              !ChatStore.isEphemeralSessionId(sid) else { return }
        let msg = RawMessage(
            id: UUID().uuidString,
            sessionId: sid,
            role: .assistant,
            parts: [.text(summary)],
            createdAt: Date())
        await ChatStore.shared.appendMessage(msg)
        handoffSessionId = sid
        handoffToken &+= 1
        logger.info("call summary handed to chat sid=\(sid.prefix(8))")
    }

    // MARK: - Ring notification (best-effort; the in-app banner is primary)

    private func ringNotificationId(_ proposalId: String) -> String {
        "dudu-call-ring-\(proposalId)"
    }

    private func scheduleRingNotification(for proposal: CallProposal) {
        let center = UNUserNotificationCenter.current()
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = proposal.personaName
            content.body = proposal.reason
            content.sound = .default
            content.userInfo = ["voiceCallProposalId": proposal.id]
            let req = UNNotificationRequest(
                identifier: ringNotificationId(proposal.id),
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
            try? await center.add(req)
        }
    }

    private func cancelRingNotification(id: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [ringNotificationId(id)])
    }
}
