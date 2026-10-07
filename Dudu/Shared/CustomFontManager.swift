import Combine
import CoreText
import Foundation
import SwiftUI

/// Custom font upload engine (D12).
///
/// Old Dudu ("appearance.fontUpload") let her upload a ttf/otf/ttc in
/// Appearance → Font; the font lived OUTSIDE the theme bundle and missing
/// glyphs fell back to the system font. Same contract here, native:
///
/// - Picked file is copied into Application Support/dudu-fonts/ and
///   registered with CTFontManager (no entitlement needed).
/// - Choice persists in UserDefaults ({displayName, file, postScriptName});
///   the persisted font is re-registered at launch.
/// - `activePostScriptName` is what DuduTheme's font helpers use: when set,
///   UI text renders in the uploaded font (sizes still scale through the
///   existing FontSettings axes — upload changes the FAMILY, not the scale).
/// - `clear()` unregisters, deletes the file, and falls back to system.
@MainActor
final class CustomFontManager: ObservableObject {
    static let shared = CustomFontManager()

    @Published private(set) var displayName: String?
    @Published private(set) var postScriptName: String?

    /// PostScript family name to render with, or nil for the system font.
    var activePostScriptName: String? { postScriptName }
    var isCustomActive: Bool { postScriptName != nil }

    private enum Keys {
        static let file = "customFont.file.v1"
        static let displayName = "customFont.displayName.v1"
        static let postScript = "customFont.postScript.v1"
    }

    private init() {
        restorePersistedFont()
    }

    // MARK: - Directories

    private func fontsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("dudu-fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Import

    enum ImportError: LocalizedError {
        case notAFontFile
        case copyFailed
        case registrationFailed
        case noPostScriptName

        var errorDescription: String? {
            switch self {
            case .notAFontFile:
                return "不是字体文件。请选择 .ttf / .otf / .ttc 文件。"
            case .copyFailed:
                return "字体文件复制失败，请重试。"
            case .registrationFailed:
                return "字体注册失败，文件可能已损坏。"
            case .noPostScriptName:
                return "读取字体名称失败，文件可能已损坏。"
            }
        }
    }

    /// Copy + register a user-picked font file. Returns the display name.
    /// Throws ImportError with a human-readable message on failure.
    @discardableResult
    func importFont(from pickedURL: URL) throws -> String {
        let ext = pickedURL.pathExtension.lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext) else {
            throw ImportError.notAFontFile
        }
        let accessing = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessing { pickedURL.stopAccessingSecurityScopedResource() } }

        let dest = fontsDirectory().appendingPathComponent("custom.\(ext)")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: pickedURL, to: dest)
        } catch {
            throw ImportError.copyFailed
        }

        var cfError: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(dest as CFURL,
                                                          .process,
                                                          &cfError)
        guard registered else { throw ImportError.registrationFailed }
        guard let psName = postScriptName(for: dest) else {
            CTFontManagerUnregisterFontsForURL(dest as CFURL, .process, nil)
            try? FileManager.default.removeItem(at: dest)
            throw ImportError.noPostScriptName
        }

        let display = pickedURL.deletingPathExtension().lastPathComponent
        let ud = UserDefaults.standard
        ud.set(dest.lastPathComponent, forKey: Keys.file)
        ud.set(display, forKey: Keys.displayName)
        ud.set(psName, forKey: Keys.postScript)
        displayName = display
        postScriptName = psName
        return display
    }

    /// Drop the custom font and go back to the system font.
    func clear() {
        if let file = UserDefaults.standard.string(forKey: Keys.file) {
            let url = fontsDirectory().appendingPathComponent(file)
            CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
            try? FileManager.default.removeItem(at: url)
        }
        let ud = UserDefaults.standard
        ud.removeObject(forKey: Keys.file)
        ud.removeObject(forKey: Keys.displayName)
        ud.removeObject(forKey: Keys.postScript)
        displayName = nil
        postScriptName = nil
    }

    // MARK: - Private

    private func restorePersistedFont() {
        let ud = UserDefaults.standard
        guard let file = ud.string(forKey: Keys.file),
              let psName = ud.string(forKey: Keys.postScript),
              !file.isEmpty, !psName.isEmpty else { return }
        let url = fontsDirectory().appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // File is gone — drop the stale choice honestly.
            ud.removeObject(forKey: Keys.file)
            ud.removeObject(forKey: Keys.displayName)
            ud.removeObject(forKey: Keys.postScript)
            return
        }
        var cfError: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfError) {
            displayName = ud.string(forKey: Keys.displayName)
            postScriptName = psName
        }
    }

    private func postScriptName(for url: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String,
              !name.isEmpty else {
            return nil
        }
        return name
    }
}
