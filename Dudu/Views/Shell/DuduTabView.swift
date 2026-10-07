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
        // Phase D3: tool-approval card floats above everything (overlay, not a
        // sheet) so chat stays interactive while a request is pending.
        // D9: AI authorization prompt rides the same overlay; it only renders
        // when OffloadPermissionManager.pendingRequest is non-nil.
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                AIAuthorizationPromptView()
                MCPApprovalCardView()
            }
        }
    }
}
