import SwiftUI

// MARK: - BlackCatView
//
// The black-cat thinking indicator (approved design, Wave 2 Item 1).
//
// - 7 solid shapes from the spec's SVG paths (viewBox "0 0 64 58"), drawn at
//   46x46pt. Back view, NO face, NO strokes — solid fills only.
// - Ink: DuduTheme.kittyInk (dynamic #171518 / #09090b, follows the system
//   appearance via the DuduTheme adaptive token pattern, never hardcoded).
// - Tail and ears rotate around the spec's transform origins, converted to
//   each part's own-bounds anchor: tail 10%/55%, ear-left 72%/88%,
//   ear-right 28%/88%, whole cat 50%/90%.
//
// Animation model: the parent (ThinkingIndicatorSlot / PeekCatHost) passes a
// mode; every motion program runs in a .task keyed on (mode, tapNonce), so a
// mode change or a tap cleanly cancels the previous program and starts the
// right one. The tap program always falls through to the mode program, so
// the infinite loops resume on their own — no reset bookkeeping needed.

/// Which motion program the cat runs. Tap is NOT a mode: it is layered on
/// top of the current mode via tapNonce.
enum BlackCatMode: Hashable {
    case thinking
    case tool
    case finished
    case peeking

    /// Rest angle of the tail per mode (spec: the 0%/100% keyframe value).
    var tailRest: Double {
        switch self {
        case .thinking: return -8
        case .tool: return -15
        case .finished: return -15
        case .peeking: return -6
        }
    }
}

/// Whole-cat transform for one keyframe step.
private struct CatPose {
    var offset = CGSize.zero
    var rotation = 0.0 // degrees
    var scale = CGSize(width: 1, height: 1)
    var opacity = 1.0

    static let identity = CatPose()
}

struct BlackCatView: View {
    let mode: BlackCatMode
    var tapNonce: Int = 0
    var pressed: Bool = false

    // MARK: - Spec constants

    private static let iconSize: CGFloat = 46
    private static let kScale = iconSize / 64.0
    private static let canvasH = 58.0 * kScale // 41.6875

    // Exact path d strings from the approved design.
    private static let tailD =
        "M44.5 39c8.7-3.8 15.8-.1 15.8 7 0 6.4-6.3 10.1-12 7.6-3-1.3-3.6-4.8-1.2-6.3 1.8-1.1 3.3.5 5.2.9 2.2.4 3.8-.9 3.4-2.7-.5-2.3-4.3-2.5-9-.2Z"
    private static let bodyD =
        "M18.2 29.4c-3.1 4.7-4.2 11.3-2.8 17.5 1.2 5.3 5.6 8.4 11.1 8.4h11c5.8 0 10.3-3.2 11.2-8.5 1.1-6.2-.2-12.7-3.1-17.4Z"
    private static let earLD =
        "M16 26.8c-1.1-6.8-.1-14.2 2.6-20.3.4-.9 1.5-1.1 2.3-.4l8.3 7.7Z"
    private static let earRD =
        "M48 26.8c1.1-6.8.1-14.2-2.6-20.3-.4-.9-1.5-1.1-2.3-.4l-8.3 7.7Z"
    private static let headD =
        "M15.4 27.2c0-9.3 6.6-15.6 16.6-15.6s16.6 6.3 16.6 15.6c0 9.4-6.6 15.1-16.6 15.1s-16.6-5.7-16.6-15.1Z"

    private static func scaledPath(_ d: String) -> (path: Path, box: CGRect) {
        var t = CGAffineTransform(scaleX: kScale, y: kScale)
        let cg = SVGPathParser.parse(d).copy(using: &t) ?? SVGPathParser.parse(d)
        // Slightly expanded box: never clip a curve, anchor math stays exact.
        let box = cg.boundingBox.insetBy(dx: -0.5, dy: -0.5)
        return (Path(cg), box)
    }

    private static let tail = scaledPath(tailD)
    private static let torso = scaledPath(bodyD)
    private static let earL = scaledPath(earLD)
    private static let earR = scaledPath(earRD)
    private static let head = scaledPath(headD)

    private static let pawLBox = CGRect(
        x: (18.2 - 7.2) * kScale, y: (49.1 - 5.8) * kScale,
        width: 14.4 * kScale, height: 11.6 * kScale
    )
    private static let pawRBox = CGRect(
        x: (45.8 - 7.2) * kScale, y: (49.1 - 5.8) * kScale,
        width: 14.4 * kScale, height: 11.6 * kScale
    )

    /// SVG drop shadow: (0, 5px, 7px, rgba(107,71,78,0.12)) — fixed design value.
    private static let dropShadow = Color(
        red: 107 / 255, green: 71 / 255, blue: 78 / 255, opacity: 0.12
    )

    // MARK: - State

    @State private var bodyPose: CatPose
    @State private var tailAngle: Double
    @State private var earLeftAngle = 0.0
    @State private var earRightAngle = 0.0

    init(mode: BlackCatMode, tapNonce: Int = 0, pressed: Bool = false) {
        self.mode = mode
        self.tapNonce = tapNonce
        self.pressed = pressed
        // Peeking starts sunk and invisible (its 0% keyframe); everything
        // else starts at the identity pose.
        _bodyPose = State(initialValue: mode == .peeking
            ? CatPose(offset: CGSize(width: 0, height: 28), opacity: 0)
            : CatPose.identity)
        _tailAngle = State(initialValue: mode.tailRest)
    }

    private struct ProgramID: Hashable {
        let mode: BlackCatMode
        let tap: Int
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            ellipseShadow
            catCanvas
                .modifier(PoseEffect(pose: bodyPose))
                // Drop shadow on the container OUTSIDE the pose transform:
                // during the finished 340-degree roll the shadow stays
                // grounded instead of orbiting with the cat.
                .shadow(color: Self.dropShadow, radius: 7, x: 0, y: 5)
                .scaleEffect(pressed ? 0.94 : 1, anchor: .center)
                .offset(y: pressed ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: pressed)
        }
        .frame(width: Self.iconSize, height: Self.iconSize)
        .task(id: ProgramID(mode: mode, tap: tapNonce)) { await runBodyProgram() }
        .task(id: ProgramID(mode: mode, tap: tapNonce)) { await runTailProgram() }
        .task(id: mode) { await twitchEar(left: true, delayMs: 0) }
        .task(id: mode) { await twitchEar(left: false, delayMs: 100) }
    }

    /// Soft ellipse shadow under the cat: inset 10pt each side, bottom 2pt,
    /// height 7pt, blur 4, rgba(105,75,72,0.12). Press state: scaleX .96,
    /// opacity .65.
    private var ellipseShadow: some View {
        Ellipse()
            .fill(DuduTheme.catShadow)
            .frame(width: Self.iconSize - 20, height: 7)
            .blur(radius: 4)
            .offset(y: Self.iconSize / 2 - 2 - 3.5)
            .scaleEffect(x: pressed ? 0.96 : 1, anchor: .center)
            .opacity(pressed ? 0.65 : 1)
            .animation(.easeOut(duration: 0.15), value: pressed)
    }

    /// The 7 shapes in spec order: tail, paws, body, ears, head.
    private var catCanvas: some View {
        ZStack {
            part(Self.tail, anchor: UnitPoint(x: 0.10, y: 0.55), angle: tailAngle)
            part((path: Path(ellipseIn: Self.pawLBox), box: Self.pawLBox))
            part((path: Path(ellipseIn: Self.pawRBox), box: Self.pawRBox))
            part(Self.torso)
            part(Self.earL, anchor: UnitPoint(x: 0.72, y: 0.88), angle: earLeftAngle)
            part(Self.earR, anchor: UnitPoint(x: 0.28, y: 0.88), angle: earRightAngle)
            part(Self.head)
        }
        .frame(width: Self.iconSize, height: Self.canvasH)
    }

    /// One shape, framed to its own bounds so the rotation anchor is exact,
    /// then positioned on the 46x41.7 canvas.
    private func part(
        _ part: (path: Path, box: CGRect),
        anchor: UnitPoint = .center,
        angle: Double = 0
    ) -> some View {
        CatPartShape(path: part.path, box: part.box)
            .fill(DuduTheme.kittyInk)
            .frame(width: part.box.width, height: part.box.height)
            .rotationEffect(.degrees(angle), anchor: anchor)
            .offset(x: part.box.midX - Self.iconSize / 2,
                    y: part.box.midY - Self.canvasH / 2)
    }

    // MARK: - Motion programs

    /// Sleep that returns false when the task was cancelled.
    private func nap(_ ms: Int) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(ms))
        } catch {
            return false
        }
        return !Task.isCancelled
    }

    private func runBodyProgram() async {
        if tapNonce > 0 { await playTapBody() }
        // .finished is a one-shot: a tap during it plays the wiggle above
        // but must NEVER restart the 1.9s sequence.
        if mode == .finished, tapNonce > 0 { return }
        switch mode {
        case .thinking: await thinkBob()
        case .tool: await toolBob()
        case .finished: await finishedSequence()
        case .peeking: await peekingSequence()
        }
    }

    private func runTailProgram() async {
        if tapNonce > 0 {
            // Tap: two hard wags, absolute angles per spec.
            await wagTailCounted(rest: -18, peak: 24, halfMs: 140, times: 2)
        }
        switch mode {
        case .thinking:
            await wagTailForever(rest: -8, peak: 10, halfMs: 1350,
                                 curve: .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 1.35))
        case .tool:
            await wagTailForever(rest: -15, peak: 18, halfMs: 210,
                                 curve: .easeInOut(duration: 0.21))
        case .finished:
            await wagTailCounted(rest: -15, peak: 19, halfMs: 170, times: 3)
        case .peeking:
            await wagTailCounted(rest: -6, peak: 8, halfMs: 550, times: 2)
        }
    }

    // thinking: body 4.2s ease (cubic-bezier(.45,0,.3,1)) infinite:
    // y 0 at 0%/42%/100%, -1.5 at 48%, 0 at 54%.
    private func thinkBob() async {
        let dip = Animation.timingCurve(0.45, 0, 0.3, 1.0, duration: 0.252)
        while !Task.isCancelled {
            guard await nap(1764) else { return } // 0% -> 42%: rest at 0
            withAnimation(dip) { bodyPose.offset.height = -1.5 } // 42% -> 48%
            guard await nap(252) else { return }
            withAnimation(dip) { bodyPose.offset.height = 0 } // 48% -> 54%
            guard await nap(252) else { return }
            guard await nap(1932) else { return } // 54% -> 100%: rest at 0
        }
    }

    // tool: body 0.82s ease-in-out infinite: y 0 at 0%/100%, -2 at 50%.
    private func toolBob() async {
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.41)) { bodyPose.offset.height = -2 }
            guard await nap(410) else { return }
            withAnimation(.easeInOut(duration: 0.41)) { bodyPose.offset.height = 0 }
            guard await nap(410) else { return }
        }
    }

    // finished: one-shot 1.9s stretch-squash -> leap -> roll -> land -> sink.
    private func finishedSequence() async {
        let steps: [(CatPose, Int)] = [
            (CatPose(offset: CGSize(width: 0, height: 2),
                     scale: CGSize(width: 1.2, height: 0.76)), 304), // 16%
            (CatPose(offset: CGSize(width: -3, height: -7), rotation: -18,
                     scale: CGSize(width: 0.96, height: 0.96)), 285), // 31%
            (CatPose(offset: CGSize(width: 5, height: -5), rotation: 340,
                     scale: CGSize(width: 0.92, height: 0.92)), 665), // 66%
            (CatPose(offset: CGSize(width: 0, height: 1), rotation: 360,
                     scale: CGSize(width: 1.13, height: 0.84)), 304), // 82%
            (CatPose(offset: CGSize(width: 0, height: 26), rotation: 360,
                     scale: CGSize(width: 0.66, height: 0.66), opacity: 0), 342), // 100%
        ]
        for (pose, ms) in steps {
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: Double(ms) / 1000)) {
                bodyPose = pose
            }
            guard await nap(ms) else { return }
        }
    }

    // peeking: one-shot 3.4s rise -> look left -> look right -> sink.
    private func peekingSequence() async {
        let steps: [(CatPose, Int)] = [
            (CatPose(offset: CGSize(width: 0, height: 28), opacity: 1), 476), // 14%
            (CatPose(offset: CGSize(width: 0, height: 7), opacity: 1), 306), // 23%
            (CatPose(offset: CGSize(width: 0, height: 2), rotation: -8), 510), // 38%
            (CatPose(offset: CGSize(width: 0, height: 2), rotation: 8), 510), // 53%
            (CatPose(offset: CGSize(width: 0, height: 3), rotation: -4), 476), // 67%
            (CatPose(offset: CGSize(width: 0, height: 7), opacity: 1), 408), // 79%
            (CatPose(offset: CGSize(width: 0, height: 28), opacity: 0), 714), // 100%
        ]
        for (pose, ms) in steps {
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: Double(ms) / 1000)) {
                bodyPose = pose
            }
            guard await nap(ms) else { return }
        }
    }

    // tap: one-shot 0.62s squash-and-recover.
    private func playTapBody() async {
        let steps: [(CatPose, Int)] = [
            (CatPose(offset: CGSize(width: 0, height: -3),
                     scale: CGSize(width: 1.07, height: 0.94)), 236), // 38%
            (CatPose.identity, 211), // 72%
            (CatPose.identity, 173), // 100%: hold
        ]
        for (pose, ms) in steps {
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: Double(ms) / 1000)) {
                bodyPose = pose
            }
            guard await nap(ms) else { return }
        }
    }

    private func wagTailForever(rest: Double, peak: Double, halfMs: Int, curve: Animation) async {
        while !Task.isCancelled {
            withAnimation(curve) { tailAngle = peak }
            guard await nap(halfMs) else { return }
            withAnimation(curve) { tailAngle = rest }
            guard await nap(halfMs) else { return }
        }
    }

    private func wagTailCounted(rest: Double, peak: Double, halfMs: Int, times: Int) async {
        for _ in 0 ..< times {
            withAnimation(.easeInOut(duration: Double(halfMs) / 1000)) { tailAngle = peak }
            guard await nap(halfMs) else { return }
            withAnimation(.easeInOut(duration: Double(halfMs) / 1000)) { tailAngle = rest }
            guard await nap(halfMs) else { return }
        }
    }

    // tool: ears 0.34s ease-in-out infinite alternate, left 0 -> -12deg,
    // right 0 -> +12deg with a 0.1s delay so they don't move in sync.
    private func twitchEar(left: Bool, delayMs: Int) async {
        guard mode == .tool else { return }
        if delayMs > 0 { guard await nap(delayMs) else { return } }
        let peak = left ? -12.0 : 12.0
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.17)) {
                if left { earLeftAngle = peak } else { earRightAngle = peak }
            }
            guard await nap(170) else { return }
            withAnimation(.easeInOut(duration: 0.17)) {
                if left { earLeftAngle = 0 } else { earRightAngle = 0 }
            }
            guard await nap(170) else { return }
        }
    }
}

// MARK: - PoseEffect

/// Whole-cat transform; rotation and scale pivot on 50%/90% of the canvas
/// (the spec's "whole svg" transform origin).
private struct PoseEffect: ViewModifier {
    let pose: CatPose

    func body(content: Content) -> some View {
        content
            .offset(pose.offset)
            .rotationEffect(.degrees(pose.rotation), anchor: UnitPoint(x: 0.5, y: 0.9))
            .scaleEffect(pose.scale, anchor: UnitPoint(x: 0.5, y: 0.9))
            .opacity(pose.opacity)
    }
}

// MARK: - CatPartShape

/// Draws a precomputed path (in 46pt-canvas coordinates) inside a frame that
/// matches the part's own bounds.
private struct CatPartShape: Shape {
    let path: Path
    let box: CGRect

    func path(in rect: CGRect) -> Path {
        path.offsetBy(dx: rect.minX - box.minX, dy: rect.minY - box.minY)
    }
}

// MARK: - CatPressButtonStyle

/// Reports the Button's isPressed through a Binding so BlackCatView can
/// render the exact press state from the spec. No extra visuals of its own.
struct CatPressButtonStyle: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                pressed = isPressed
            }
    }
}

// MARK: - PeekCatHost

/// The peeking easter egg: when the chat tab is active and no bubble cat is
/// showing, a cat peeks over the input bar every 8-14s (random) for 3.4s,
/// then sinks back. The host clips to its own frame so the cat genuinely
/// disappears behind the input bar's top edge instead of fading mid-air.
struct PeekCatHost: View {
    @EnvironmentObject private var vm: AIChatViewModel

    /// DuduTabView's selection == .chat, passed down from ChatView.
    let isChatActive: Bool

    @State private var peeking = false
    @State private var tapNonce = 0
    @State private var pressed = false
    @State private var countdown = Double.random(in: 8 ... 14)
    @State private var drawerBlock: AssistantBlock?

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if peeking {
                Button {
                    tapNonce += 1
                    // Peek tap: the wiggle plays (tapNonce); 620ms later
                    // the drawer opens for the session's most recent
                    // thinking block. No thinking block anywhere means the
                    // tap is just the wiggle.
                    let block = vm.messages.reversed().compactMap { message in
                        message.blocks.first { $0.kind == .thinking }
                    }.first
                    guard let block else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
                        drawerBlock = block
                    }
                } label: {
                    BlackCatView(mode: .peeking, tapNonce: tapNonce, pressed: pressed)
                }
                .buttonStyle(CatPressButtonStyle(pressed: $pressed))
                .accessibilityLabel("小黑猫正在探头偷看，打开思考与工具")
            }
        }
        .frame(width: 60, height: 46)
        .clipped()
        // The drawer lives on the host (not inside `if peeking`) so it
        // survives the peek window closing underneath it. Peek only shows
        // while the engine is idle, so the block is never live.
        // Custom bottom drawer (Wave 2 Item 9): presented as an overlay,
        // not a system sheet.
        .overlay {
            if let block = drawerBlock {
                ThinkingDrawerOverlay(block: block, isLive: false) {
                    drawerBlock = nil
                }
            }
        }
        .onReceive(tick) { _ in
            countdown -= 1
            guard countdown <= 0 else { return }
            countdown = Double.random(in: 8 ... 14)
            // "No cat showing anywhere" ~= the engine is idle. (The 1.9s
            // finished one-shot is the only unobservable sliver; a peek
            // landing inside it is harmless.)
            guard isChatActive, !vm.isProcessing, !peeking else { return }
            peeking = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                peeking = false
            }
        }
    }
}

// MARK: - SVGPathParser

/// Minimal SVG path-data parser — just enough for the spec's path strings
/// (M/m, L/l, H/h, V/v, C/c, S/s, Z, with implicit command repetition and
/// sign-separated numbers like "15.8-.1"). Pure and nonisolated: it never
/// touches theme state.
private struct SVGPathParser {
    private var chars: [Character]
    private var i = 0
    private var path = CGMutablePath()
    private var cur = CGPoint.zero
    private var subStart = CGPoint.zero
    private var prevCubicCtrl2: CGPoint?

    static func parse(_ d: String) -> CGPath {
        var p = SVGPathParser(chars: Array(d))
        p.run()
        return p.path
    }

    private mutating func run() {
        var cmd: Character = "\0"
        while true {
            skipSeparators()
            guard i < chars.count else { break }
            if chars[i].isLetter {
                cmd = chars[i]
                i += 1
                if cmd == "Z" || cmd == "z" {
                    path.closeSubpath()
                    cur = subStart
                    prevCubicCtrl2 = nil
                    cmd = "\0"
                    continue
                }
            }
            guard cmd != "\0" else { i += 1; continue }
            switch cmd {
            case "M":
                let pt = readPoint()
                path.move(to: pt); cur = pt; subStart = pt
                cmd = "L"; prevCubicCtrl2 = nil
            case "m":
                let d = readPoint()
                cur = CGPoint(x: cur.x + d.x, y: cur.y + d.y)
                path.move(to: cur); subStart = cur
                cmd = "l"; prevCubicCtrl2 = nil
            case "L":
                cur = readPoint(); path.addLine(to: cur); prevCubicCtrl2 = nil
            case "l":
                let d = readPoint()
                cur = CGPoint(x: cur.x + d.x, y: cur.y + d.y)
                path.addLine(to: cur); prevCubicCtrl2 = nil
            case "H":
                cur.x = readNumber(); path.addLine(to: cur); prevCubicCtrl2 = nil
            case "h":
                cur.x += readNumber(); path.addLine(to: cur); prevCubicCtrl2 = nil
            case "V":
                cur.y = readNumber(); path.addLine(to: cur); prevCubicCtrl2 = nil
            case "v":
                cur.y += readNumber(); path.addLine(to: cur); prevCubicCtrl2 = nil
            case "C":
                let c1 = readPoint(), c2 = readPoint(), pt = readPoint()
                path.addCurve(to: pt, control1: c1, control2: c2)
                prevCubicCtrl2 = c2; cur = pt
            case "c":
                let d1 = readPoint(), d2 = readPoint(), d3 = readPoint()
                let c1 = CGPoint(x: cur.x + d1.x, y: cur.y + d1.y)
                let c2 = CGPoint(x: cur.x + d2.x, y: cur.y + d2.y)
                let pt = CGPoint(x: cur.x + d3.x, y: cur.y + d3.y)
                path.addCurve(to: pt, control1: c1, control2: c2)
                prevCubicCtrl2 = c2; cur = pt
            case "S":
                let c2 = readPoint(), pt = readPoint()
                path.addCurve(to: pt, control1: reflectedCtrl(), control2: c2)
                prevCubicCtrl2 = c2; cur = pt
            case "s":
                let d2 = readPoint(), d3 = readPoint()
                let c2 = CGPoint(x: cur.x + d2.x, y: cur.y + d2.y)
                let pt = CGPoint(x: cur.x + d3.x, y: cur.y + d3.y)
                path.addCurve(to: pt, control1: reflectedCtrl(), control2: c2)
                prevCubicCtrl2 = c2; cur = pt
            default:
                i += 1
            }
        }
    }

    private mutating func reflectedCtrl() -> CGPoint {
        guard let p = prevCubicCtrl2 else { return cur }
        return CGPoint(x: 2 * cur.x - p.x, y: 2 * cur.y - p.y)
    }

    private mutating func skipSeparators() {
        while i < chars.count
            && (chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t")
        {
            i += 1
        }
    }

    private mutating func readNumber() -> Double {
        skipSeparators()
        let start = i
        if i < chars.count && (chars[i] == "-" || chars[i] == "+") { i += 1 }
        while i < chars.count && (chars[i].isNumber || chars[i] == ".") { i += 1 }
        return Double(String(chars[start ..< i])) ?? 0
    }

    private mutating func readPoint() -> CGPoint {
        CGPoint(x: readNumber(), y: readNumber())
    }
}
