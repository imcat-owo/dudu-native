import SwiftUI

// MARK: - ThinkingIndicatorSlot
//
// The thinking-indicator SLOT: exact layout + animation-state contract.
//
// G1 — the black-cat artwork comes from the art pipeline and does NOT exist
// yet. Until the SVG lands, this slot renders a NEUTRAL marker (a rounded
// dot) so the layout contract stays verifiable. It is NOT a fake cat: no
// emoji, no SF Symbol cat, no code-drawn silhouette. The marker is clearly
// marked "awaiting cat SVG from art pipeline" in code and in accessibility.
//
// Layout contract (plan §7):
//   - 44pt square silhouette box; sits on the bubble's top edge (the parent
//     MessageRowView offsets it by -22pt so it straddles the edge).
//   - Three animation states driven by phase:
//       .waiting     — opening wait / between tool rounds: gentle pulse.
//       .toolRunning — a tool round is executing: vertical bounce.
//       .streaming   — tokens are arriving: steady dot.
//   - Visibility is NOT decided here: use phase(for:) which follows the
//     message's own per-round rule (ChatMessage.shouldShowTypingIndicator).

struct ThinkingIndicatorSlot: View {
    enum Phase {
        case waiting
        case toolRunning
        case streaming
    }

    /// Maps a ChatMessage to the slot's phase, or nil when the slot must be
    /// hidden. Visibility follows ChatMessage.shouldShowTypingIndicator —
    /// the per-round rule, not the view model's isProcessing.
    ///
    /// Per the engine rule the indicator never shows while a tool is
    /// actually running (the tool card animates its own state) nor while
    /// text is streaming into the bubble — .toolRunning / .streaming are
    /// contract states reserved for the final art pass.
    static func phase(for message: ChatMessage) -> Phase? {
        guard message.shouldShowTypingIndicator else { return nil }
        return .waiting
    }

    let phase: Phase

    @State private var animating = false

    var body: some View {
        ZStack {
            // AWAITING CAT SVG — art pipeline (G1). Neutral placeholder dot,
            // not the cat. Swap this ZStack content for the SVG asset when it
            // lands; the 44pt box and phase contract stay unchanged.
            Circle()
                .fill(DuduTheme.kitty)
                .frame(width: 13, height: 13)
                .scaleEffect(animating && phase == .waiting ? 1.28 : 1.0)
                .opacity(phase == .streaming ? 0.85 : 1.0)
                .offset(y: animating && phase == .toolRunning ? -5 : 0)
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("正在思考（猫咪插画待美术管线交付）")
        .onAppear {
            withAnimation(animation) {
                animating = true
            }
        }
    }

    private var animation: Animation {
        switch phase {
        case .waiting:
            return .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
        case .toolRunning:
            return .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
        case .streaming:
            return .default
        }
    }
}
