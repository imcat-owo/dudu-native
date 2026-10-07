//
//  P6 PORT (2026-10-07): ported from OpenMinis Agent/BrowserUse/BrowserWebView.swift — renames Minis->Dudu
//  (incl. mid-identifier), com.openminis.clone->com.dudu.ios, group ids,
//  minis->dudu prefixes (minis-clone://->dudu-clone://, minis-browser-use->dudu-browser-use,
//  /var/minis/->/var/dudu/); iCloud container refs dropped (no iCloud entitlement).
//  Real English words containing "minis" (deterministic*) untouched.
import SwiftUI
import WebKit

/// UIViewRepresentable wrapper that displays a `BrowserUseManager`'s WKWebView.
struct BrowserWebView: UIViewRepresentable {
    let manager: BrowserUseManager

    func makeUIView(context: Context) -> WKWebView {
        manager.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // The manager owns the webView — nothing to update here.
    }
}
