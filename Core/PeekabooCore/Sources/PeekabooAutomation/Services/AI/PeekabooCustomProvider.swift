import Foundation
import Tachikoma

public final class PeekabooCustomProviderModel: ModelProvider, @unchecked Sendable {
    public enum Kind: Sendable {
        case openai
        case anthropic
    }

    public let providerID: String
    public let resolvedModelID: String
    public let kind: Kind
    public let modelId: String
    public let baseURL: String?
    public let apiKey: String?
    public let additionalHeaders: [String: String]
    public let capabilities: ModelCapabilities

    public init(
        providerID: String,
        resolvedModelID: String,
        kind: Kind,
        baseURL: String,
        apiKey: String?,
        additionalHeaders: [String: String],
        supportsVision: Bool)
    {
        self.providerID = providerID
        self.resolvedModelID = resolvedModelID
        self.kind = kind
        self.modelId = "\(providerID)/\(resolvedModelID)"
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.additionalHeaders = additionalHeaders
        self.capabilities = ModelCapabilities(
            supportsVision: supportsVision,
            supportsTools: true,
            supportsStreaming: true)
    }

    public func generateText(request: ProviderRequest) async throws -> ProviderResponse {
        switch self.kind {
        case .openai:
            try await self.openAICompatibleProvider().generateText(request: request)
        case .anthropic:
            try await self.anthropicCompatibleProvider().generateText(request: request)
        }
    }

    public func streamText(request: ProviderRequest) async throws -> AsyncThrowingStream<TextStreamDelta, any Error> {
        switch self.kind {
        case .openai:
            try await self.openAICompatibleProvider().streamText(request: request)
        case .anthropic:
            try await self.anthropicCompatibleProvider().streamText(request: request)
        }
    }

    func compatibleConfiguration() -> TachikomaConfiguration {
        let configuration = TachikomaConfiguration(loadFromEnvironment: true)
        guard let apiKey, !apiKey.isEmpty else { return configuration }

        switch self.kind {
        case .openai:
            configuration.setAPIKey(apiKey, for: "openai_compatible")
        case .anthropic:
            configuration.setAPIKey(apiKey, for: "anthropic_compatible")
        }
        return configuration
    }

    private func openAICompatibleProvider() throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(
            modelId: self.resolvedModelID,
            baseURL: self.baseURL ?? "",
            configuration: self.compatibleConfiguration(),
            additionalHeaders: self.additionalHeaders)
    }

    private func anthropicCompatibleProvider() throws -> AnthropicCompatibleProvider {
        try AnthropicCompatibleProvider(
            modelId: self.resolvedModelID,
            baseURL: self.baseURL ?? "",
            configuration: self.compatibleConfiguration(),
            additionalHeaders: self.additionalHeaders)
    }
}

public enum PeekabooCustomProviderFactory {
    public static func makeModel(
        providerID: String,
        modelString: String,
        configuration: ConfigurationManager) -> PeekabooCustomProviderModel?
    {
        guard let provider = configuration.getCustomProvider(id: providerID),
              provider.enabled
        else {
            return nil
        }

        let model = provider.models?[modelString]
        let resolvedModelID = model?.name ?? modelString
        let kind: PeekabooCustomProviderModel.Kind = switch provider.type {
        case .openai: .openai
        case .anthropic: .anthropic
        }

        CustomProviderRegistry.shared.loadFromProfile()

        return PeekabooCustomProviderModel(
            providerID: providerID,
            resolvedModelID: resolvedModelID,
            kind: kind,
            baseURL: provider.options.baseURL,
            apiKey: self.resolveCredential(provider.options.apiKey, configuration: configuration),
            additionalHeaders: provider.options.headers ?? [:],
            supportsVision: model?.supportsVision ?? true)
    }

    public static func tachikomaConfiguration(for model: LanguageModel) -> TachikomaConfiguration {
        guard case let .custom(provider) = model,
              let peekabooProvider = provider as? PeekabooCustomProviderModel
        else {
            return .current
        }
        return peekabooProvider.compatibleConfiguration()
    }

    public static func resolveCredential(_ reference: String, configuration: ConfigurationManager) -> String? {
        guard reference.hasPrefix("{env:"), reference.hasSuffix("}") else {
            return reference
        }

        let variableName = String(reference.dropFirst(5).dropLast(1))
        if let environmentValue = ProcessInfo.processInfo.environment[variableName] {
            return environmentValue
        }
        return configuration.credentialValue(for: variableName)
    }
}
