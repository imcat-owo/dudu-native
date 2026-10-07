import Foundation

// MARK: - Voice call tools (AI → propose_voice_call / list_voice_calls)
//
// Ported from ~/workspace/openmuse/apps/mobile/src/voice-call/tools.ts.
//
// Permission iron rule (her authorization model — a call is the most
// intrusive proactive act): the AI may only PROPOSE a call. The phone rings
// with WHO and WHY; SHE accepts or declines. The AI can never start audio
// or auto-answer. A declined/missed proposal is NEVER silently retried.
//
// Definitions are appended in AIChatViewModel.makeAgentTools(); the handlers
// below are called from AIChatViewModel+ConcurrentTools's dispatch switch.

private let voiceCallPermissionLine =
    "PERMISSION RULE (hard): a call is the most intrusive thing you can do — " +
    "it rings HER phone. Only propose a call when SHE explicitly asked for one " +
    "in THIS conversation ('给我打个电话'), or when you have her explicit " +
    "permission for this specific call. NEVER surprise-call her. The proposal " +
    "must carry a real reason — 'call me' with no why is refused."

func voiceCallToolDefinitions() -> [AgentToolDefinition] {
    [
        AgentToolDefinition(
            name: "propose_voice_call",
            description:
                "Propose a realtime voice call to HER (AI-initiated call). This RINGS her phone " +
                "with your persona name and reason — she accepts or declines. " +
                voiceCallPermissionLine +
                " A declined or missed proposal is terminal: never re-propose without a new explicit reason. " +
                "Use list_voice_calls first to avoid duplicate ringing.",
            parameters: [
                "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user (e.g. 'Propose a voice call about the trip'). Use the same language as the user."),
                "personaId": AgentToolParam(type: .string, description: "Persona id placing the call (must be YOUR persona). Omit to use the current persona."),
                "reason": AgentToolParam(type: .string, description: "WHY you want to call — shown to her as the ring reason. Required, be specific."),
                "topic": AgentToolParam(type: .string, description: "Optional: what the call is about."),
            ],
            required: ["tool_title", "reason"],
            propertyOrdering: ["tool_title", "personaId", "reason", "topic"]
        ),
        AgentToolDefinition(
            name: "list_voice_calls",
            description:
                "List voice call proposals (ringing / accepted / declined / missed) with reasons. " +
                "Use before proposing to avoid duplicate ringing, or when she asks about calls.",
            parameters: [
                "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user. Use the same language as the user."),
            ],
            required: ["tool_title"],
            propertyOrdering: ["tool_title"]
        ),
    ]
}

@MainActor
enum VoiceCallToolHandler {

    struct Outcome {
        let output: String
        let success: Bool
    }

    static func propose(
        args: [String: Any],
        isIncognito: Bool,
        personas: [Persona],
        currentPersonaId: String
    ) async -> Outcome {
        // Incognito: no ringing, no proposals — the old Dudu suppressed the
        // ring UI in incognito; the tool is refused outright here.
        if isIncognito {
            return Outcome(
                output: "Error: Voice calls are unavailable in incognito mode.",
                success: false)
        }
        let reason = (args["reason"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            return Outcome(
                output: "Error: Missing required 'reason' parameter. A call proposal needs a reason — she decides based on the why.",
                success: false)
        }
        let topic = (args["topic"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let personaIdArg = (args["personaId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let persona: Persona?
        if let pid = personaIdArg, !pid.isEmpty {
            persona = personas.first(where: { $0.id == pid })
            guard persona != nil else {
                return Outcome(
                    output: "Error: Persona not found: \(pid).",
                    success: false)
            }
        } else {
            persona = personas.first(where: { $0.id == currentPersonaId })
                ?? personas.first
        }
        guard let persona else {
            return Outcome(output: "Error: No persona available.", success: false)
        }
        do {
            let p = try await CallProposalCenter.shared.propose(
                reason: reason,
                topic: (topic?.isEmpty == true) ? nil : topic,
                personaId: persona.id,
                personaName: persona.name)
            return Outcome(
                output: "Call proposed — her phone is ringing with your reason. " +
                    "Proposal [\(p.id)] status=ringing. " +
                    "If she declines or misses it, do NOT re-propose without asking her first.",
                success: true)
        } catch {
            return Outcome(
                output: "Error: \(error.localizedDescription)",
                success: false)
        }
    }

    static func list() async -> Outcome {
        let list = CallProposalCenter.shared.recentProposals()
        guard !list.isEmpty else {
            return Outcome(output: "No call proposals yet.", success: true)
        }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        let lines = list.map { p -> String in
            var line = "- \(p.personaName) [\(p.id)] status=\(p.status.rawValue) " +
                "at=\(fmt.string(from: p.createdAt))\n" +
                "  reason: \(p.reason)"
            if let topic = p.topic, !topic.isEmpty {
                line += "\n  topic: \(topic)"
            }
            return line
        }
        return Outcome(output: lines.joined(separator: "\n"), success: true)
    }
}
