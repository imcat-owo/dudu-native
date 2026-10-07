import AVFoundation
import Foundation
import UIKit

// MARK: - [D18-avatar] AvatarEmotionEngine
//
// @MainActor state machine driving the AI avatar's animated clips.
// Ported 1:1 from ~/workspace/openmuse/apps/mobile/src/pet/buddy-video-states.ts
// (her 13 approved buddy states). States are NEVER invented — the enum below
// is exactly her list: 6 task + 4 interaction + 3 environment.
//
//   state → clip file → trigger → next state (one-shot vs loop)
//
// Triggers (per avatar-clip-pipeline-20261005.md §一.3):
//   - chat engine: setEmotion(_:source:) — reply emotion classification.
//     Today the chat engine drives it from agent-loop activity + error signal
//     (see the [D18-avatar] hook in AIChatViewModel.isProcessing.didSet);
//     a real reply-emotion classifier plugs into the same API later.
//   - her mood: noteHerMood(_:) — OurSpaceStore.setHerMood hook.
//   - gestures: petDrag / petHeadpat / petReach are gesture-driven
//     (double-tap = 摸头, long-press = 伸手, drag = 拎起来).
//
// One-shot states (sit down, stand up) play once, then auto-transition to
// their exit state. Gesture states remember the state they interrupted and
// endGesture() returns to it (松手→回到之前的状态).
//
// Honest degradation (her iron rule: 素材缺了就问她要，不许 AI 自己生成凑数):
// every registered clip is validated against the bundle at init. A state
// whose file is missing degrades to the static avatar (sora-avatar.webp,
// the theme anchor) and is recorded in missingClipFiles. Never a crash,
// never a blank frame, never a synthesized video.
//
// Playback: one AVPlayer instance, seamless loops via AVPlayerLooper,
// one-shots via .AVPlayerItemDidPlayToEndTime → exit state. The player is
// muted — a chat avatar must never make unexpected noise. Views call
// attachViewer()/detachViewer(); when the last viewer leaves, the item and
// looper are released.
@MainActor
final class AvatarEmotionEngine: ObservableObject {

    static let shared = AvatarEmotionEngine()

    // MARK: States (her 13, verbatim — do not invent)

    /// The 13 buddy states from buddy-video-states.ts. Raw values are the
    /// original TS names, used in logs.
    enum AvatarState: String, CaseIterable {
        case taskRunning   = "task_running"    // 跑循环：任务进行中
        case taskStuckSit  = "task_stuck_sit"  // 坐下（一次）：任务卡住
        case taskStuckIdle = "task_stuck_idle" // 坐着晃（循环）：卡住干等
        case taskResumed   = "task_resumed"    // 起身（一次）：任务恢复
        case taskUnhappy   = "task_unhappy"    // 不开心（循环）：任务失败/出错
        case taskDone      = "task_done"       // 完成（循环）：任务做完
        case petDrag       = "pet_drag"        // 拖动（循环）：拎后衣领提溜
        case petHeadpat    = "pet_headpat"     // 摸头（循环）：双击=正面蹭手指
        case petHeadphones = "pet_headphones"  // 戴耳机（循环）：听歌房
        case petReach      = "pet_reach"       // 伸手（循环）：长按=贴住手指
        case petWaiting    = "pet_waiting"     // 等待（循环）：默认空状态
        case petDJ         = "pet_dj"          // 打碟（循环）：DJ 模式
        case petReading    = "pet_reading"     // 读书（循环）：知识库空状态
    }

    /// Who asked for the transition (for logs and future priority rules).
    enum TriggerSource: String {
        case chatEngine
        case herMood
        case gesture
        case system
    }

    // MARK: State → clip file (BUDDY_STATE_VIDEO, artwork/avatar-anim/v2/)

    /// NOTE on taskRunning: the TS spec names "run_loop_final.mp4", but that
    /// file does not exist in the repo. The real artifact with the same stem
    /// is "run_loop_final_20261004.mp4" — bundled as-is, NOT renamed, NOT
    /// regenerated. Per v2/STATUS.md the run loop was never approved by her
    /// (停/待她定), so this mapping is honest-but-pending: if she rejects the
    /// clip, remove the file and this state degrades to the static avatar.
    private static let clipFile: [AvatarState: String] = [
        .taskRunning: "run_loop_final_20261004.mp4",
        .taskStuckSit: "sit_down.mp4",
        .taskStuckIdle: "sit_idle_loop.mp4",
        .taskResumed: "stand_up.mp4",
        .taskUnhappy: "unhappy_loop.mp4",
        .taskDone: "victory_loop.mp4",
        .petDrag: "cheek_pull_loop.mp4",
        .petHeadpat: "head_pat.mp4",
        .petHeadphones: "headphone_loop.mp4",
        .petReach: "reach_out_loop.mp4",
        .petWaiting: "waiting_loop.mp4",
        .petDJ: "dj_loop.mp4",
        .petReading: "reading_loop.mp4",
    ]

    /// One-shot states (BUDDY_ONE_SHOTS): play once, then exit.
    private static let oneShots: Set<AvatarState> = [.taskStuckSit, .taskResumed]

    /// Where one-shots go when they finish (BUDDY_EXIT_STATE).
    /// Gesture states return to the interrupted state via endGesture().
    private static func exitState(for state: AvatarState) -> AvatarState? {
        switch state {
        case .taskStuckSit: return .taskStuckIdle
        case .taskResumed: return .taskRunning
        case .taskDone: return .petWaiting
        default: return nil
        }
    }

    /// States driven by her gestures; entering one remembers the state it
    /// interrupted so 松手 can return to it.
    private static let gestureStates: Set<AvatarState> = [.petDrag, .petHeadpat, .petReach]

    // MARK: Published state

    /// Current state. Views observe this (and currentClipURL) for live updates.
    @Published private(set) var currentState: AvatarState = .petWaiting
    /// Bundle URL of the clip for currentState, or nil → show static avatar.
    @Published private(set) var currentClipURL: URL?
    /// Static fallback image (sora-avatar.webp). Nil → SF symbol fallback.
    @Published private(set) var staticAvatarImage: UIImage?
    /// Honest gap report: registered clip files missing from the bundle.
    /// Empty in a healthy build; surfaced for diagnostics, never faked.
    @Published private(set) var missingClipFiles: [String] = []

    // MARK: Playback

    /// The single player instance. Muted — the avatar never makes noise.
    /// AVQueuePlayer (not AVPlayer): AVPlayerLooper requires a queue player.
    private(set) var player: AVQueuePlayer = {
        let p = AVQueuePlayer()
        p.isMuted = true
        return p
    }()

    private var looper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var viewers = 0
    private var suspendedForBackground = false
    private var interruptedState: AvatarState?
    /// Her-mood overlay: when idle, show this instead of plain waiting.
    private var herMoodState: AvatarState?
    /// True while the currently shown state comes from her mood (so a later
    /// mood change/clear knows to settle back to idle).
    private var moodDriven = false

    private let logger = AppLogger(category: "AvatarEmotion")

    private init() {
        validateClips()
        loadStaticAvatar()
        currentClipURL = Self.resolveURL(for: .petWaiting)
        if currentClipURL == nil {
            logger.warning("[D18] default waiting clip missing — avatar starts static")
        }
    }

    // NOTE: no deinit — deinit is nonisolated in this codebase (see
    // AIChatViewModel) and must not touch @MainActor state. The end observer
    // is removed by teardownItem() on every rebind and on detachViewer(),
    // and the engine is a singleton that lives for the app's lifetime.

    // MARK: Public API — chat engine

    /// The chat engine's entry point (reply emotion classification, loop
    /// activity, error signal). Same-state calls are no-ops.
    func setEmotion(_ state: AvatarState, source: TriggerSource = .chatEngine) {
        var target = state
        if target == .petWaiting, let mood = herMoodState, mood != .petWaiting {
            target = mood
        }
        guard target != currentState else { return }
        if Self.gestureStates.contains(target),
           !Self.gestureStates.contains(currentState) {
            interruptedState = currentState
        }
        logger.debug("[D18] \(currentState.rawValue) → \(target.rawValue) (source: \(source.rawValue))")
        transition(to: target)
    }

    /// Gesture released (松手): return to the state the gesture interrupted.
    func endGesture() {
        let back = interruptedState ?? herMoodState ?? .petWaiting
        interruptedState = nil
        guard back != currentState else { return }
        logger.debug("[D18] gesture ended → \(back.rawValue)")
        transition(to: back)
    }

    // MARK: Public API — her mood hook

    /// OurSpaceStore.setHerMood hook. Maps her free-text mood to an avatar
    /// state with a tiny explicit keyword heuristic — a hook, not
    /// intelligence. Unknown or tied moods change nothing (honest: no fake
    /// emotion reading). Applies when the avatar is idle.
    func noteHerMood(_ mood: HerMood) {
        let text = mood.mood + mood.note
        let neg = Self.moodNegativeHints.filter { text.contains($0) }.count
        let pos = Self.moodPositiveHints.filter { text.contains($0) }.count
        let derived: AvatarState?
        if neg > pos {
            derived = .taskUnhappy
        } else if pos > neg {
            derived = .taskDone
        } else {
            derived = nil
        }
        herMoodState = derived
        logger.debug("[D18] her-mood noted → \(derived?.rawValue ?? "none")")
        // Only touch the visible state when idle or when the visible state
        // is itself mood-driven. While the agent loop runs (taskRunning /
        // taskStuck…), her mood is recorded and applies at the next idle.
        if currentState == .petWaiting || moodDriven {
            setEmotion(.petWaiting, source: .herMood)
        }
    }

    // MARK: View lifecycle

    /// A view started showing the avatar. First viewer binds + plays.
    func attachViewer() {
        viewers += 1
        if viewers == 1 {
            bindCurrentItem()
        }
    }

    /// A view stopped showing the avatar. Last viewer out releases the
    /// item and looper (memory-sane: nothing plays unseen).
    func detachViewer() {
        viewers = max(0, viewers - 1)
        if viewers == 0 {
            suspendedForBackground = false
            teardownItem()
        }
    }

    /// App went to background: pause, keep the item so resume is instant.
    /// Idempotent — safe to call from every mounted AvatarView.
    func pausePlayback() {
        guard viewers > 0, !suspendedForBackground else { return }
        suspendedForBackground = true
        player.pause()
    }

    /// App back to foreground: resume where we paused.
    /// Idempotent — safe to call from every mounted AvatarView.
    func resumePlayback() {
        guard viewers > 0, suspendedForBackground else { return }
        suspendedForBackground = false
        if player.currentItem == nil {
            bindCurrentItem()
        } else {
            player.play()
        }
    }

    // MARK: Transitions

    private func transition(to state: AvatarState) {
        moodDriven = (state != .petWaiting && state == herMoodState)
        currentState = state
        currentClipURL = Self.resolveURL(for: state)
        if currentClipURL == nil {
            logger.warning("[D18] clip missing for \(state.rawValue) — static fallback")
        }
        bindCurrentItem()
    }

    private func bindCurrentItem() {
        teardownItem()
        guard viewers > 0 else { return }
        guard let url = currentClipURL else { return } // static avatar shows; nothing to play
        let item = AVPlayerItem(url: url)
        if Self.oneShots.contains(currentState) {
            player.replaceCurrentItem(with: item)
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.oneShotDidFinish() }
            }
        } else {
            // AVPlayerLooper takes over the player's item for seamless loops.
            looper = AVPlayerLooper(player: player, templateItem: item)
        }
        if !suspendedForBackground {
            player.play()
        }
    }

    private func oneShotDidFinish() {
        guard Self.oneShots.contains(currentState) else { return }
        let next = Self.exitState(for: currentState) ?? .petWaiting
        logger.debug("[D18] one-shot \(currentState.rawValue) finished → \(next.rawValue)")
        // Route through setEmotion so gesture/her-mood bookkeeping applies.
        setEmotion(next, source: .system)
    }

    private func teardownItem() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        looper = nil
        player.replaceCurrentItem(with: nil)
    }

    // MARK: Clip validation (startup)

    /// Assert every registered clip exists in the bundle. Missing files are
    /// logged and recorded in missingClipFiles — the state degrades to the
    /// static avatar. Never crashes, never blanks.
    private func validateClips() {
        var missing: [String] = []
        for state in AvatarState.allCases {
            guard let file = Self.clipFile[state] else {
                missing.append("\(state.rawValue):<no mapping>")
                continue
            }
            if Self.resolveURL(for: state) == nil {
                missing.append(file)
            }
        }
        missingClipFiles = missing
        if missing.isEmpty {
            logger.info("[D18] clip validation OK — 13/13 states have bundle clips")
        } else {
            logger.warning("[D18] clip validation: missing \(missing.count) file(s): \(missing.joined(separator: ", "))")
        }
    }

    private static func resolveURL(for state: AvatarState) -> URL? {
        guard let file = clipFile[state] else { return nil }
        let name = (file as NSString).deletingPathExtension
        // Resource build entries land flattened at the bundle root; also try
        // the AvatarClips subfolder in case packaging ever uses folder refs.
        if let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "AvatarClips")
    }

    private func loadStaticAvatar() {
        let url = Bundle.main.url(forResource: "sora-avatar", withExtension: "webp")
            ?? Bundle.main.url(forResource: "sora-avatar", withExtension: "webp", subdirectory: "AvatarClips")
        guard let url, let data = try? Data(contentsOf: url) else {
            logger.warning("[D18] sora-avatar.webp not in bundle — static fallback is SF symbol")
            return
        }
        staticAvatarImage = UIImage(data: data)
        if staticAvatarImage == nil {
            logger.warning("[D18] sora-avatar.webp failed to decode — static fallback is SF symbol")
        }
    }

    // MARK: Her-mood keyword hints (explicit, documented — see noteHerMood)

    private static let moodNegativeHints = [
        "不开心", "难过", "生气", "委屈", "哭", "烦", "疲惫", "沮丧",
        "焦虑", "低落", "伤心", "emo", "不爽",
    ]
    private static let moodPositiveHints = [
        "开心", "高兴", "哈哈", "嘿嘿", "幸福", "满足", "兴奋", "期待",
    ]
}
