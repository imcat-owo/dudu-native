//  P7 PORT (2026-10-07): ported from OpenMinis Agent/Intents/OpenSessionIntent.swift — renames Minis->Dudu
//  (incl. mid-identifier; English words like deterministic/administrative untouched),
//  com.openminis.clone->com.dudu.ios, group ids, minis->dudu prefixes
//  (minis-clone://->dudu-clone://, minis-browser-use->dudu-browser-use,
//  /var/minis/->/var/dudu/, MINIS_SESSION_ID->DUDU_SESSION_ID);
//  iCloud container id renamed (entitlement dropped); OpenMinis#NNN issue refs
//  and github.com/OpenMinis URLs kept (upstream project).
//

import AppIntents
import Foundation

/// Opens a specific chat session in the Dudu app.
struct OpenSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Session"
    static var description = IntentDescription("Opens a 我的小家 chat session in the app.")
    static var openAppWhenRun = true

    @Parameter(title: "Session")
    var session: SessionEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .openSessionFromIntent,
            object: nil,
            userInfo: ["sessionId": session.id]
        )
        return .result()
    }
}

// P7 PORT: `openSessionFromIntent` is defined in Dudu/Shared/DuduNotifications.swift
// (P1-owned cross-cutting definition) — removed the duplicate that was here.
