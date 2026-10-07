import SwiftUI

@main
struct DuduApp: App {
    init() {
        // D20: interactive tools (photo share / doodle / story) read live
        // context per call — set once here. All reads are nonisolated-safe:
        // activeSessionId/activeSessionIsIncognito are nonisolated(unsafe)
        // statics, PersonaStore.currentID() is nonisolated.
        InteractiveTools.contextProvider = {
            InteractiveContext(
                threadId: AIChatViewModel.activeSessionId ?? "",
                personaId: PersonaStore.currentID(),
                incognito: AIChatViewModel.activeSessionIsIncognito
            )
        }
        // D20: self-posts publish into the native Our Space timeline.
        Task { @MainActor in
            SelfPostManager.shared.feedSink = OurSpaceMomentFeedSink()
        }
    }

    var body: some Scene {
        WindowGroup {
            DuduTabView()
        }
    }
}
