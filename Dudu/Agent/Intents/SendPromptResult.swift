//  P7 PORT (2026-10-07): ported from OpenMinis Agent/Intents/SendPromptResult.swift — renames Minis->Dudu
//  (incl. mid-identifier; English words like deterministic/administrative untouched),
//  com.openminis.clone->com.dudu.ios, group ids, minis->dudu prefixes
//  (minis-clone://->dudu-clone://, minis-browser-use->dudu-browser-use,
//  /var/minis/->/var/dudu/, MINIS_SESSION_ID->DUDU_SESSION_ID);
//  iCloud container id renamed (entitlement dropped); OpenMinis#NNN issue refs
//  and github.com/OpenMinis URLs kept (upstream project).
//

import AppIntents
import Foundation

/// Structured result returned by SendPromptIntent, usable in Shortcuts automation chains.
struct SendPromptResult: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Prompt Result")
    static var defaultQuery = SendPromptResultQuery()

    var id: String  // session ID

    @Property(title: "Session ID")
    var sessionId: String

    @Property(title: "Model")
    var modelName: String

    @Property(title: "Status")
    var status: String

    @Property(title: "Is New Session")
    var isNewSession: Bool

    @Property(title: "Prompt")
    var prompt: String

    @Property(title: "Response")
    var responseText: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(sessionId)",
            subtitle: "\(modelName) · \(status)"
        )
    }

    init(sessionId: String, modelName: String, status: String, isNewSession: Bool, prompt: String = "", responseText: String = "") {
        self.id = sessionId
        self.sessionId = sessionId
        self.modelName = modelName
        self.status = status
        self.isNewSession = isNewSession
        self.prompt = prompt
        self.responseText = responseText
    }
}

/// Minimal query — result entities are ephemeral, not persisted.
struct SendPromptResultQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SendPromptResult] {
        []
    }
}
