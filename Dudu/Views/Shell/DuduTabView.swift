import SwiftUI

/// Root view of the app (Phase C shell). Owns the engine singletons as
/// @StateObject, injects them into the environment, and routes the
/// Phase-C deep-link destinations from DeepLinkCoordinator.
struct DuduTabView: View {
    @State private var selection: DuduTab = .chat

    // Engine singletons — owned here, shared with the whole shell.
    @StateObject private var chatViewModel = AIChatViewModel()
    @StateObject private var providerStore = ProviderConfigStore.shared
    @StateObject private var appearance = AppearanceStudio.shared
    @ObservedObject private var deepLinks = DeepLinkCoordinator.shared

    var body: some View {
        TabView(selection: $selection) {
            ChatView(selection: $selection)
                .tabItem {
                    Label(DuduTab.chat.title, systemImage: DuduTab.chat.systemImage)
                }
                .tag(DuduTab.chat)

            OurSpaceView()
                .tabItem {
                    Label(DuduTab.ourSpace.title, systemImage: DuduTab.ourSpace.systemImage)
                }
                .tag(DuduTab.ourSpace)

            SettingsView()
                .tabItem {
                    Label(DuduTab.settings.title, systemImage: DuduTab.settings.systemImage)
                }
                .tag(DuduTab.settings)
        }
        .tint(DuduTheme.pink)
        // Liquid Glass: iOS system material only. No custom blur overlays.
        .toolbarBackground(.visible, for: .tabBar)
        .environmentObject(chatViewModel)
        .environmentObject(providerStore)
        .environmentObject(appearance)
        .onReceive(deepLinks.$pendingSettingsTarget) { target in
            guard target != nil else { return }
            // Phase C destinations (providers / providerDetail / appearance)
            // land on the Settings tab. The step-6 Settings builder consumes
            // pendingSettingsTarget for the actual push; the value stays
            // published for it.
            selection = .settings
        }
        .appFontScale()
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
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                ThemeTryOnBanner()
                AIAuthorizationPromptView()
                MCPApprovalCardView()
            }
        }
        // [D21] Voice call: ringing banner (top) + full-screen call screen.
        // Rides above every tab, like the approval cards above.
        .overlay(alignment: .top) {
            VoiceCallOverlay()
        }
    }
}
