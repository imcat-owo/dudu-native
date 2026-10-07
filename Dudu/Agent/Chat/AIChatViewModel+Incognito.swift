//
//  Phase D4 (2026-10-07): incognito chat — in-memory-only conversations.
//
//  Privacy contract: while `isIncognito` is true, NO message content touches
//  disk. The engine never creates a ChatStore session row and never appends
//  message rows (see the guards in `createSessionForDraft`,
//  `persistAgentMessage`, the batch-persist path, AskUser, and title
//  generation). ChatStore itself drops any write whose session id carries the
//  `incognito-` prefix as a second layer of defense, so even a missed guard
//  cannot persist content. Attachment uploads go to a tmp dir that is wiped
//  on exit; nothing lands in the persistent per-session directories.
//
//  Exiting incognito discards everything in memory. The caller (ChatView)
//  confirms with the user first when there are messages to lose.
import Foundation
import UIKit

private let incognitoLogger = AppLogger(category: "AIChatVM-Incognito")

extension AIChatViewModel {

    /// Prefix marking in-memory-only session ids. Never written to ChatStore
    /// (see `ChatStore.isEphemeralSessionId`).
    static let incognitoSessionIdPrefix = "incognito-"

    static func isIncognitoSessionId(_ id: String) -> Bool {
        id.hasPrefix(incognitoSessionIdPrefix)
    }

    /// Enter incognito mode: reset to a blank slate, in memory only.
    /// Any previous normal session's rows stay intact in the database.
    func enterIncognito() {
        resetViewState()
        isIncognito = true
        incognitoLogger.info("[Incognito] entered — in-memory only from here")
    }

    /// Exit incognito mode and discard everything.
    /// - Parameter confirmed: the view confirms with the user when messages
    ///   exist; pass true once they accept the loss.
    func exitIncognito(confirmed: Bool = false) {
        guard isIncognito else { return }
        resetViewState()
        isIncognito = false
        incognitoLogger.info("[Incognito] exited (confirmed=\(confirmed)) — in-memory transcript discarded")
    }

    /// Reset the view to a fresh draft without touching the database.
    /// Shared by enter/exit incognito and normal "new chat". Also wipes any
    /// tmp files an incognito session may have left behind.
    func resetViewState() {
        sessionId = nil
        sessionPersonaId = nil
        messages.removeAll()
        agentHistory.removeAll()
        errorMessage = nil
        transientNotice = nil
        inputText = ""
        attachments.removeAll()
        titleGenAttempts = 0
        isTitleGenerating = false
        canResume = false
        isSuspended = false
        wipeIncognitoTempFiles()
    }

    /// Uploads dir for a session. In incognito this is a tmp dir (wiped on
    /// exit); normal sessions use the persistent per-session uploads dir.
    func sessionUploadsDir(for sid: String) -> URL {
        if isIncognito {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("dudu-incognito-uploads", isDirectory: true)
                .appendingPathComponent(sid, isDirectory: true)
                .appendingPathComponent("uploads", isDirectory: true)
        }
        return DuduPaths.duduUploadsDir(for: sid)
    }

    /// Offloads dir for a session (large tool outputs). Same incognito rule:
    /// tmp in incognito, wiped on exit.
    func sessionOffloadsDir(for sid: String) -> URL {
        if isIncognito {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("dudu-incognito-uploads", isDirectory: true)
                .appendingPathComponent(sid, isDirectory: true)
                .appendingPathComponent("offloads", isDirectory: true)
        }
        return DuduPaths.duduOffloadsPersistentDir(for: sid)
    }

    /// Browser dir for a session (screenshots, downloads). Same incognito
    /// rule: tmp in incognito, wiped on exit.
    func sessionBrowserDir(for sid: String) -> URL {
        if isIncognito {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("dudu-incognito-uploads", isDirectory: true)
                .appendingPathComponent(sid, isDirectory: true)
                .appendingPathComponent("browser", isDirectory: true)
        }
        return DuduPaths.duduBrowserPersistentDir(for: sid)
    }

    /// Attachments dir for a session. Same incognito rule.
    func sessionAttachmentsDir(for sid: String) -> URL {
        if isIncognito {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("dudu-incognito-uploads", isDirectory: true)
                .appendingPathComponent(sid, isDirectory: true)
                .appendingPathComponent("attachments", isDirectory: true)
        }
        return DuduPaths.duduAttachmentsPersistentDir(for: sid)
    }

    /// Delete any tmp upload dirs left by incognito sessions.
    func wipeIncognitoTempFiles() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("dudu-incognito-uploads", isDirectory: true)
        if fm.fileExists(atPath: root.path) {
            try? fm.removeItem(at: root)
            incognitoLogger.info("[Incognito] wiped tmp uploads")
        }
    }
}
