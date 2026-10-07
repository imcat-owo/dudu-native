import Foundation

// MARK: - ProviderShareCodec · 服务配置分享编解码
//
// Native port of old Dudu's api-groups/sharing.ts (B12/D38/D44).
// The wire format is byte-compatible with the old app so QR codes and
// pasted share texts cross-import both ways:
//
//   dudu-provider:v1:<base64(utf8 JSON)>
//
// JSON fields (all validated on decode, same rules as decodeShare):
//   v=1, name, vendor, baseUrl, apiKey, model, headers,
//   headersStripped?, bodyExtras?, apiKeys?[{name,key,priority}], exportedAt
//
// SECURITY: the payload carries the API key in plaintext — that is the
// point (move a working config to another phone). The share UI must show
// the explicit key warning before rendering the QR (old Dudu behavior).

/// Old Dudu share prefix — kept verbatim so old QR codes still import.
let providerSharePrefix = "dudu-provider:v1:"

/// Decoded share payload. Mirrors SharedProviderPayload in sharing.ts.
struct SharedProviderPayload: Decodable {
    let v: Int
    let name: String
    let vendor: String
    let baseUrl: String
    let apiKey: String
    let model: String
    let headers: [String: String]
    let headersStripped: Bool
    let hasBodyExtras: Bool
    let apiKeys: [SharedAPIKey]

    struct SharedAPIKey: Decodable {
        let name: String
        let key: String
        let priority: Int
    }

    private enum CodingKeys: String, CodingKey {
        case v, name, vendor, baseUrl, apiKey, model, headers
        case headersStripped, bodyExtras, apiKeys, exportedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decode(Int.self, forKey: .v)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        vendor = try c.decodeIfPresent(String.self, forKey: .vendor) ?? "custom"
        baseUrl = try c.decode(String.self, forKey: .baseUrl)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try c.decode(String.self, forKey: .model)
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        headersStripped = try c.decodeIfPresent(Bool.self, forKey: .headersStripped) ?? false
        // bodyExtras is Record<string, unknown> — the native instance has no
        // field for it, so we only record PRESENCE for the honest warning.
        hasBodyExtras = c.contains(.bodyExtras)
        apiKeys = (try? c.decodeIfPresent([SharedAPIKey].self, forKey: .apiKeys)) ?? []
        // exportedAt is informational; absence is tolerated.
    }
}

enum ProviderShareCodec {
    /// Decode a scanned/pasted share text. Returns nil when the text is not
    /// one of ours — same validation as old Dudu's decodeShare: prefix,
    /// base64, JSON object, v == 1, baseUrl and model are strings.
    static func decodeShare(_ text: String) -> SharedProviderPayload? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix(providerSharePrefix) else { return nil }
        let b64 = String(t.dropFirst(providerSharePrefix.count))
        guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { return nil }
        guard let payload = try? JSONDecoder().decode(SharedProviderPayload.self, from: data) else { return nil }
        guard payload.v == 1 else { return nil }
        return payload
    }

    /// Encode a share text for one provider instance. Matches old Dudu's
    /// encodeShare field-for-field (including headersStripped semantics:
    /// native instances carry no custom headers, so it is always false).
    static func encodeShare(name: String, vendor: String, baseUrl: String,
                            apiKey: String, model: String, includeKeys: Bool) -> String {
        var obj: [String: Any] = [
            "v": 1,
            "name": name,
            "vendor": vendor,
            "baseUrl": baseUrl,
            "apiKey": includeKeys ? apiKey : "",
            "model": model,
            "headers": [String: String](),
            "exportedAt": Int(Date().timeIntervalSince1970 * 1000),
        ]
        // Native instances have no custom headers and no key pool, so
        // headersStripped / apiKeys are never emitted. Old Dudu decoders
        // treat their absence as false / empty (decodeIfPresent defaults).
        let json = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
        return providerSharePrefix + json.base64EncodedString()
    }
}

// MARK: - Vendor mapping (old Dudu ApiVendor <-> native ProviderType)

enum ProviderShareVendor {
    /// Old Dudu vendor string for a native provider type (encode side).
    static func vendorString(for type: ProviderType) -> String {
        switch type {
        case .anthropic: return "anthropic"
        case .gemini: return "gemini"
        case .openAI, .openAIResponses, .openRouter, .xAI, .kimiCode: return "openai"
        case .antigravity, .unsupported: return "custom"
        }
    }

    /// Native provider type for an old Dudu vendor string (decode side).
    /// "custom" (and anything unknown) maps to .openAI: the OpenAI-compatible
    /// path with a custom base URL — same role "custom" played in old Dudu.
    static func providerType(for vendor: String) -> ProviderType {
        switch vendor.lowercased() {
        case "anthropic": return .anthropic
        case "gemini": return .gemini
        case "openai": return .openAI
        default: return .openAI
        }
    }

    /// Official base URL for the type, so the share payload carries a working
    /// address even when the instance uses the provider default.
    static func officialBaseURL(for type: ProviderType) -> String {
        switch type {
        case .anthropic: return "https://api.anthropic.com"
        case .openAI, .openAIResponses: return "https://api.openai.com"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .xAI: return "https://api.x.ai/v1"
        case .kimiCode: return "https://api.kimi.com/coding"
        case .antigravity, .unsupported: return ""
        }
    }
}

// MARK: - Import

/// Honest warnings produced while importing a shared payload.
enum ProviderShareImportWarning: Hashable {
    /// The payload carried custom headers (or the sharer stripped them):
    /// native instances have no header field, so they were dropped.
    case headersDropped
    /// The payload carried extra request params: no native field, dropped.
    case bodyExtrasDropped
    /// The payload carried a key pool: native keeps a single key per instance.
    case keyPoolTruncated(poolSize: Int)
    /// No key in the payload: the user must fill it on the detail page.
    case noKey
    /// No base URL in the payload: the user must fill it on the detail page.
    case noBaseURL
}

struct ProviderShareImportResult {
    let instanceId: String
    let name: String
    let warnings: [ProviderShareImportWarning]
}

enum ProviderShareImporter {
    /// Import a decoded payload as a brand-new provider instance + model
    /// entry. Synchronous — the store and Keychain writes underneath are
    /// synchronous, so there is no fake "importing" spinner (old Dudu needed
    /// one only because its upsert was async).
    @MainActor
    static func importPayload(_ payload: SharedProviderPayload,
                             into store: ProviderConfigStore) -> ProviderShareImportResult {
        let type = ProviderShareVendor.providerType(for: payload.vendor)
        let baseURL = payload.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        var instance = ProviderInstance(
            label: payload.name.isEmpty ? "导入的配置" : payload.name,
            providerType: type,
            credentialType: .apiKey,
            customBaseURL: baseURL.isEmpty ? nil : baseURL
        )
        store.addInstance(instance)

        // Key: primary apiKey wins; otherwise the highest-priority pool key
        // (pool is sorted ascending by priority — lower number = higher priority).
        let primaryKey = payload.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let poolKey = payload.apiKeys
            .sorted { $0.priority < $1.priority }
            .first.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let keyToSave = !primaryKey.isEmpty ? primaryKey : poolKey

        var warnings: [ProviderShareImportWarning] = []
        if !keyToSave.isEmpty {
            ProviderKeychainHelper.saveAPIKey(keyToSave, instanceId: instance.id, caller: "ProviderShareImporter")
        } else {
            warnings.append(.noKey)
        }
        if payload.apiKeys.count > 1 {
            warnings.append(.keyPoolTruncated(poolSize: payload.apiKeys.count))
        }
        if !payload.headers.isEmpty || payload.headersStripped {
            warnings.append(.headersDropped)
        }
        if payload.hasBodyExtras {
            warnings.append(.bodyExtrasDropped)
        }
        if baseURL.isEmpty {
            warnings.append(.noBaseURL)
        }

        // Model entry for the shared model id (custom entry, like the
        // manual "Add Model" flow).
        let modelId = payload.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !modelId.isEmpty {
            let model = LLMModel(id: modelId, displayName: modelId, provider: type.rawValue)
            let entry = ModelEntry(providerInstanceId: instance.id, model: model, isCustom: true)
            _ = store.addEntry(entry)
        }

        return ProviderShareImportResult(instanceId: instance.id, name: instance.label, warnings: warnings)
    }
}
