import Foundation
import UIKit

// MARK: - D25 · CrossAppOpener
//
// The real "open in other app" engine for the cross-app list.
//
// Wiring: this uses UIApplication.shared.open(_:options:completionHandler:) —
// the EXACT same mechanism as the native `apple-open` engine
// (Dudu/NativeOffloads/OpenOffload.m `open_handler`, registered via
// open_offload_register()). One mechanism, one honesty contract: the
// completion handler reports whether the system actually opened the URL,
// and the UI surfaces that result instead of pretending.
//
// Rules (from the old openapp whitelist):
// - Only whitelisted entries are opened (lookupOpenAppEntry); unknown ids
//   are refused, never guessed.
// - Every attempt is real: the returned result says opened / not installed /
//   failed. No dead buttons.

private let crossAppLogger = AppLogger(category: "CrossApp")

enum CrossAppOpenResult {
    /// The system opened the URL.
    case opened
    /// No app on this phone handles the scheme (honest "not installed").
    case notHandled
}

enum CrossAppDestination {
    /// Leave 嘟嘟 for the other app.
    case jump(URL)
    /// Stay in 嘟嘟: open in the in-app browser.
    case webview(URL)
}

enum CrossAppOpener {
    /// Resolve an entry + args to a concrete destination. Throws on unknown
    /// entry id, missing required params, or (for webview) no web version.
    static func resolve(entryId: String, args: [String: String] = [:]) throws -> (OpenAppEntry, CrossAppDestination) {
        guard let entry = lookupOpenAppEntry(id: entryId) else {
            throw OpenAppURLError.unknownEntry(entryId, entry: "openapp")
        }
        switch entry.mode {
        case .jump:
            let url = try buildEntryURL(entry: entry, args: args)
            return (entry, .jump(url))
        case .webview:
            guard entry.webUrl != nil else {
                throw OpenAppURLError.noWebVersion(entry.app)
            }
            let webEntry = OpenAppEntry(
                id: entry.id, app: entry.app, useWhen: entry.useWhen,
                mode: .webview, url: entry.webUrl!, webUrl: entry.webUrl,
                params: entry.params, xCallback: entry.xCallback
            )
            let url = try buildEntryURL(entry: webEntry, args: args)
            return (entry, .webview(url))
        }
    }

    /// Really attempt to open a jump URL. The completion value is the
    /// system's honest answer — true = the other app opened.
    @MainActor
    static func open(_ url: URL) async -> CrossAppOpenResult {
        let scheme = url.scheme ?? ""
        // canOpenURL is honest on iOS only for schemes declared in
        // LSApplicationQueriesSchemes (see OPEN_APP_QUERIED_SCHEMES) —
        // undeclared schemes report false even when the app exists, so the
        // real verdict comes from open(_:options:completionHandler:).
        let handled: Bool = await withCheckedContinuation { cont in
            UIApplication.shared.open(url, options: [:]) { success in
                cont.resume(returning: success)
            }
        }
        crossAppLogger.info("open scheme=\(scheme) handled=\(handled)")
        return handled ? .opened : .notHandled
    }
}
