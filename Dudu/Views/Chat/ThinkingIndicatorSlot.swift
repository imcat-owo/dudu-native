import SwiftUI

// MARK: - ThinkingIndicatorSlot
//
// The thinking-indicator SLOT: exact layout + animation-state contract,
// now hosting the real black-cat artwork (BlackCatView, Wave 2 Item 1).
//
// Layout contract (approved design spec — replaces the old plan-§7 straddle):
//   - 44pt square silhouette box; the parent MessageRowView offsets it by
//     (+8, -40), so the box's left edge sits 8pt inside the bubble's left
//     edge and its bottom (paws) sits 4pt below the bubble's top edge.
//   - The parent also reserves 29pt of top margin while the cat shows,
//     because the overlay takes no layout space and the box extends 40pt
//     above the bubble (message rows are only 6pt apart).
//   - The cat draws at 46x46pt; the whole cat is a Button with a 52x48pt
//     hit area, centered in the 44pt box (the overflow is intentional and
//     never clipped).
//   - Visibility is NOT decided here: use phase(for:), which follows the
//     message's own per-round engine state. The cat never shows while text
//     streams into the bubble.
//
// Phases — the old .waiting/.toolRunning/.streaming contract is kept and
// extended with .finished:
//   .waiting     — awaiting the model's response (opening wait / between
//                  tool rounds): the cat's gentle "thinking" bob.
//   .toolRunning — a tool round is executing on this message: fast tail wag
//                  + ear twitch. (Previously a reserved contract state; now
//                  wired to the real engine state.)
//   .streaming   — reserved: the drawer's live-thinking mini slot.
//   .finished    — one-shot stretch-squash played ONCE when the turn ends,
//                  then the cat hides. Driven by the parent (MessageRowView),
//                  not by phase(for:).

struct ThinkingIndicatorSlot: View {
    enum Phase {
        case waiting
        case toolRunning
        case streaming
        case finished
    }

    /// Maps a ChatMessage to the slot's phase, or nil when the slot must be
    /// hidden. A running tool round takes precedence: while a tool executes,
    /// the cat shows the "tool" motion on the bubble (the engine's own
    /// shouldShowTypingIndicator stays false then, so the order matters).
    static func phase(for message: ChatMessage) -> Phase? {
        if hasRunningTool(message) { return .toolRunning }
        guard message.shouldShowTypingIndicator else { return nil }
        return .waiting
    }

    /// How tool-card state is tracked on the message: any block whose
    /// toolStatus is still .streaming/.running — the same predicate the
    /// engine uses inside shouldShowTypingIndicator.
    private static func hasRunningTool(_ message: ChatMessage) -> Bool {
        message.blocks.contains { block in
            switch block.toolStatus {
            case .streaming, .running: return true
            default: return false
            }
        }
    }

    let phase: Phase
    /// The message's thinking block, if any. 620ms after a tap the slot
    /// opens it in ThinkingDrawerView; nil means the tap only plays the
    /// tap animation.
    var thinkingBlock: AssistantBlock?
    /// Whether the drawer block belongs to the live, still-streaming turn.
    var isLiveBlock: Bool = false

    @State private var tapNonce = 0
    @State private var pressed = false
    @State private var drawerBlock: AssistantBlock?

    private var catMode: BlackCatMode {
        switch phase {
        case .waiting, .streaming: return .thinking
        case .toolRunning: return .tool
        case .finished: return .finished
        }
    }

    private var label: String {
        switch phase {
        case .waiting, .streaming:
            return "小黑猫正在慢慢摇尾巴，打开思考与工具"
        case .toolRunning:
            return "小黑猫正在快速摇尾巴和抖耳朵，打开思考与工具"
        case .finished:
            return "小黑猫回完消息正在伸懒腰"
        }
    }

    var body: some View {
        ZStack {
            Button {
                tapNonce += 1
                guard thinkingBlock != nil else { return }
                // The tap animation runs 0.62s; the drawer opens as it lands.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
                    drawerBlock = thinkingBlock
                }
            } label: {
                BlackCatView(mode: catMode, tapNonce: tapNonce, pressed: pressed)
                    .frame(width: 52, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CatPressButtonStyle(pressed: $pressed))
            .accessibilityLabel(label)
            // Custom bottom drawer (Wave 2 Item 9): presented as an overlay,
            // not a system sheet.
            .overlay {
                if let block = drawerBlock {
                    ThinkingDrawerOverlay(block: block, isLive: isLiveBlock) {
                        drawerBlock = nil
                    }
                }
            }
        }
        .frame(width: 44, height: 44)
    }
}
