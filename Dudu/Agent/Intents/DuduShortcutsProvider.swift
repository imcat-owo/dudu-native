//  P7 PORT (2026-10-07): ported from OpenMinis Agent/Intents/MinisShortcutsProvider.swift — renames Minis->Dudu
//  (incl. mid-identifier; English words like deterministic/administrative untouched),
//  com.openminis.clone->com.dudu.ios, group ids, minis->dudu prefixes
//  (minis-clone://->dudu-clone://, minis-browser-use->dudu-browser-use,
//  /var/minis/->/var/dudu/, MINIS_SESSION_ID->DUDU_SESSION_ID);
//  iCloud container id renamed (entitlement dropped); OpenMinis#NNN issue refs
//  and github.com/OpenMinis URLs kept (upstream project).
//

import AppIntents

/// Registers app shortcuts so they appear in Shortcuts with zero user setup.
///
/// Phrase localization: Chinese Siri trigger phrases are registered DIRECTLY
/// in the `phrases:` arrays below (plain strings, no `\(.applicationName)`
/// token — she says "小梦"/"嘟嘟" by name). Siri matches the phrases in the
/// device's current language, so Chinese Siri on a Chinese-locale device
/// picks these up with zero extra .strings tables. English phrases are kept
/// as-is; DuduShortcutsCatalog.siriPhrases must stay verbatim-identical to
/// the resolved list here (see that file's SYNC RULE).
@available(iOS 17.0, *)
struct DuduShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Siri-facing "ask Dudu" entry — opens the app and lands in the
        // conversation. Note: iOS App Intents cannot capture free-form trailing
        // text from the phrase itself (e.g. "…the weather today"); Siri collects
        // the prompt via the parameter's requestValueDialog follow-up. The
        // phrases below are the invocation triggers, not the prompt.
        AppShortcut(
            intent: AskDuduIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question",
                "Talk to \(.applicationName)",
                "New \(.applicationName) chat",
                "和小梦聊天",
                "问问小梦",
                "打开嘟嘟",
            ],
            shortTitle: "Ask 我的小家",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: QuickTaskIntent(),
            phrases: [
                "Run a \(.applicationName) quick task",
                "Use \(.applicationName) quick task",
                "小梦帮我查一下",
                "嘟嘟快捷任务",
            ],
            shortTitle: "Quick Task",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: SendPromptIntent(),
            phrases: [
                "Send a prompt to \(.applicationName)",
                "Ask \(.applicationName) something",
                "Start a \(.applicationName) task",
                "给小梦发个任务",
                "让嘟嘟在后台干活",
            ],
            shortTitle: "Send Prompt",
            systemImageName: "message.fill"
        )
        AppShortcut(
            intent: GetSessionStatusIntent(),
            phrases: [
                "Get \(.applicationName) session status",
                "Check \(.applicationName) task",
                "小梦干到哪了",
                "看看小梦在忙什么",
            ],
            shortTitle: "Session Status",
            systemImageName: "info.circle.fill"
        )
        AppShortcut(
            intent: ListSessionsIntent(),
            phrases: [
                "List \(.applicationName) sessions",
                "Show \(.applicationName) chats",
                "看看和小梦的聊天记录",
                "嘟嘟的聊天列表",
            ],
            shortTitle: "List Sessions",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: FollowUpSessionIntent(),
            phrases: [
                "Follow up a \(.applicationName) session",
                "Continue a \(.applicationName) session",
                "继续跟小梦聊",
                "接着上次跟小梦说",
            ],
            shortTitle: "Follow Up",
            systemImageName: "arrowshape.turn.up.left.fill"
        )
        // RetryRunIntent is not registered here because its
        // @IntentParameterDependency causes an iOS 16 launch crash
        // (Swift metadata resolution). It remains available in Shortcuts
        // via the "All Actions" list.
        AppShortcut(
            intent: OpenSessionIntent(),
            phrases: [
                "Open a \(.applicationName) session",
                "打开跟小梦的聊天",
                "打开嘟嘟会话",
            ],
            shortTitle: "Open Session",
            systemImageName: "arrow.up.right.square"
        )
        // [T-ios-remove-open-webapp-shortcut-intent] OpenWebAppIntent removed —
        // the Home-Screen WebApp tile path was replaced by another mechanism,
        // so the Shortcuts/AppIntents action is no longer registered.
    }
}
