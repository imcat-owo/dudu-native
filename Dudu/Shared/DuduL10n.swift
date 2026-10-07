//
//  DuduL10n.swift
//  DuduApp
//
//  [D13] Typed access to Localizable.xcstrings — the trilingual string catalog
//  ported verbatim from openmuse/apps/mobile/src/i18n/{zh-Hans,zh-Hant,en}.ts
//  (2486 keys, en + zh-Hans + zh-Hant).
//
//  Source placeholders like {name} were compiled to positional format
//  specifiers (%1$@, %2$@, ...) so every locale keeps its own word order.
//  %@ boxes Int/Double automatically, so counts can be passed as Ints.
//
//  Usage from Views:
//      Text(L10n.string("chat.title"))              // plain lookup
//      L10n.format("pgroup.messageCount", count)    // with placeholders
//
//  No colors, no UI here — strings only. New user-facing copy goes into the
//  catalog, never hardcoded in a View.

import Foundation

/// Read-only view over the Localizable string catalog.
///
/// Resolution follows the in-app language override (`AppBundle.current`), which
/// falls back to `Bundle.main` when no override is set — system-language
/// behaviour is unchanged. A missing key falls back to the key itself
/// (never a crash, never an empty string).
enum L10n {
    /// Resolve one catalog key to its localized text.
    static func string(_ key: String) -> String {
        AppBundle.current.localizedString(forKey: key, value: key, table: nil)
    }

    /// Resolve one catalog key and interpolate its placeholders.
    ///
    /// Pass arguments in the order the source `{name}` placeholders appear;
    /// positional specifiers make locale-specific reordering safe.
    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: args)
    }
}
