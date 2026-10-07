import Foundation
import PDFKit
import UniformTypeIdentifiers

// MARK: - KnowledgePDFImport · D14 document text extraction
//
// Honest, minimal: PDF via PDFKit (page.string), plain/markdown text via
// String(contentsOf:). Scanned-image PDFs have no extractable text layer —
// that throws KnowledgeError.noExtractableText instead of indexing garbage.

enum KnowledgePDFImport {

    /// Extract plain text from a PDF at `url`. Handles security-scoped URLs
    /// (as handed out by SwiftUI fileImporter).
    static func extractText(fromPDF url: URL) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        guard let document = PDFDocument(url: url) else {
            throw KnowledgeError.noExtractableText
        }
        var parts: [String] = []
        parts.reserveCapacity(document.pageCount)
        for i in 0..<document.pageCount {
            if let pageText = document.page(at: i)?.string {
                let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
            }
        }
        let text = parts.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KnowledgeError.noExtractableText
        }
        return text
    }

    /// Read a .txt / .md / text file, trying UTF-8 then common CJK encodings.
    static func extractText(fromTextFile url: URL) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let encodings: [String.Encoding] = [
            .utf8,
            .init(rawValue: 0x80000632), // kCFStringEncodingGB_18030_2000
            .init(rawValue: 0x80000421), // kCFStringEncodingBig5_HKSCS_1999
            .shiftJIS,
        ]
        for encoding in encodings {
            if let text = try? String(contentsOf: url, encoding: encoding),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        throw KnowledgeError.emptyText
    }

    /// Route by file extension: pdf → PDFKit, everything else → text read.
    static func extractText(from url: URL) throws -> String {
        if url.pathExtension.lowercased() == "pdf" {
            return try extractText(fromPDF: url)
        }
        return try extractText(fromTextFile: url)
    }
}
