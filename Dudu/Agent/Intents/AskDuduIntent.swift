//  P7 PORT (2026-10-07): ported from OpenMinis Agent/Intents/AskMinisIntent.swift — renames Minis->Dudu
//  (incl. mid-identifier; English words like deterministic/administrative untouched),
//  com.openminis.clone->com.dudu.ios, group ids, minis->dudu prefixes
//  (minis-clone://->dudu-clone://, minis-browser-use->dudu-browser-use,
//  /var/minis/->/var/dudu/, MINIS_SESSION_ID->DUDU_SESSION_ID);
//  iCloud container id renamed (entitlement dropped); OpenMinis#NNN issue refs
//  and github.com/OpenMinis URLs kept (upstream project).
//

import AppIntents
import Foundation

private let logger = AppLogger(category: "AskDuduIntent")

/// Siri-facing "ask Dudu" entry point. Unlike `SendPromptIntent` (which runs
/// headless with `openAppWhenRun = false` for Shortcuts automations), this
/// intent OPENS the app and routes to the session so the user lands in the live
/// conversation — matching the "Hey Siri, ask Dudu to …" experience.
///
/// It reuses the exact normal send pipeline (`AIChatViewModel.send()`) and the
/// existing `.openSessionFromIntent` navigation path — no separate agent logic.
/// New session when `session` is nil; follow-up when a `SessionEntity` is given.
struct AskDuduIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask 我的小家"
    static var description = IntentDescription("Opens 我的小家, sends your prompt, and shows the conversation. Starts a new session, or continues an existing one when you pick a session.")

    // Open the app and land in the conversation (the Siri experience). The send
    // itself still goes through the normal in-app pipeline.
    static var openAppWhenRun = true

    @Parameter(title: "Prompt", requestValueDialog: "What would you like to ask 我的小家?")
    var prompt: String

    @Parameter(title: "Session", description: "Existing session to continue. Leave empty to start a new session.")
    var session: SessionEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Same eager keep-alive discipline as SendPromptIntent: arm before any
        // await so an intent-woken process isn't suspended before the send path
        // flips isActive. No-op unless enhancedBackgroundEffective is on.
        BackgroundKeepAliveManager.shared.setup()
        let placeholderSid: String? = (session == nil) ? "intent-eager:\(UUID().uuidString)" : nil
        let eagerInitialSid = session?.id ?? placeholderSid ?? ""
        var eagerArmed = false
        if !eagerInitialSid.isEmpty {
            eagerArmed = BackgroundKeepAliveManager.shared.armEagerlyForShortcut(
                sessionId: eagerInitialSid, caller: "AskDuduIntent").armed
        }
        defer {
            if let placeholder = placeholderSid, eagerArmed {
                SessionActivityTracker.shared.setInactive(placeholder,
                    source: "AskDuduIntent.eager.cleanupDefer")
            }
        }

        // Resolve / create the target VM through the shared cache — identical to
        // SendPromptIntent so both paths converge on one send pipeline.
        let vm: AIChatViewModel
        if let session = session {
            let (cached, _) = ViewModelCache.shared.getOrCreate(for: session.id)
            vm = cached
            await vm.loadSession()
        } else {
            vm = ViewModelCache.shared.createDraft()
            vm.sessionSource = "siri"
            await vm.ensureSessionReturningId()
            if let placeholder = placeholderSid, let realSid = vm.sessionId {
                BackgroundKeepAliveManager.shared.armEagerlyForShortcut(
                    sessionId: realSid, caller: "AskDuduIntent.swap")
                SessionActivityTracker.shared.setInactive(placeholder,
                    source: "AskDuduIntent.eager.placeholderSwap")
            }
        }

        // If the session is mid-run, let it settle before appending (mirrors
        // FollowUpSessionIntent) so we don't send into an in-flight turn.
        if vm.isProcessing {
            for await processing in vm.$isProcessing.values where !processing { break }
        }

        vm.inputText = prompt
        vm.send()

        let sid = vm.sessionId ?? session?.id ?? ""
        logger.info("AskDudu send sid=\(sid.prefix(8)) new=\(session == nil)")

        // Route the (now-open) app to this session. Same event ContentView and
        // the cold-launch buffer already consume for notification taps / deep
        // links — no new navigation surface.
        if !sid.isEmpty {
            NotificationNavigationStore.shared.setPending(sid)
            NotificationCenter.default.post(
                name: .openSessionFromIntent,
                object: nil,
                userInfo: ["sessionId": sid]
            )
        }

        return .result(dialog: "On it — opening 我的小家.")
    }
}
