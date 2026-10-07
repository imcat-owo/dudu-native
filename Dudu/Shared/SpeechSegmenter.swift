//
//  SpeechSegmenter.swift
//  Dudu
//
//  SEAM (P3): moved early for P3; P4 AIChatViewModel must forward, not duplicate.
//  Ported from AIChatViewModel+SSEStream.swift (~line 140+, OpenMinis):
//  `splitIntoSpeechSegments(_:)`, `extractSentencesStatic(from:spokenOffset:)`,
//  the `speechEnders`/`speechPauses`/`speechSoftLimit` constants, and the
//  private `appendUnit` helper. Renamed Minis -> Dudu (no renames applied here;
//  the code had no product identifiers).
//
//  The `nonisolated` modifiers from the original are dropped: they existed
//  because AIChatViewModel is @MainActor; this plain enum is nonisolated by
//  definition (same deviation as DuduPaths).
//
//  Later parts (P4 chat core) must call SpeechSegmenter instead of
//  re-implementing segmentation.

import Foundation

/// Streaming-text speech segmentation: splits streamed/markdown text into
/// speakable units for TTS. Moved here from AIChatViewModel so Providers/Voice
/// (VoiceOutputPlayer) can use it without the chat core.
enum SpeechSegmenter {
        /// Returns (array of sentences to speak, new offset into text).
        /// Split newly-streamed text into speakable units. A unit ends at a sentence
        /// terminator (。！？.!?) or a newline (so Markdown headings & list items read
        /// as their own line). To keep first-utterance latency low, a run that grows
        /// past `softLimit` characters without a terminator is forced out at the last
        /// comma/pause mark. Fenced code blocks (``` … ```) are skipped (not read).
        /// Markdown lead-in markers (#, -, *, >) are stripped before speaking.
        // MARK: - Speech segmentation tuning (constants — adjust from logs)
        /// Tier-1 boundaries (highest priority): full-sentence terminators + newline.
        static let speechEnders: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n", "；", ";"]
        /// Tier-2 boundaries: weaker pause marks used only when a run grows too long
        /// without a tier-1 ender (so we don't read an over-long unbroken clause).
        static let speechPauses: Set<Character> = ["，", ",", "、", "：", ":"]
        /// Soft length (chars) past which a run is force-cut at the last pause mark.
        /// Sized below the dynamic-window max so a single extracted unit stays well
        /// under the TTS max-batch ceiling.
        static let speechSoftLimit = 60

        /// Static entry point so callers without a vm reference (long-press TTS,
        /// markdown preview read-aloud) can split text with the same segmenter.
        static func splitIntoSpeechSegments(_ text: String) -> [String] {
            let (segments, _) = extractSentencesStatic(from: text, spokenOffset: 0)
            return segments.isEmpty ? [text] : segments
        }

        static func extractSentencesStatic(from text: String, spokenOffset: Int) -> (sentences: [String], newOffset: Int) {
            guard spokenOffset < text.count else { return ([], spokenOffset) }
            let startIndex = text.index(text.startIndex, offsetBy: spokenOffset)
            let remaining = Array(text[startIndex...])
            let enders = Self.speechEnders
            let pauses = Self.speechPauses
            let softLimit = Self.speechSoftLimit

            var units: [String] = []
            var consumed = 0           // chars consumed from `remaining`
            var unitStart = 0
            var lastPause = -1         // index of last pause mark in the current run

            func isFence(at idx: Int) -> Bool {
                idx + 2 < remaining.count && remaining[idx] == "`"
                    && remaining[idx+1] == "`" && remaining[idx+2] == "`"
            }

            // A `.` or `,` flanked by digits on BOTH sides is an intra-number
            // separator (decimal point "28.98" / "3.14" / "$1.5" / "2.0", European
            // decimal comma "€28,98", or thousands grouping "1,000,000"), NOT a
            // sentence boundary or clause pause. Splitting there mangles the number
            // into "28." + "98" and the TTS reads it wrong / mid-word. Both neighbors
            // must be digits so a real sentence end after a number ("He scored 5. Then…")
            // still cuts. Uses Character.isNumber so ASCII and full-width digits both count.
            func isIntraNumberSeparator(at idx: Int) -> Bool {
                let ch = remaining[idx]
                guard ch == "." || ch == "," else { return false }
                guard idx > 0, idx + 1 < remaining.count else { return false }
                return remaining[idx - 1].isNumber && remaining[idx + 1].isNumber
            }

            var i = 0
            while i < remaining.count {
                if isFence(at: i) {
                    // Only SKIP a fenced block once we can see its CLOSING fence in the
                    // current buffer. An unclosed fence is left for a later delta — we
                    // stop here WITHOUT advancing `consumed` past the open fence, but we
                    // also stop scanning, so the offset is whatever we consumed BEFORE
                    // the fence (never stalls on already-consumed text). When the close
                    // arrives we skip the whole block in one go.
                    var j = i + 3
                    var foundClose = false
                    while j < remaining.count {
                        if isFence(at: j) { foundClose = true; break }
                        j += 1
                    }
                    guard foundClose else { break }   // incomplete fence → wait
                    // Flush any pending text before the fence as a unit.
                    if i > unitStart { appendUnit(remaining[unitStart..<i], into: &units) }
                    let afterClose = j + 3
                    unitStart = afterClose; consumed = afterClose; i = afterClose; lastPause = -1
                    continue
                }

                let ch = remaining[i]
                // Skip intra-number separators entirely: they must never register as a
                // pause (else a long clause force-cuts inside "€28,98") nor as an ender.
                if isIntraNumberSeparator(at: i) {
                    i += 1
                    continue
                }
                // Streaming look-ahead: a `.`/`,` that trails a digit at the CURRENT END
                // of the buffer might be a decimal point whose fractional part hasn't
                // streamed yet ("price 28." with "98" still in flight). Committing it now
                // as a sentence ender would speak "28." early and split the number. Stop
                // scanning WITHOUT consuming it — the next delta reveals whether a digit
                // (→ intra-number, skip) or non-digit (→ real boundary) follows. Mirrors
                // the unclosed-fence wait above. Only applies at the very last char so
                // fully-arrived text is never delayed.
                if i == remaining.count - 1, (ch == "." || ch == ","), i > 0, remaining[i - 1].isNumber {
                    break
                }
                if pauses.contains(ch) { lastPause = i }

                let runLen = i - unitStart + 1
                let isEnder = enders.contains(ch)
                // Force a cut at a pause mark if the run got too long without an ender.
                let forceCut = !isEnder && runLen >= softLimit && lastPause >= unitStart

                if isEnder {
                    appendUnit(remaining[unitStart...i], into: &units)
                    i += 1; unitStart = i; consumed = i; lastPause = -1
                } else if forceCut {
                    appendUnit(remaining[unitStart...lastPause], into: &units)
                    unitStart = lastPause + 1; consumed = unitStart; i += 1; lastPause = -1
                } else {
                    i += 1
                }
            }
            return (units, spokenOffset + consumed)
        }

        /// Trim, strip Markdown lead-in markers, and append if non-empty/speakable.
        private static func appendUnit(_ slice: ArraySlice<Character>, into units: inout [String]) {
            var s = String(slice).trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip leading markdown markers: #, >, -, *, 1. etc.
            while let first = s.first, "#>-*".contains(first) {
                s.removeFirst()
                s = s.trimmingCharacters(in: .whitespaces)
            }
            // Ordered-list marker "1. " / "12) "
            if let r = s.range(of: "^\\d+[.)]\\s+", options: .regularExpression) {
                s.removeSubrange(r)
            }
            guard !s.isEmpty else { return }
            // Skip units that are only symbols / a bare URL (nothing useful to read).
            if s.range(of: "[\\p{L}\\p{N}]", options: .regularExpression) == nil { return }
            if s.range(of: "^https?://\\S+$", options: .regularExpression) != nil { return }
            units.append(s)
        }
}
