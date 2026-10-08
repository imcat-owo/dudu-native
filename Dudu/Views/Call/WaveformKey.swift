import SwiftUI
import UIKit

// MARK: - Call waveform bars (live mic metering, not decoration)
//
// dB is negative; map -60..-10 → 0..1 (same mapping as the old Dudu's
// call-ui Waveform). Bars are driven by the REAL mic level — flat when
// she's quiet, dancing when she speaks.

struct CallWaveformBars: View {
    /// Live mic level in dB (-80..0).
    var levelDb: Float
    var barCount: Int = 24
    /// No default: DuduTheme is @MainActor — callers pass it explicitly from
    /// their ViewBuilder closure (where referencing it is fine).
    var color: Color
    var barHeight: CGFloat = 32

    var body: some View {
        let v = max(0, min(1, (Double(levelDb) + 60) / 50))
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                let wave = 0.35 + 0.65 * abs(sin(Double(i) * 0.7)) * v + 0.08
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: max(4, barHeight * min(1, wave)))
                    .opacity(0.35 + 0.65 * v)
            }
        }
        .frame(height: barHeight + 4)
        .accessibilityHidden(true)
    }
}

// MARK: - WaveformKey （波形键）
//
// Hold-to-talk key with a LIVE mic waveform inside. Press-and-hold forces
// a capture (interrupts the AI if speaking); release ends it and the turn
// is transcribed. Small, compact, refined — design tokens only.
//
// iOS 26: system Liquid Glass; older: ultraThinMaterial (same fallback the
// chat input bar uses — "iOS system material only, no custom blur overlays").

struct WaveformKey: View {
    /// Live mic level in dB (-80..0).
    var levelDb: Float
    /// When muted the mic is stopped — show the honest dimmed state.
    var muted: Bool = false
    var onHoldBegin: () -> Void = {}
    var onHoldEnd: () -> Void = {}

    @State private var isHeld = false

    var body: some View {
        ZStack {
            Circle()
                .fill(keyFill)
                .frame(width: 64, height: 64)
                .modifier(CallKeyGlass(isHeld: isHeld))
            if muted {
                DuduIcon(systemName: "mic.slash")
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            } else {
                CallWaveformBars(levelDb: levelDb, barCount: 14, color: DuduTheme.pink, barHeight: 26)
                    .frame(width: 44, height: 30)
            }
        }
        .scaleEffect(isHeld ? 1.08 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHeld)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isHeld else { return }
                    isHeld = true
                    HapticTap.light()
                    onHoldBegin()
                }
                .onEnded { _ in
                    guard isHeld else { return }
                    isHeld = false
                    onHoldEnd()
                }
        )
        .accessibilityLabel("按住说话")
        .accessibilityHint("按住开始说话，松开发送")
    }

    private var keyFill: Color {
        if isHeld { return DuduTheme.pink.opacity(0.55) }
        return DuduTheme.duduIconChip.opacity(0.35)
    }
}

/// Liquid Glass key background (iOS 26) with material fallback.
///
/// NOTE: CI currently builds with Xcode 16.4 (Swift 6.1), whose SDK has no
/// `glassEffect`. The Liquid Glass branch is gated on `#if compiler(>=6.2)`
/// (Xcode 26's Swift, which ships the iOS 26 SDK): it compiles out on the old
/// toolchain and lights up automatically when CI moves to Xcode 26.
/// `#available(iOS 26.0, *)` alone cannot do this — availability is runtime,
/// but the symbol must exist at compile time.
private struct CallKeyGlass: ViewModifier {
    var isHeld: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if isHeld {
                content.glassEffect(.regular.tint(DuduTheme.pink).interactive(), in: Circle())
            } else {
                content.glassEffect(.regular.interactive(), in: Circle())
            }
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
        #else
        content.background(.ultraThinMaterial, in: Circle())
        #endif
    }
}

/// Tiny haptic for the key press (UIKit-level, no extra dependency).
private enum HapticTap {
    static func light() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        gen.impactOccurred()
    }
}
