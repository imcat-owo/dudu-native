import Foundation

// MARK: - 语音通话纸条（AI 说明书 · 纸条版）
//
// 按她定的纸条口径：用户话题跟语音通话相关时，才把这张纸条塞进 system
// prompt（注入点见 AIChatViewModel.runAgentLoop 的两处）；平时不占 prompt。
// 内容来自旧嘟嘟的 src/manuals/voice-call.ts，consent 铁律逐字保留。
//
// 触发判定是宽松的语义匹配（不是死关键词）；是否配了 TTS/模型不影响纸条
// 本身——工具定义里已有 permission 说明，缺配置时工具会明确报错。

enum VoiceCallPaper {

    static func paperIfRelevant(userMessage: String) -> String? {
        let t = userMessage.lowercased()
        let triggers = [
            "打电话", "语音通话", "电话", "通话", "voice call",
            "给我打个", "打个电话", "call me",
        ]
        guard triggers.contains(where: { t.contains($0) }) else { return nil }
        return paperText()
    }

    static func paperText() -> String {
        """
        【纸条·语音通话】
        你有一个 propose_voice_call 工具：向主人提议一通实时语音通话（电话会响铃，她接听后你们直接用语音对话，她可以随时打断你说话——像打电话，不是一条条语音消息）。

        同意铁律（最高标准——电话是最打扰人的主动行为）：
        - 你只能提议（propose），永远不能自己接通、不能自动开始录音。
        - 只有她在这次对话里明确说过「给我打个电话」这类话，或者给了这一次通话的明确许可，才能调这个工具。永远不要搞突然袭击。
        - 提议必须带上真正的 reason（为什么打这通电话）——没有 why 的提议会被拒绝。
        - 她挂断/未接之后，这个提议就结束了：永远不要悄悄重拨。想再打，必须有新的理由、重新提议。
        - 无痕模式里不能打电话：通话内容会写进聊天记录，无痕模式承诺不留痕，所以这条路是关的。

        通话里你是这样工作的（级联链路，诚实延迟）：
        - 她的声音 → 语音识别 → 你（她配好的模型）→ 逐句语音合成 → 播给她听。
        - 一轮有几秒延迟（识别+思考+合成），不是服务器实时模型那种 1.5 秒。如果她问为什么有停顿，如实说，别装作是即时的。
        - 她说话盖过你时，你会停下把话筒交给她；短促的杂音不会触发打断（要持续说话才算）。

        设备诚实：
        - 通话要麦克风权限；没有就直说、停下。
        - 绝不用预录好的音频假装通话——没经过她实时声音的「通话」是撒谎。
        """
    }
}
