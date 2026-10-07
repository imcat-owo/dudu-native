//
//  DuduPaths.swift
//  Dudu
//
//  Central path-helper family for the Dudu native rewrite (P1 — Shared foundation).
//  Ported from AIChatViewModel+RequestBudget.swift and AIChatViewModel+Misc.swift
//  (OpenMinis), renamed Minis -> Dudu. Exact logic, only renames, with two
//  deliberate deviations documented below.
//
//  DEVIATION 1 — resolveDuduURL takes the session id as a parameter.
//  The original read `AIChatViewModel.activeSessionId` directly; that type lands
//  in P4 (chat core) and must stay the single owner of the session id. P4 should
//  keep a thin wrapper and change nothing here:
//      nonisolated static func resolveDuduURL(_ url: URL) -> URL? {
//          DuduPaths.resolveDuduURL(url, activeSessionId: activeSessionId)
//      }
//
//  DEVIATION 2 — the `nonisolated` modifiers from the original are dropped.
//  They existed because AIChatViewModel is @MainActor; this plain enum is
//  nonisolated by definition, so the modifiers would be noise.
//
//  Later parts (P4 chat core, P7 capabilities) must use DuduPaths instead of
//  re-deriving these directories.
//
//  SEAM (P3): `duduAttachmentsPersistentDir(for:)` and `duduUploadsDir(for:)`
//  were moved early for P3 (ported from AIChatViewModel+Misc.swift
//  `minisAttachmentsPersistentDir`/`minisUploadsDir`); P4 AIChatViewModel must
//  forward to DuduPaths, not duplicate them.

import Foundation

/// App-wide filesystem locations: App Group container, per-session persistent
/// storage, and the iSH-visible `/var/dudu/` twins.
enum DuduPaths {

    // MARK: - App Group (shared container)

    /// App Group container root for FileProvider-visible directories.
    /// Everything under this path is exposed to iOS Files via the replicated
    /// FileProvider extension. Keep ONLY user-facing subdirs (shared, skills,
    /// memory) here — anything else leaks into "On My iPhone → Dudu".
    static var duduAppGroupRoot: URL {
        SharedContainerStore.containerURL
            .appendingPathComponent("DuduFileProvider", isDirectory: true)
    }

    /// App Group subdirectory for private metadata that must NOT be exposed
    /// to iOS Files (mounted-folders.json, FileProvider extension logs, etc).
    /// Sibling of `duduAppGroupRoot` inside the same App Group container.
    static var duduConfigRoot: URL {
        let url = SharedContainerStore.containerURL
            .appendingPathComponent("DuduConfig", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Persistent storage directory for memory (shared across all sessions).
    /// Stored in the App Group container so the FileProvider extension can access it.
    static var duduMemoryPersistentDir: URL {
        duduAppGroupRoot.appendingPathComponent("memory", isDirectory: true)
    }

    /// Persistent storage directory for skills (shared across all sessions).
    /// Stored in the App Group container so the FileProvider extension can access it.
    static var duduSkillsPersistentDir: URL {
        duduAppGroupRoot.appendingPathComponent("skills", isDirectory: true)
    }

    /// Persistent storage directory for shared files (shared across all sessions).
    /// Stored in the App Group container so the FileProvider extension can access it.
    static var duduSharedPersistentDir: URL {
        duduAppGroupRoot.appendingPathComponent("shared", isDirectory: true)
    }

    /// Persistent storage directory for MCP server configs (servers.json,
    /// daemon log). Deliberately under DuduConfig, NOT duduAppGroupRoot:
    /// servers.json carries credentials (Authorization headers, API keys) and
    /// must never surface in iOS Files via the FileProvider extension.
    static var duduMcpServersPersistentDir: URL {
        duduConfigRoot.appendingPathComponent("mcp-servers", isDirectory: true)
    }

    // MARK: - iOS persistent base (per-session data)

    /// iOS persistent base for all dudu data (Library/DuduChat/dudu/).
    static var duduPersistentBase: URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return lib.appendingPathComponent("DuduChat/dudu", isDirectory: true)
    }

    /// Persistent storage directory for a specific session's browser snapshots.
    static func duduBrowserPersistentDir(for sid: String) -> URL {
        duduPersistentBase.appendingPathComponent(sid, isDirectory: true)
            .appendingPathComponent("browser", isDirectory: true)
    }

    /// Persistent storage directory for a specific session's offloads.
    static func duduOffloadsPersistentDir(for sid: String) -> URL {
        duduPersistentBase.appendingPathComponent(sid, isDirectory: true)
            .appendingPathComponent("offloads", isDirectory: true)
    }

    /// Persistent storage directory for a specific session's attachments.
    static func duduAttachmentsPersistentDir(for sid: String) -> URL {
        duduPersistentBase.appendingPathComponent(sid, isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
    }

    /// Persistent storage directory for a specific session's uploaded attachments.
    static func duduUploadsDir(for sid: String) -> URL {
        duduAttachmentsPersistentDir(for: sid)
            .appendingPathComponent("uploads", isDirectory: true)
    }

    // MARK: - iSH-visible Linux paths (/var/dudu/)

    /// Unified bidirectional file area between iOS and iSH:
    ///   /var/dudu/attachments/  — screenshots, images, media
    ///   /var/dudu/offloads/     — large tool outputs
    ///   /var/dudu/workspace/    — general session working area
    /// P8 (iSH) must keep the rootfs twins of these paths in sync.
    static let duduLinuxBaseDir = "/var/dudu"
    static let duduAttachmentsLinuxDir = "/var/dudu/attachments"
    static let duduOffloadsLinuxDir = "/var/dudu/offloads"
    static let duduWorkspaceLinuxDir = "/var/dudu/workspace"
    static let duduBrowserLinuxDir = "/var/dudu/browser"
    static let duduMemoryLinuxDir = "/var/dudu/memory"
    static let duduSkillsLinuxDir = "/var/dudu/skills"
    static let duduSharedLinuxDir = "/var/dudu/shared"
    static let duduMcpServersLinuxDir = "/var/dudu/mcp-servers"
    static let duduMountsLinuxDir = "/var/dudu/mounts"

    // MARK: - dudu-clone:// URL resolution

    /// Resolve a `dudu-clone://` URL to a host filesystem URL.
    /// Shared resolution logic used by Markdown link handlers and the browser's WKURLSchemeHandler.
    /// `activeSessionId` is injected (P4 owns it on AIChatViewModel) — see file header.
    static func resolveDuduURL(_ url: URL, activeSessionId: String?) -> URL? {
        guard url.scheme == "dudu-clone", let host = url.host else { return nil }
        // Tolerate double-encoded links (%25E6…) alongside the correct
        // single-encoded form. [T-fix-double-encoding]
        let subPaths = duduSubPathCandidates(for: url)
        let fm = FileManager.default

        // Primary: resolve via active session
        if let sid = activeSessionId {
            for subPath in subPaths {
                let candidate = duduPersistentBase
                    .appendingPathComponent(sid, isDirectory: true)
                    .appendingPathComponent(host, isDirectory: true)
                    .appendingPathComponent(subPath)
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
        }

        // Global directories (skills, memory, shared)
        let globalDirs: [(String, URL)] = [
            ("skills", duduSkillsPersistentDir),
            ("memory", duduMemoryPersistentDir),
            ("shared", duduSharedPersistentDir),
        ]
        for (subdir, dir) in globalDirs where host == subdir {
            for subPath in subPaths {
                let candidate = dir.appendingPathComponent(subPath)
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
        }

        // Scan all sessions
        if let sessions = try? fm.contentsOfDirectory(atPath: duduPersistentBase.path) {
            for sid in sessions {
                for subPath in subPaths {
                    let candidate = duduPersistentBase
                        .appendingPathComponent(sid, isDirectory: true)
                        .appendingPathComponent(host, isDirectory: true)
                        .appendingPathComponent(subPath)
                    if fm.fileExists(atPath: candidate.path) { return candidate }
                }
            }
        }
        return nil
    }

    // MARK: - private

    /// Candidate subpaths for a `dudu-clone://` URL, in priority order.
    /// Ported from MinisURLPathDecoding.subPathCandidates (Agent/Chat, P4) as a
    /// private copy so Shared compiles without the chat core. P4 ports
    /// MinisURLPathDecoding.swift -> DuduURLPathDecoding.swift; the two
    /// implementations must stay in sync (same [T-fix-double-encoding] rule).
    private static func duduSubPathCandidates(for url: URL) -> [String] {
        let p = url.path
        let base = p.hasPrefix("/") ? String(p.dropFirst()) : p
        var candidates = [base]
        // Recover double-encoded names: a second decode collapses %25XX → %XX
        // → the real UTF-8 character. Only add it when it actually differs so
        // single-encoded (already-correct) URLs keep exactly one candidate.
        if let twice = base.removingPercentEncoding, twice != base {
            candidates.append(twice)
        }
        return candidates
    }
}
