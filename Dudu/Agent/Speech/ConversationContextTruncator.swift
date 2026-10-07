//
//  P6 PORT (2026-10-07): ported from OpenMinis Agent/Speech/ConversationContextTruncator.swift — renames Minis->Dudu
//  (incl. mid-identifier), com.openminis.clone->com.dudu.ios, group ids,
//  minis->dudu prefixes (minis-clone://->dudu-clone://, minis-browser-use->dudu-browser-use,
//  /var/minis/->/var/dudu/); iCloud container refs dropped (no iCloud entitlement).
//  Real English words containing "minis" (deterministic*) untouched.
import Foundation

/// Soft-cap truncation for the conversation context injected into the correction prompt
/// (design §6).
///
/// "Soft" is the whole point: cutting at exactly 500 characters would routinely slice a
/// sentence in half, and a half-sentence is worse context than a slightly longer whole
/// one. So we take the first `softLimit` characters, then keep scanning to the next
/// sentence terminator and cut *there* — accepting that the result may exceed the limit.
///
/// The escape hatch matters too: text with no punctuation at all (a wall-of-words
/// transcript) would otherwise scan to the end and blow up the prompt, so we give up
/// after `hardCeiling` and hard-cut with an ellipsis.
enum ConversationContextTruncator {

    /// Truncated text, plus whether truncation happened (the caller appends "…" so the
    /// model knows it's reading an excerpt, not a complete message — design §6).
    struct Result: Equatable {
        let text: String
        let wasTruncated: Bool
    }

    static func truncate(_ text: String,
                         softLimit: Int = VoiceCorrectionConfig.contextSoftLimit,
                         hardCeiling: Int = VoiceCorrectionConfig.contextHardCeiling) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result(text: "", wasTruncated: false) }

        let chars = Array(trimmed)
        // Under the cap: use it whole. No truncation, no ellipsis.
        if chars.count <= softLimit {
            return Result(text: trimmed, wasTruncated: false)
        }

        // Past the cap: scan forward for the first sentence terminator, but never past
        // the hard ceiling.
        let scanEnd = min(chars.count, hardCeiling)
        var cut: Int?
        var i = softLimit
        while i < scanEnd {
            if SentenceSplitter.isTerminator(chars[i]) {
                cut = i + 1     // inclusive of the punctuation itself
                break
            }
            i += 1
        }

        if let cut {
            let body = String(chars[0..<cut])
            return Result(text: body + "…", wasTruncated: true)
        }

        // No terminator within the safety margin — degrade to a hard cut (design §6-2d).
        let body = String(chars[0..<softLimit])
        return Result(text: body + "…", wasTruncated: true)
    }
}
