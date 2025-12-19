//
//  MCPInstallCommandBuilder.swift
//  aizen
//
//  Builds agent-specific MCP install/uninstall commands
//

import Foundation

struct MCPInstallCommand {
    let executable: String
    let arguments: [String]
    let environment: [String: String]

    var commandString: String {
        var parts = [executable] + arguments
        if !environment.isEmpty {
            let envString = environment.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            parts.insert(envString, at: 0)
        }
        return parts.joined(separator: " ")
    }
}

enum MCPInstallCommandBuilder {

    // MARK: - Package Install

    static func buildInstallCommand(
        for agentId: String,
        agentPath: String?,
        serverName: String,
        package: MCPPackage,
        env: [String: String]
    ) -> MCPInstallCommand {
        // Use CLI name for built-in agents (not ACP wrapper)
        let executable = cliExecutable(for: agentId, agentPath: agentPath)

        switch agentId {
        case "claude":
            return buildClaudeInstall(
                executable: executable,
                serverName: serverName,
                package: package,
                env: env
            )

        case "codex":
            return buildCodexInstall(
                executable: executable,
                serverName: serverName,
                package: package,
                env: env
            )

        case "gemini":
            return buildGeminiInstall(
                executable: executable,
                serverName: serverName,
                package: package,
                env: env
            )

        default:
            return buildGenericInstall(
                executable: executable,
                serverName: serverName,
                package: package,
                env: env
            )
        }
    }

    // MARK: - Remote Install

    static func buildRemoteInstallCommand(
        for agentId: String,
        agentPath: String?,
        serverName: String,
        remote: MCPRemote,
        env: [String: String]
    ) -> MCPInstallCommand {
        // Use CLI name for built-in agents (not ACP wrapper)
        let executable = cliExecutable(for: agentId, agentPath: agentPath)

        switch agentId {
        case "claude":
            return buildClaudeRemoteInstall(
                executable: executable,
                serverName: serverName,
                remote: remote
            )

        case "codex":
            return buildCodexRemoteInstall(
                executable: executable,
                serverName: serverName,
                remote: remote
            )

        case "gemini":
            return buildGeminiRemoteInstall(
                executable: executable,
                serverName: serverName,
                remote: remote
            )

        default:
            return buildGenericRemoteInstall(
                executable: executable,
                serverName: serverName,
                remote: remote
            )
        }
    }

    // MARK: - Remove

    static func buildRemoveCommand(
        for agentId: String,
        agentPath: String?,
        serverName: String
    ) -> MCPInstallCommand {
        // Use CLI name for built-in agents (not ACP wrapper)
        let executable = cliExecutable(for: agentId, agentPath: agentPath)

        return MCPInstallCommand(
            executable: executable,
            arguments: ["mcp", "remove", serverName],
            environment: [:]
        )
    }

    // MARK: - List

    static func buildListCommand(
        for agentId: String,
        agentPath: String?
    ) -> MCPInstallCommand {
        // Use CLI name for built-in agents (not ACP wrapper)
        let executable = cliExecutable(for: agentId, agentPath: agentPath)

        return MCPInstallCommand(
            executable: executable,
            arguments: ["mcp", "list"],
            environment: [:]
        )
    }

    // MARK: - CLI Executable

    /// Returns the CLI executable name for MCP commands.
    /// Built-in agents use their CLI name directly (claude, codex, gemini).
    /// Custom agents use the provided path.
    private static func cliExecutable(for agentId: String, agentPath: String?) -> String {
        switch agentId {
        case "claude":
            return "claude"
        case "codex":
            return "codex"
        case "gemini":
            return "gemini"
        default:
            // For custom agents, use path if provided, otherwise agent ID
            return agentPath ?? agentId
        }
    }

    // MARK: - Claude

    private static func buildClaudeInstall(
        executable: String,
        serverName: String,
        package: MCPPackage,
        env: [String: String]
    ) -> MCPInstallCommand {
        // claude mcp add <name> -s user [--env KEY=VAL]... -- npx -y @package [args]...
        var args = ["mcp", "add", serverName, "-s", "user"]

        for (key, value) in env.sorted(by: { $0.key < $1.key }) {
            args.append(contentsOf: ["--env", "\(key)=\(value)"])
        }

        args.append("--")
        args.append(contentsOf: runtimeArgs(for: package))

        return MCPInstallCommand(executable: executable, arguments: args, environment: [:])
    }

    private static func buildClaudeRemoteInstall(
        executable: String,
        serverName: String,
        remote: MCPRemote
    ) -> MCPInstallCommand {
        // claude mcp add --transport http <name> <url>
        let transport = remote.type == "sse" ? "sse" : "http"
        return MCPInstallCommand(
            executable: executable,
            arguments: ["mcp", "add", "--transport", transport, serverName, remote.url],
            environment: [:]
        )
    }

    // MARK: - Codex

    private static func buildCodexInstall(
        executable: String,
        serverName: String,
        package: MCPPackage,
        env: [String: String]
    ) -> MCPInstallCommand {
        // codex mcp add <name> [--env KEY=VAL]... -- npx -y @package [args]...
        var args = ["mcp", "add", serverName]

        for (key, value) in env.sorted(by: { $0.key < $1.key }) {
            args.append(contentsOf: ["--env", "\(key)=\(value)"])
        }

        args.append("--")
        args.append(contentsOf: runtimeArgs(for: package))

        return MCPInstallCommand(executable: executable, arguments: args, environment: [:])
    }

    private static func buildCodexRemoteInstall(
        executable: String,
        serverName: String,
        remote: MCPRemote
    ) -> MCPInstallCommand {
        // codex mcp add --transport http <name> <url>
        let transport = remote.type == "sse" ? "sse" : "http"
        return MCPInstallCommand(
            executable: executable,
            arguments: ["mcp", "add", "--transport", transport, serverName, remote.url],
            environment: [:]
        )
    }

    // MARK: - Gemini

    private static func buildGeminiInstall(
        executable: String,
        serverName: String,
        package: MCPPackage,
        env: [String: String]
    ) -> MCPInstallCommand {
        // gemini mcp add <name> -- npx -y @package [args]...
        // Note: Gemini may handle env differently
        var args = ["mcp", "add", serverName]

        for (key, value) in env.sorted(by: { $0.key < $1.key }) {
            args.append(contentsOf: ["--env", "\(key)=\(value)"])
        }

        args.append("--")
        args.append(contentsOf: runtimeArgs(for: package))

        return MCPInstallCommand(executable: executable, arguments: args, environment: [:])
    }

    private static func buildGeminiRemoteInstall(
        executable: String,
        serverName: String,
        remote: MCPRemote
    ) -> MCPInstallCommand {
        let transport = remote.type == "sse" ? "sse" : "http"
        return MCPInstallCommand(
            executable: executable,
            arguments: ["mcp", "add", "--transport", transport, serverName, remote.url],
            environment: [:]
        )
    }

    // MARK: - Generic

    private static func buildGenericInstall(
        executable: String,
        serverName: String,
        package: MCPPackage,
        env: [String: String]
    ) -> MCPInstallCommand {
        var args = ["mcp", "add", serverName]

        for (key, value) in env.sorted(by: { $0.key < $1.key }) {
            args.append(contentsOf: ["--env", "\(key)=\(value)"])
        }

        args.append("--")
        args.append(contentsOf: runtimeArgs(for: package))

        return MCPInstallCommand(executable: executable, arguments: args, environment: [:])
    }

    private static func buildGenericRemoteInstall(
        executable: String,
        serverName: String,
        remote: MCPRemote
    ) -> MCPInstallCommand {
        let transport = remote.type == "sse" ? "sse" : "http"
        return MCPInstallCommand(
            executable: executable,
            arguments: ["mcp", "add", "--transport", transport, serverName, remote.url],
            environment: [:]
        )
    }

    // MARK: - Helpers

    private static func runtimeArgs(for package: MCPPackage) -> [String] {
        var args: [String] = []

        switch package.registryType {
        case "npm":
            args.append(package.runtimeHint)  // npx
            args.append("-y")
            args.append(package.identifier)

        case "pypi":
            args.append(package.runtimeHint)  // uvx
            args.append(package.identifier)

        case "oci":
            args.append("docker")
            args.append("run")
            args.append("-i")
            args.append("--rm")
            args.append(package.identifier)

        default:
            args.append(package.runtimeHint)
            args.append(package.identifier)
        }

        if let runtimeArgs = package.runtimeArguments {
            args.append(contentsOf: runtimeArgs)
        }

        return args
    }
}
