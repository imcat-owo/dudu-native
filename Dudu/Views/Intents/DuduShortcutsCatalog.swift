import Foundation

// MARK: - D22 · Siri / Shortcuts user-facing catalog
//
// The App Intents engine lives in Dudu/Agent/Intents/ (AskDuduIntent,
// QuickTaskIntent, SendPromptIntent, GetSessionStatusIntent,
// ListSessionsIntent, FollowUpSessionIntent, OpenSessionIntent,
// RetryRunIntent). This catalog is the USER-FACING layer rendered by
// SiriShortcutsHubView: plain-language titles and descriptions in Dudu's
// copy tone (zero emoji), SF symbols, whether each action opens the app or
// runs in the background (mirrors the intent's `openAppWhenRun`), and the
// Siri voice phrases registered in DuduShortcutsProvider.
//
// SYNC RULE: `siriPhrases` must stay verbatim-identical to the phrases in
// DuduShortcutsProvider.appShortcuts. When the engine adds/removes/renames a
// phrase, update the matching entry here in the same commit.
// `nil` phrases = the intent has no App Shortcut voice phrase; it is still
// available in the Shortcuts app under "All Actions" (e.g. RetryRunIntent).

/// User-facing description of one Dudu App Intent for the Siri & Shortcuts hub.
struct DuduShortcutDescriptor: Identifiable {
    /// Stable id, e.g. "ask". Never shown to the user.
    let id: String
    /// i18n key (the English source string) for the display title.
    /// Present in Localizable.xcstrings (en / zh-Hans / zh-Hant).
    let titleKey: String
    /// i18n key (the English source string) for the plain-language description.
    let descriptionKey: String
    /// SF Symbol rendered in the row's icon chip.
    let systemImage: String
    /// Mirrors the intent's `openAppWhenRun`. true = the action opens Dudu and
    /// lands in the conversation; false = it runs headless in the background.
    let opensApp: Bool
    /// Voice phrases from DuduShortcutsProvider, quoted verbatim for display.
    let siriPhrases: [String]?
}

/// The eight App Intents in Dudu/Agent/Intents/, in hub display order.
enum DuduShortcutsCatalog {
    static let all: [DuduShortcutDescriptor] = [
        DuduShortcutDescriptor(
            id: "ask",
            titleKey: "Ask Dudu",
            descriptionKey: "Talk to Dudu out loud — she opens the chat, sends your words, and answers right in front of you.",
            systemImage: "sparkles",
            opensApp: true,
            siriPhrases: ["Ask Dudu", "Ask Dudu a question", "Talk to Dudu", "New Dudu chat"]
        ),
        DuduShortcutDescriptor(
            id: "quicktask",
            titleKey: "Quick Task",
            descriptionKey: "Little everyday jobs — sleep check, weather, morning briefing. Pick one and Dudu handles it.",
            systemImage: "bolt.fill",
            opensApp: false,
            siriPhrases: ["Run a Dudu quick task", "Use Dudu quick task"]
        ),
        DuduShortcutDescriptor(
            id: "sendprompt",
            titleKey: "Send Prompt",
            descriptionKey: "Slip Dudu a task in the background — she keeps working while you do other things.",
            systemImage: "paperplane.fill",
            opensApp: false,
            siriPhrases: ["Send a prompt to Dudu", "Ask Dudu something", "Start a Dudu task"]
        ),
        DuduShortcutDescriptor(
            id: "sessionstatus",
            titleKey: "Session Status",
            descriptionKey: "Peek at a running task — see what Dudu is up to and what she just said.",
            systemImage: "info.circle.fill",
            opensApp: false,
            siriPhrases: ["Get Dudu session status", "Check Dudu task"]
        ),
        DuduShortcutDescriptor(
            id: "listsessions",
            titleKey: "List Sessions",
            descriptionKey: "All your chats with Dudu, in one tidy list.",
            systemImage: "list.bullet",
            opensApp: false,
            siriPhrases: ["List Dudu sessions", "Show Dudu chats"]
        ),
        DuduShortcutDescriptor(
            id: "followup",
            titleKey: "Follow Up",
            descriptionKey: "Wake an old conversation with one more question — Dudu picks up right where you left off.",
            systemImage: "arrowshape.turn.up.left.fill",
            opensApp: false,
            siriPhrases: ["Follow up a Dudu session", "Continue a Dudu session"]
        ),
        DuduShortcutDescriptor(
            id: "opensession",
            titleKey: "Open Session",
            descriptionKey: "Jump straight into a chat — no scrolling through the list.",
            systemImage: "arrow.up.right.square",
            opensApp: true,
            siriPhrases: ["Open a Dudu session"]
        ),
        DuduShortcutDescriptor(
            id: "retryrun",
            titleKey: "Retry Run",
            descriptionKey: "Dudu went sideways? Rewind to any of your messages and let her try that turn again.",
            systemImage: "arrow.counterclockwise",
            opensApp: false,
            siriPhrases: nil
        ),
    ]

    /// Only the intents that carry a registered Siri voice phrase.
    static var voiceShortcuts: [DuduShortcutDescriptor] {
        all.filter { $0.siriPhrases != nil }
    }
}
