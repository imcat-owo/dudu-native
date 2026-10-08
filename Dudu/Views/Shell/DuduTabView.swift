import SwiftUI

/// Root view of the app (Phase C shell). Owns the engine singletons as
/// @StateObject, injects them into the environment, and routes the
/// Phase-C deep-link destinations from DeepLinkCoordinator.
///
/// Wave 2 Item 2: the iOS system TabView is replaced by a custom floating
/// glass tab bar (DuduTabBar, html-2 定稿) — 59pt high, 22pt corner
/// radius, 12pt side margins, 10pt above the safe area. Tab content
/// crossfades with a subtle spring; per-tab state (scroll position, chat
/// input) is preserved because all four tabs stay alive.
struct DuduTabView: View {
    @State private var selection: DuduTab = .chat

    // Engine singletons — owned here, shared with the whole shell.
    @StateObject private var chatViewModel = AIChatViewModel()
    @StateObject private var providerStore = ProviderConfigStore.shared
    @StateObject private var appearance = AppearanceStudio.shared
    @ObservedObject private var deepLinks = DeepLinkCoordinator.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            tabLayer(.ourSpace) { OurSpaceView() }
            tabLayer(.chat) { ChatView(selection: $selection) }
            tabLayer(.library) { LibraryView() }
            tabLayer(.more) { SettingsView() }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selection)
        // The floating bar lives in the bottom safe-area inset so content
        // scrolls clear of it and it always sits 10pt above the home
        // indicator, with 12pt side margins.
        .safeAreaInset(edge: .bottom) {
            DuduTabBar(selection: $selection)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .environmentObject(chatViewModel)
        .environmentObject(providerStore)
        .environmentObject(appearance)
        .onReceive(deepLinks.$pendingSettingsTarget) { target in
            guard target != nil else { return }
            // Phase C destinations (providers / providerDetail / appearance)
            // land on the More tab (raw value "settings" is preserved, so
            // existing deep links keep working). The step-6 Settings builder
            // consumes pendingSettingsTarget for the actual push; the value
            // stays published for it.
            selection = .more
        }
        .appFontScale()
        // Theme tokens now read AppearanceStudio live (Wave 3): when the user
        // toggles system appearance, force a re-render so the new variant
        // resolves. (The old adaptive() UIColor providers did this at UIKit
        // render time; the studio path needs an explicit invalidation.)
        .onChange(of: colorScheme) { _ in
            appearance.objectWillChange.send()
        }
        // D11: app-level Face ID lock — overlay + foreground/background
        // evaluation live in AppLockGate (Views/Settings/AppLockView.swift).
        .modifier(AppLockGate())
        // Phase D3: tool-approval card floats above everything (overlay, not a
        // sheet) so chat stays interactive while a request is pending.
        // D9: AI authorization prompt rides the same overlay; it only renders
        // when OffloadPermissionManager.pendingRequest is non-nil.
        // D12: ThemeTryOnBanner rides here too — try-on previews staged by
        // the AI (preview_theme) or theme-pack import must be visible from
        // chat, with Save/Discard always one tap away.
        // The banners are lifted 77pt (59pt bar + 10pt margin + 8pt gap) so
        // they float above the tab bar instead of hiding behind it.
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                ThemeTryOnBanner()
                AIAuthorizationPromptView()
                MCPApprovalCardView()
            }
            .padding(.bottom, 77)
        }
        // [D21] Voice call: ringing banner (top) + full-screen call screen.
        // Rides above every tab, like the approval cards above.
        .overlay(alignment: .top) {
            VoiceCallOverlay()
        }
    }

    /// One tab layer: only the selected tab is visible and hittable; the
    /// others stay alive underneath so their state is preserved.
    private func tabLayer(_ tab: DuduTab, @ViewBuilder content: () -> some View) -> some View {
        content()
            .opacity(selection == tab ? 1 : 0)
            .allowsHitTesting(selection == tab)
            .accessibilityHidden(selection != tab)
            .zIndex(selection == tab ? 1 : 0)
    }
}
