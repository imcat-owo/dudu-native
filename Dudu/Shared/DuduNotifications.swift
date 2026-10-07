//
//  DuduNotifications.swift
//  Dudu
//
//  P1-owned cross-cutting definitions (ported from OpenMinis, exact string
//  values — these are cross-part contracts, do NOT rename the values):
//  - NSNotification.Name.openSessionFromIntent  (was Agent/Intents/OpenSessionIntent.swift)
//  - NSNotification.Name.dismissAllImmersivePresentations (was MinisApp.swift)
//  - Bundle.languageBundle (was MinisApp.swift; the in-app language override
//    bundle. The swizzle entry point `enableLanguageOverride()` stays with the
//    app entry and is NOT ported here.)
//
//  Later parts must NOT redeclare these — they would be duplicate symbols.

import Foundation
import ObjectiveC

extension NSNotification.Name {
    /// Posted with userInfo["sessionId"] to open a chat session
    /// (App Intents flow).
    static let openSessionFromIntent = NSNotification.Name("openSessionFromIntent")

    /// Posted before presenting a WebApp to dismiss any leftover
    /// fullScreenCover (image gallery, in-chat web preview, camera, …).
    /// iOS allows one fullScreenCover per host view; presenting while
    /// another is up silently no-ops.
    static let dismissAllImmersivePresentations =
        NSNotification.Name("dismissAllImmersivePresentations")

    /// P7: posted when memory files change (was
    /// Views/Settings/MemoryManagementView.swift in OpenMinis; moved to the
    /// engine because AIChatViewModel+MemoryTools posts it and
    /// ChatStoreSyncHydrators observes it — both engine. The Views overlay
    /// must NOT redeclare it).
    static let memoryFilesDidChange =
        NSNotification.Name("com.dudu.ios.memoryFilesDidChange")

    /// P7: chat session lifecycle (were MinisApp.swift in OpenMinis).
    static let sessionDidCreate = NSNotification.Name("sessionDidCreate")
    static let sessionDidUpdate = NSNotification.Name("sessionDidUpdate")
    static let sessionAgentLoopDidEnd = NSNotification.Name("sessionAgentLoopDidEnd")

    /// P7: posted when user attachments are mounted for a session (was
    /// Agent/MessageList/CollectionViewMessageListV3.swift in OpenMinis,
    /// which is excluded until Views/Phase C — the definition moves here
    /// so the engine compiles; Views must NOT redeclare it).
    static let duduUserAttachmentsMounted =
        NSNotification.Name("duduUserAttachmentsMounted")
}

extension Bundle {
    private static var overrideBundleKey: UInt8 = 0

    /// The language-specific `.lproj` bundle currently in use, or `nil` for
    /// system default. Set by the in-app language picker (later part).
    var languageBundle: Bundle? {
        get { objc_getAssociatedObject(self, &Self.overrideBundleKey) as? Bundle }
        set {
            objc_setAssociatedObject(
                self, &Self.overrideBundleKey, newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
