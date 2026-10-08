import SwiftUI

// MARK: - D22 · Siri & Shortcuts hub
//
// User-facing Siri/Shortcuts layer for the App Intents engine in
// Dudu/Agent/Intents/. Reachable from Settings → Siri & Shortcuts and via
// `dudu-clone://settings/siri`.
//
// What this screen does:
//   1. Lists every available App Intent (DuduShortcutsCatalog) with a
//      plain-language description, an "opens app / runs in background"
//      badge, and a working "Add to Siri" button per row.
//   2. Shows the seven registered Siri voice phrases so users know what to say.
//   3. Links to the existing ScheduledPromptsView (Dudu/Agent/Intents/) for
//      scheduled prompts — list / enable / disable / delete / add all live
//      there; this hub does not duplicate it.
//
// "Add to Siri" — honest platform note (verified 2026-10-05 against
// research_notes/siri-ai-bidirectional-20261005-0844): there is NO public API
// that lets an app record a Siri voice phrase for an App Intent. The
// SiriKit-era INUIAddVoiceShortcutButton / INUIAddVoiceShortcutViewController
// only accept INShortcut values built from SiriKit INIntents — an App Intent
// cannot be wrapped in one, so that UI cannot be presented here. Since iOS 16
// App Shortcuts install with zero setup: the seven voice shortcuts in
// DuduShortcutsProvider appear in Siri, Spotlight and the Shortcuts app
// automatically, no donation needed. The button therefore does the two things
// an app CAN do: it opens the Shortcuts app, where the user attaches a
// personal phrase to any Dudu action or builds automations around it. The
// explainer card on this screen says exactly this — no dead button, no fake.
//
// Execution-result routing (requirement: no dead ends) — HONEST STATE,
// hand-verified 2026-10-08: NOT fully wired. What exists:
//   - AskDuduIntent / OpenSessionIntent (openAppWhenRun = true): post
//     `.openSessionFromIntent` with the session id, and NotificationNavigationStore
//     has a consume side (SendPromptIntent.swift:401-439) that buffers the
//     completion notifications for the cold-launch path.
// What is MISSING — do not claim this works:
//   - No view currently observes `.openSessionFromIntent` (ContentView has no
//     such observer; the only mentions are comments).
//   - Nothing calls NotificationNavigationStore's consume side.
// So today, tapping a Siri-intent / scheduled-prompt completion notification
// posts into the void and does NOT navigate to the session. The consumer ends
// (ContentView observer, consume-side callers) are DEFERRED to a later phase;
// wiring them is Phase C's territory, not this hub's.

/// Resolves a catalog i18n key through the same bundle AppLocalized uses, so
/// the in-app language override keeps working once it lands. Keys are the
/// English source strings, present in Localizable.xcstrings (en / zh-Hans /
/// zh-Hant). Static screen copy below uses AppLocalized("literal") directly.
private func hubLocalized(_ key: String) -> String {
    NSLocalizedString(key, bundle: AppBundle.current, comment: "")
}

/// The working "Add to Siri" behavior: opens the Shortcuts app. See the file
/// header for why no INUIAddVoiceShortcutButton is presented.
private enum DuduSiriAdder {
    static var shortcutsAppURL: URL? { URL(string: "shortcuts://") }
}

struct SiriShortcutsHubView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalized("Dudu lives in the Shortcuts app too. Seven voice shortcuts work out of the box — just say the phrase and Dudu gets moving."))
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                    Text(AppLocalized("Apple doesn't let apps record their own Siri phrases, so Add to Siri opens the Shortcuts app — give any action a phrase of your own there."))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(DuduShortcutsCatalog.voiceShortcuts) { descriptor in
                    phraseRow(descriptor)
                }
            } header: {
                DuduSectionTitle(AppLocalized("Siri phrases"))
            }

            Section {
                ForEach(DuduShortcutsCatalog.all) { descriptor in
                    actionRow(descriptor)
                }
            } header: {
                DuduSectionTitle(AppLocalized("All actions"))
            }

            Section {
                NavigationLink {
                    ScheduledPromptsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "alarm.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(DuduTheme.pink)
                            .frame(width: 30, height: 30)
                            .background(DuduTheme.pinkSoft)
                            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLocalized("Wake Dudu on a schedule"))
                                .font(DuduTheme.bodyFont(weight: .semibold))
                                .foregroundStyle(DuduTheme.duduText)
                            Text(AppLocalized("A notification at your chosen time — tap it and Dudu runs your preset prompt."))
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                DuduSectionTitle(AppLocalized("On a schedule"))
            }
        }
        .navigationTitle(AppLocalized("Siri & Shortcuts"))
        .navigationBarTitleDisplayMode(.inline)
        .duduCardList()
    }

    // MARK: - Rows

    private func iconChip(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15))
            .foregroundStyle(DuduTheme.pink)
            .frame(width: 30, height: 30)
            .background(DuduTheme.pinkSoft)
            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
    }

    /// One registered Siri voice shortcut with its say-it-like-this phrases.
    private func phraseRow(_ descriptor: DuduShortcutDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                iconChip(descriptor.systemImage)
                Text(hubLocalized(descriptor.titleKey))
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
            }
            Text(hubLocalized("Try saying") + ": " + (descriptor.siriPhrases ?? [])
                .map { "\u{201C}\($0)\u{201D}" }
                .joined(separator: " \u{00B7} "))
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .padding(.leading, 42)
        }
        .padding(.vertical, 4)
    }

    /// One App Intent: description, open-app/background badge, Add to Siri.
    private func actionRow(_ descriptor: DuduShortcutDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                iconChip(descriptor.systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hubLocalized(descriptor.titleKey))
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                    Text(hubLocalized(descriptor.descriptionKey))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                Spacer()
                runModeBadge(opensApp: descriptor.opensApp)
            }
            HStack(alignment: .center) {
                if descriptor.siriPhrases == nil {
                    Text(AppLocalized("Also in the Shortcuts app, under All Actions."))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                Spacer()
                Button {
                    if let url = DuduSiriAdder.shortcutsAppURL {
                        openURL(url)
                    }
                } label: {
                    Label(AppLocalized("Add to Siri"), systemImage: "mic.fill")
                        .font(DuduTheme.captionFont(weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(DuduTheme.pink)
                .accessibilityLabel(AppLocalized("Add to Siri"))
            }
        }
        .padding(.vertical, 4)
    }

    private func runModeBadge(opensApp: Bool) -> some View {
        let key: String.LocalizationValue = opensApp ? "Opens the app" : "Runs in background"
        return Text(AppLocalized(key))
            .font(DuduTheme.captionFont())
            .foregroundStyle(opensApp ? DuduTheme.pink : DuduTheme.duduTextDim)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((opensApp ? DuduTheme.pinkSoft : DuduTheme.duduIconChip).opacity(0.6))
            .clipShape(Capsule())
    }
}
