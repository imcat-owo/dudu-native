import SwiftUI
import UIKit

// MARK: - Solid tab icons (hand-drawn, Q萌 chunky — never SF Symbols)
//
// Each shape fills a unit box and is rendered at 18pt by the bar.
// Chunky rounded silhouettes to match the 嘟嘟定妆美术.

/// 我们 — chunky rounded heart.
struct TabBarHeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0.50 * w, y: 0.95 * h))
        p.addCurve(to: CGPoint(x: 0.08 * w, y: 0.58 * h),
                   control1: CGPoint(x: 0.30 * w, y: 0.82 * h),
                   control2: CGPoint(x: 0.05 * w, y: 0.72 * h))
        p.addCurve(to: CGPoint(x: 0.26 * w, y: 0.10 * h),
                   control1: CGPoint(x: 0.02 * w, y: 0.42 * h),
                   control2: CGPoint(x: 0.08 * w, y: 0.16 * h))
        p.addCurve(to: CGPoint(x: 0.50 * w, y: 0.32 * h),
                   control1: CGPoint(x: 0.36 * w, y: 0.08 * h),
                   control2: CGPoint(x: 0.44 * w, y: 0.16 * h))
        p.addCurve(to: CGPoint(x: 0.74 * w, y: 0.10 * h),
                   control1: CGPoint(x: 0.56 * w, y: 0.16 * h),
                   control2: CGPoint(x: 0.64 * w, y: 0.08 * h))
        p.addCurve(to: CGPoint(x: 0.92 * w, y: 0.58 * h),
                   control1: CGPoint(x: 0.92 * w, y: 0.16 * h),
                   control2: CGPoint(x: 0.98 * w, y: 0.42 * h))
        p.addCurve(to: CGPoint(x: 0.50 * w, y: 0.95 * h),
                   control1: CGPoint(x: 0.95 * w, y: 0.72 * h),
                   control2: CGPoint(x: 0.70 * w, y: 0.82 * h))
        p.closeSubpath()
        return p
    }
}

/// 对话 — chunky speech bubble with a soft tail.
struct TabBarChatShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = 0.30 * w
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 0.05 * w, y: 0.06 * h, width: 0.90 * w, height: 0.64 * h),
                         cornerSize: CGSize(width: r, height: r))
        p.move(to: CGPoint(x: 0.34 * w, y: 0.66 * h))
        p.addLine(to: CGPoint(x: 0.24 * w, y: 0.95 * h))
        p.addCurve(to: CGPoint(x: 0.52 * w, y: 0.68 * h),
                   control1: CGPoint(x: 0.33 * w, y: 0.88 * h),
                   control2: CGPoint(x: 0.40 * w, y: 0.80 * h))
        p.closeSubpath()
        return p
    }
}

/// 资料 — chunky open book (two rounded pages).
struct TabBarBookShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Left page.
        p.move(to: CGPoint(x: 0.50 * w, y: 0.30 * h))
        p.addCurve(to: CGPoint(x: 0.10 * w, y: 0.22 * h),
                   control1: CGPoint(x: 0.36 * w, y: 0.24 * h),
                   control2: CGPoint(x: 0.22 * w, y: 0.20 * h))
        p.addLine(to: CGPoint(x: 0.10 * w, y: 0.72 * h))
        p.addCurve(to: CGPoint(x: 0.50 * w, y: 0.80 * h),
                   control1: CGPoint(x: 0.22 * w, y: 0.70 * h),
                   control2: CGPoint(x: 0.36 * w, y: 0.74 * h))
        p.closeSubpath()
        // Right page (mirror).
        p.move(to: CGPoint(x: 0.50 * w, y: 0.30 * h))
        p.addCurve(to: CGPoint(x: 0.90 * w, y: 0.22 * h),
                   control1: CGPoint(x: 0.64 * w, y: 0.24 * h),
                   control2: CGPoint(x: 0.78 * w, y: 0.20 * h))
        p.addLine(to: CGPoint(x: 0.90 * w, y: 0.72 * h))
        p.addCurve(to: CGPoint(x: 0.50 * w, y: 0.80 * h),
                   control1: CGPoint(x: 0.78 * w, y: 0.70 * h),
                   control2: CGPoint(x: 0.64 * w, y: 0.74 * h))
        p.closeSubpath()
        return p
    }
}

/// 更多 — three solid dots.
struct TabBarDotsShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let d = 0.28 * min(w, h)
        var p = Path()
        for i in 0..<3 {
            let cx = w * (0.16 + 0.34 * CGFloat(i))
            p.addEllipse(in: CGRect(x: cx - d / 2, y: (h - d) / 2, width: d, height: d))
        }
        return p
    }
}

/// Resolves a tab to its solid icon shape.
struct TabBarIcon: View {
    let tab: DuduTab

    @ViewBuilder
    var body: some View {
        switch tab {
        case .ourSpace: TabBarHeartShape()
        case .chat: TabBarChatShape()
        case .library: TabBarBookShape()
        case .more: TabBarDotsShape()
        }
    }
}

// MARK: - Floating glass tab bar

private extension View {
    /// iOS native Liquid Glass on toolchains that have the iOS 26 SDK,
    /// `.ultraThinMaterial` fallback on older ones (CI runs Xcode 16.4 —
    /// the `glassEffect` symbol does not exist there, so a plain
    /// availability check would fail the build).
    ///
    /// The native glass material carries the blur itself; no manual
    /// `.blur` overlay is applied on top of the icons/labels.
    @ViewBuilder
    func floatingBarGlass(cornerRadius: CGFloat) -> some View {
        #if compiler(>=6.2)
        self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        #else
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        #endif
    }
}

/// Custom floating tab bar (html-2 定稿): 59pt high, 22pt corner radius,
/// 12pt side margins (applied by the parent), 10pt above the safe area
/// (applied by the parent). Selected tab: pink text on a light-pink
/// rounded block; unselected: dim text. Light haptic on tap.
struct DuduTabBar: View {
    @Binding var selection: DuduTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DuduTab.barOrder) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 59)
        .frame(maxWidth: .infinity)
        .floatingBarGlass(cornerRadius: 22)
    }

    @ViewBuilder
    private func tabButton(_ tab: DuduTab) -> some View {
        let isSelected = (tab == selection)
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                TabBarIcon(tab: tab)
                    .frame(width: 18, height: 18)
                Text(tab.title)
                    .font(DuduTheme.captionFont(weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? DuduTheme.pink : DuduTheme.duduTextDim)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 17)
                        .fill(DuduTheme.pinkSoft)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
