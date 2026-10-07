//
//  DuduAgentProviderFactory.swift
//  Dudu
//
//  SEAM (P3): moved early for P3; P4 AIChatViewModel must forward, not duplicate.
//  Ported from the static `makeAgentProvider(for:)` in
//  Agent/Chat/AIChatViewModel+ProviderFactory.swift (OpenMinis), renamed
//  Minis -> Dudu. The instance-method variant and the warmup helper stay on
//  AIChatViewModel (P4) and must delegate to this static method, not copy it.
//
//  Construct an AgentProvider from a ModelEntry by looking up its
//  ProviderInstance and credential. Used by call sites that don't have a
//  viewmodel context (title generation, vision describe, voice correction).
//  The resolution depends only on global state (ProviderConfigStore +
//  LLMProviderFactory), both of which live in Providers.

import Foundation

private let duduAgentProviderFactoryLog = AppLogger(category: "DuduAgentProviderFactory")

// @MainActor: the original lived on @MainActor AIChatViewModel, and
// LLMProviderFactory (which this calls) is @MainActor.
@MainActor
enum DuduAgentProviderFactory {

    /// Construct an AgentProvider from a ModelEntry by looking up its ProviderInstance and credential.
    static func makeAgentProvider(for entry: ModelEntry) async -> AgentProvider {
        let store = ProviderConfigStore.shared
        guard let instance = store.instance(for: entry.providerInstanceId) else {
            duduAgentProviderFactoryLog.error("No ProviderInstance found for entry \(entry.id)")
            return AnthropicAgentProvider(provider: AnthropicProvider(apiKey: "", model: entry.model))
        }
        switch instance.providerType {
        case .anthropic:
            return AnthropicAgentProvider(provider: LLMProviderFactory.makeAnthropicProvider(instance: instance, model: entry.model))
        case .gemini:
            return GeminiAgentProvider(provider: await LLMProviderFactory.makeGeminiProvider(instance: instance, model: entry.model))
        case .openAI:
            return OpenAIAgentProvider(provider: LLMProviderFactory.makeOpenAIProvider(instance: instance, model: entry.model))
        case .antigravity:
            return AntigravityAgentProvider(provider: await LLMProviderFactory.makeAntigravityProvider(instance: instance, model: entry.model))
        case .openRouter:
            return OpenAIAgentProvider(provider: LLMProviderFactory.makeOpenRouterProvider(instance: instance, model: entry.model))
        case .openAIResponses:
            return OpenAIAgentProvider(provider: LLMProviderFactory.makeOpenAIResponsesProvider(instance: instance, model: entry.model))
        case .xAI:
            return OpenAIAgentProvider(provider: LLMProviderFactory.makeXAIProvider(instance: instance, model: entry.model))
        case .kimiCode:
            return OpenAIAgentProvider(provider: LLMProviderFactory.makeKimiProvider(instance: instance, model: entry.model))
        case .unsupported:
            duduAgentProviderFactoryLog.error("\(instance.providerType) has no agent provider; returning placeholder")
            return AnthropicAgentProvider(provider: AnthropicProvider(apiKey: "", model: entry.model))
        }
    }
}
