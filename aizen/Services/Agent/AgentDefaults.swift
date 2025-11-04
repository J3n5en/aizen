//
//  AgentDefaults.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Default agent configurations
extension AgentRegistry {
    /// Initialize default built-in agents with discovery
    func initializeDefaultAgents() {
        // Get existing metadata
        var metadata = agentMetadata

        // Try to discover agent paths
        let discovered = discoverAgents()

        // Create or update default built-in agents
        // Only add if not already present to preserve user settings

        addAgentIfMissing("claude", to: &metadata, discovered: discovered) {
            AgentMetadata(
                id: "claude",
                name: "Claude",
                description: "Anthropic's AI assistant with advanced coding capabilities",
                iconType: .builtin("claude"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: discovered["claude"],
                launchArgs: [],
                installMethod: .npm(package: "@zed-industries/claude-code-acp")
            )
        }

        addAgentIfMissing("codex", to: &metadata, discovered: discovered) {
            AgentMetadata(
                id: "codex",
                name: "Codex",
                description: "OpenAI's code generation model",
                iconType: .builtin("openai"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: discovered["codex"],
                launchArgs: [],
                installMethod: .githubRelease(
                    repo: "openai/openai-agent",
                    assetPattern: "openai-agent-{arch}-apple-darwin.tar.gz"
                )
            )
        }

        addAgentIfMissing("gemini", to: &metadata, discovered: discovered) {
            AgentMetadata(
                id: "gemini",
                name: "Gemini",
                description: "Google's multimodal AI model",
                iconType: .builtin("gemini"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: discovered["gemini"],
                launchArgs: ["--experimental-acp"],
                installMethod: .npm(package: "@google/gemini-cli")
            )
        }

        addAgentIfMissing("kimi", to: &metadata, discovered: discovered) {
            AgentMetadata(
                id: "kimi",
                name: "Kimi",
                description: "Moonshot AI assistant",
                iconType: .builtin("kimi"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: discovered["kimi"],
                launchArgs: ["--acp"],
                installMethod: .githubRelease(
                    repo: "MoonshotAI/kimi-cli",
                    assetPattern: "kimi-{version}-{arch}-apple-darwin.tar.gz"
                )
            )
        }

        agentMetadata = metadata
    }

    /// Helper to add agent if not already present, preserving user settings
    func addAgentIfMissing(
        _ id: String,
        to metadata: inout [String: AgentMetadata],
        discovered: [String: String],
        factory: () -> AgentMetadata
    ) {
        if metadata[id] == nil {
            metadata[id] = factory()
        }
    }
}
