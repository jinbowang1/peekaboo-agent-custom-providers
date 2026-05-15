import Foundation
import Tachikoma
import Testing
@testable import PeekabooAutomation

struct PeekabooCustomProviderFactoryTests {
    @Test
    @MainActor
    func `makeModel resolves an enabled OpenAI-compatible provider`() throws {
        try self.withCustomProviderConfig(
            providerID: "local-proxy",
            providerType: "openai",
            baseURL: "http://localhost:8317/v1",
            apiKey: "dummy-not-used",
            models: """
            "mini": { "name": "gpt-5.4-mini", "supportsVision": true }
            """) {
                let model = try #require(PeekabooCustomProviderFactory.makeModel(
                    providerID: "local-proxy",
                    modelString: "mini",
                    configuration: ConfigurationManager.shared))

                #expect(model.providerID == "local-proxy")
                #expect(model.resolvedModelID == "gpt-5.4-mini")
                #expect(model.modelId == "local-proxy/gpt-5.4-mini")
                #expect(model.baseURL == "http://localhost:8317/v1")
                #expect(model.apiKey == "dummy-not-used")
                #expect(model.kind == .openai)
                #expect(model.capabilities.supportsVision)
                #expect(model.capabilities.supportsTools)
            }
    }

    @Test
    @MainActor
    func `makeModel resolves an enabled Anthropic-compatible provider`() throws {
        try self.withCustomProviderConfig(
            providerID: "claude-bridge",
            providerType: "anthropic",
            baseURL: "http://localhost:9000/v1",
            apiKey: "anthropic-test-key",
            models: """
            "opus": { "name": "claude-opus-4-7", "supportsVision": false }
            """) {
                let model = try #require(PeekabooCustomProviderFactory.makeModel(
                    providerID: "claude-bridge",
                    modelString: "opus",
                    configuration: ConfigurationManager.shared))

                #expect(model.kind == .anthropic)
                #expect(model.resolvedModelID == "claude-opus-4-7")
                #expect(model.capabilities.supportsVision == false)
            }
    }

    @Test
    @MainActor
    func `makeModel returns nil for unknown provider id`() throws {
        try self.withCustomProviderConfig(
            providerID: "local-proxy",
            providerType: "openai",
            baseURL: "http://localhost:8317/v1",
            apiKey: "dummy-not-used",
            models: """
            "mini": { "name": "gpt-5.4-mini" }
            """) {
                let model = PeekabooCustomProviderFactory.makeModel(
                    providerID: "does-not-exist",
                    modelString: "mini",
                    configuration: ConfigurationManager.shared)
                #expect(model == nil)
            }
    }

    @Test
    @MainActor
    func `makeModel returns nil when provider is disabled`() throws {
        try self.withCustomProviderConfig(
            providerID: "local-proxy",
            providerType: "openai",
            baseURL: "http://localhost:8317/v1",
            apiKey: "dummy",
            models: """
            "mini": { "name": "gpt-5.4-mini" }
            """,
            enabled: false) {
                let model = PeekabooCustomProviderFactory.makeModel(
                    providerID: "local-proxy",
                    modelString: "mini",
                    configuration: ConfigurationManager.shared)
                #expect(model == nil)
            }
    }

    @Test
    @MainActor
    func `makeModel falls back to modelString when no model entry exists`() throws {
        try self.withCustomProviderConfig(
            providerID: "local-proxy",
            providerType: "openai",
            baseURL: "http://localhost:8317/v1",
            apiKey: "dummy",
            models: nil) {
                let model = try #require(PeekabooCustomProviderFactory.makeModel(
                    providerID: "local-proxy",
                    modelString: "freeform-model-id",
                    configuration: ConfigurationManager.shared))

                #expect(model.resolvedModelID == "freeform-model-id")
                #expect(model.modelId == "local-proxy/freeform-model-id")
                #expect(model.capabilities.supportsVision)
            }
    }

    @Test
    @MainActor
    func `resolveCredential dereferences env var indirection`() throws {
        let varName = "PEEKABOO_FACTORY_TEST_KEY_\(UUID().uuidString.prefix(8))"
        setenv(varName, "value-from-env", 1)
        defer { unsetenv(varName) }

        try self.withCustomProviderConfig(
            providerID: "envref",
            providerType: "openai",
            baseURL: "http://localhost:8317/v1",
            apiKey: "{env:\(varName)}",
            models: """
            "default": { "name": "gpt-5.4-mini" }
            """) {
                let model = try #require(PeekabooCustomProviderFactory.makeModel(
                    providerID: "envref",
                    modelString: "default",
                    configuration: ConfigurationManager.shared))
                #expect(model.apiKey == "value-from-env")
            }
    }

    @Test
    @MainActor
    func `tachikomaConfiguration injects api key for custom OpenAI-compatible model`() throws {
        try self.withCustomProviderConfig(
            providerID: "ark",
            providerType: "openai",
            baseURL: "http://ark.example/v1",
            apiKey: "ark-secret-123",
            models: """
            "examplemodel": { "name": "example-model-v1" }
            """) {
                let model = try #require(PeekabooCustomProviderFactory.makeModel(
                    providerID: "ark",
                    modelString: "examplemodel",
                    configuration: ConfigurationManager.shared))
                let config = PeekabooCustomProviderFactory.tachikomaConfiguration(for: .custom(provider: model))
                #expect(config.getAPIKey(for: "openai_compatible") == "ark-secret-123")
            }
    }

    private func withCustomProviderConfig(
        providerID: String,
        providerType: String,
        baseURL: String,
        apiKey: String,
        models: String?,
        enabled: Bool = true,
        body: () throws -> Void) throws
    {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("peekaboo-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let modelsBlock: String = if let models {
            ", \"models\": { \(models) }"
        } else {
            ""
        }

        let configJSON = """
        {
          "customProviders": {
            "\(providerID)": {
              "name": "\(providerID)",
              "type": "\(providerType)",
              "enabled": \(enabled),
              "options": {
                "baseURL": "\(baseURL)",
                "apiKey": "\(apiKey)"
              }\(modelsBlock)
            }
          }
        }
        """
        try configJSON.write(
            to: tempDir.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8)

        let prevConfigDir = getenv("PEEKABOO_CONFIG_DIR").map { String(cString: $0) }
        let prevMigration = getenv("PEEKABOO_CONFIG_DISABLE_MIGRATION").map { String(cString: $0) }
        setenv("PEEKABOO_CONFIG_DIR", tempDir.path, 1)
        setenv("PEEKABOO_CONFIG_DISABLE_MIGRATION", "1", 1)

        ConfigurationManager.shared.resetForTesting()
        _ = ConfigurationManager.shared.loadConfiguration()

        defer {
            if let prev = prevConfigDir { setenv("PEEKABOO_CONFIG_DIR", prev, 1) } else { unsetenv("PEEKABOO_CONFIG_DIR") }
            if let prev = prevMigration { setenv("PEEKABOO_CONFIG_DISABLE_MIGRATION", prev, 1) } else { unsetenv("PEEKABOO_CONFIG_DISABLE_MIGRATION") }
            ConfigurationManager.shared.resetForTesting()
            try? FileManager.default.removeItem(at: tempDir)
        }

        try body()
    }
}
