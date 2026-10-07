//
//  ProviderV3Bootstrap.swift
//  Dudu
//
//  P4 EXTRACT (2026-10-07): this tiny feature-flag enum is the only piece of
//  OpenMinis Agent/Sync/V2/ChatStoreSyncHydrators.swift needed by P3/P4.
//  ProviderConfigStore (P3) gates its V3-DB authority on
//  `ProviderV3Bootstrap.isEnabled`; the gate was dropped in P3 with the
//  iCloud refs and is restored here.
//
//  It is intentionally self-contained (UserDefaults only) so Providers and
//  the chat core can use it without the Sync engine.
//
//  WHEN Agent/Sync lands (P7): DELETE this file and use the canonical enum
//  in ChatStoreSyncHydrators.swift — do not keep two definitions.

import Foundation

/// Controls whether the v3 per-record sync surface is the authoritative
/// inbound path for ProviderConfig data. Default ON; kill-switch via
/// UserDefaults key `cloudSync.providerV3.enabled`.
/// Extracted verbatim from OpenMinis Agent/Sync/V2/ChatStoreSyncHydrators.swift.
@MainActor
enum ProviderV3Bootstrap {
    private static let key = "cloudSync.providerV3.enabled"
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
        duduProviderV3Log.info("[v3] ProviderV3Bootstrap.setEnabled(\(enabled))")
    }
}

private let duduProviderV3Log = AppLogger(category: "ProviderV3")
