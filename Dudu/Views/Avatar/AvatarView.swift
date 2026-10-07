import AVFoundation
import SwiftUI
import UIKit

// MARK: - [D18-avatar] AvatarView
//
// SwiftUI wrapper around AvatarEmotionEngine — the AI avatar shown on
// assistant message rows. Shows the looping / one-shot clip for the current
// emotion state via an AVPlayerLayer-backed UIViewRepresentable; falls back
// to the static avatar when a state has no clip (honest degradation —
// sora-avatar.webp, then the pre-D18 sparkles chip; never blank).
//
// Lifecycle: attachViewer on appear, detachViewer on disappear (refcounted
// in the engine — the last viewer out releases the player item + looper, so
// nothing plays unseen and memory stays sane with many rows mounted).
// Background/foreground via scenePhase → engine pause/resume. Both are
// idempotent, so every mounted row can call them safely.
//
// DuduTheme refs stay inside the body DSL (the proven-safe shape per the
// D16 @MainActor isolation lesson). Zero emoji, zero hardcoded colors.
struct AvatarView: View {
    @ObservedObject private var engine = AvatarEmotionEngine.shared
    @Environment(\.scenePhase) private var scenePhase

    let size: CGFloat

    var body: some View {
        ZStack {
            if engine.currentClipURL != nil {
                AvatarPlayerLayerView(player: engine.player)
            } else {
                // Static fallback chain: sora-avatar.webp → sparkles chip.
                ZStack {
                    Circle()
                        .fill(DuduTheme.duduIconChip)
                    if let image = engine.staticAvatarImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "sparkles")
                            .font(DuduTheme.captionFont(weight: .medium))
                            .foregroundStyle(DuduTheme.pink)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onAppear { engine.attachViewer() }
        .onDisappear { engine.detachViewer() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                engine.pausePlayback()
            case .active:
                engine.resumePlayback()
            default:
                break
            }
        }
    }
}

// MARK: - AVPlayerLayer representable

/// Thin AVPlayerLayer host. The engine owns the single AVPlayer; this view
/// only binds it to a layer (aspectFill, clipped to the circle by the parent).
private struct AvatarPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> AvatarPlayerUIView {
        let view = AvatarPlayerUIView()
        view.bind(player: player)
        return view
    }

    func updateUIView(_ uiView: AvatarPlayerUIView, context: Context) {
        uiView.bind(player: player)
    }
}

private final class AvatarPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    /// Safe: layerClass guarantees the layer type.
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    func bind(player: AVPlayer?) {
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
    }
}
