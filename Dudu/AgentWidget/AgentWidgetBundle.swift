//  P7 PORT (2026-10-07): ported from OpenMinis AgentWidget/AgentWidgetBundle.swift — renames Minis->Dudu
//  (incl. mid-identifier; English words like deterministic/administrative untouched),
//  com.openminis.clone->com.dudu.ios, group ids, minis->dudu prefixes
//  (minis-clone://->dudu-clone://, minis-browser-use->dudu-browser-use,
//  /var/minis/->/var/dudu/, MINIS_SESSION_ID->DUDU_SESSION_ID);
//  iCloud container id renamed (entitlement dropped); OpenMinis#NNN issue refs
//  and github.com/OpenMinis URLs kept (upstream project).
//

import SwiftUI
import WidgetKit

@main
struct AgentWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOSApplicationExtension 16.2, *) {
            AgentLiveActivityWidget()
        }
    }
}
