//
//  MCPManager.swift
//  aizen
//
//  Orchestrates MCP server installation, removal, and status tracking
//

import Combine
import Foundation

// MARK: - Process Executor (Background)

/// Executes MCP commands on a background thread to avoid blocking the main thread.
private actor MCPProcessExecutor {
    private var cachedShellEnv: [String: String]?

    func run(_ command: MCPInstallCommand) async throws {
        let environment = await getShellEnvironment()
        try await executeProcess(command: command, environment: environment, captureOutput: false)
    }

    func runWithOutput(_ command: MCPInstallCommand) async throws -> String {
        let environment = await getShellEnvironment()
        return try await executeProcess(command: command, environment: environment, captureOutput: true)
    }

    private func getShellEnvironment() async -> [String: String] {
        if let cached = cachedShellEnv {
            return cached
        }
        let env = await ShellEnvironmentLoader.shared.loadShellEnvironment()
        cachedShellEnv = env
        return env
    }

    private func executeProcess(
        command: MCPInstallCommand,
        environment: [String: String],
        captureOutput: Bool
    ) async throws -> String {
        // Run process execution on a detached task to avoid blocking actor
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()

                // Use /usr/bin/env to search PATH if executable is not a full path
                if command.executable.hasPrefix("/") {
                    process.executableURL = URL(fileURLWithPath: command.executable)
                    process.arguments = command.arguments
                } else {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = [command.executable] + command.arguments
                }

                // Merge shell environment with command environment
                var processEnv = environment
                for (key, value) in command.environment {
                    processEnv[key] = value
                }
                process.environment = processEnv

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: MCPManagerError.processLaunchFailed(error.localizedDescription))
                    return
                }

                process.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    if captureOutput {
                        // For list commands, return output even on error (some agents exit non-zero but still output)
                        print("[MCPManager] Command exited with status \(process.terminationStatus): \(errorOutput)")
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: MCPManagerError.commandFailed(Int(process.terminationStatus), errorOutput))
                    }
                    return
                }

                continuation.resume(returning: output)
            }
        }
    }
}

// MARK: - MCP Manager (Main Actor)

@MainActor
class MCPManager: ObservableObject {
    static let shared = MCPManager()

    @Published var installedServers: [String: [MCPInstalledServer]] = [:]
    @Published var isSyncing: Set<String> = []
    @Published var isInstalling = false
    @Published var isRemoving = false
    @Published var lastError: MCPManagerError?

    private let executor = MCPProcessExecutor()

    private init() {}

    // MARK: - Install Package

    func installPackage(
        server: MCPServer,
        package: MCPPackage,
        agentId: String,
        agentPath: String?,
        env: [String: String]
    ) async throws {
        isInstalling = true
        lastError = nil
        defer { isInstalling = false }

        let serverName = extractServerName(from: server.name)
        let command = MCPInstallCommandBuilder.buildInstallCommand(
            for: agentId,
            agentPath: agentPath,
            serverName: serverName,
            package: package,
            env: env
        )

        try await executor.run(command)

        // Refresh installed list from agent
        await syncInstalled(agentId: agentId, agentPath: agentPath)
    }

    // MARK: - Install Remote

    func installRemote(
        server: MCPServer,
        remote: MCPRemote,
        agentId: String,
        agentPath: String?,
        env: [String: String]
    ) async throws {
        isInstalling = true
        lastError = nil
        defer { isInstalling = false }

        let serverName = extractServerName(from: server.name)
        let command = MCPInstallCommandBuilder.buildRemoteInstallCommand(
            for: agentId,
            agentPath: agentPath,
            serverName: serverName,
            remote: remote,
            env: env
        )

        try await executor.run(command)

        // Refresh installed list from agent
        await syncInstalled(agentId: agentId, agentPath: agentPath)
    }

    // MARK: - Remove

    func remove(serverName: String, agentId: String, agentPath: String?) async throws {
        isRemoving = true
        lastError = nil
        defer { isRemoving = false }

        let command = MCPInstallCommandBuilder.buildRemoveCommand(
            for: agentId,
            agentPath: agentPath,
            serverName: serverName
        )

        try await executor.run(command)

        // Refresh installed list from agent
        await syncInstalled(agentId: agentId, agentPath: agentPath)
    }

    // MARK: - Sync (Source of Truth: agent mcp list)

    func syncInstalled(agentId: String, agentPath: String?) async {
        isSyncing.insert(agentId)
        defer { isSyncing.remove(agentId) }

        let command = MCPInstallCommandBuilder.buildListCommand(
            for: agentId,
            agentPath: agentPath
        )

        print("[MCPManager] Syncing installed servers for \(agentId)")
        print("[MCPManager] Command: \(command.executable) \(command.arguments.joined(separator: " "))")

        do {
            let output = try await executor.runWithOutput(command)
            print("[MCPManager] Output:\n\(output)")
            let parsedServers = parseListOutput(output, agentId: agentId)
            print("[MCPManager] Parsed \(parsedServers.count) servers: \(parsedServers.map { $0.serverName })")
            installedServers[agentId] = parsedServers
        } catch {
            print("[MCPManager] Failed to sync MCP servers for \(agentId): \(error)")
            // Don't clear on error, keep previous state
        }
    }

    func isSyncingServers(for agentId: String) -> Bool {
        isSyncing.contains(agentId)
    }

    // MARK: - Query

    func isInstalled(serverName: String, agentId: String) -> Bool {
        let name = extractServerName(from: serverName)
        return installedServers[agentId]?.contains { $0.serverName.lowercased() == name.lowercased() } ?? false
    }

    func servers(for agentId: String) -> [MCPInstalledServer] {
        installedServers[agentId] ?? []
    }

    // MARK: - Private

    /// Parse output like: "context7: https://mcp.context7.com/mcp (HTTP) - ✓ Connected"
    private func parseListOutput(_ output: String, agentId: String) -> [MCPInstalledServer] {
        var servers: [MCPInstalledServer] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and status messages
            guard !trimmed.isEmpty,
                  !trimmed.lowercased().hasPrefix("checking"),
                  !trimmed.lowercased().hasPrefix("no mcp"),
                  trimmed.contains(":") else {
                continue
            }

            // Parse format: "<name>: <url/command> (<type>) - <status>"
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count >= 1 else { continue }

            let serverName = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard !serverName.isEmpty else { continue }

            // Try to extract transport type from parentheses
            var transportType: String? = nil
            if let openParen = trimmed.firstIndex(of: "("),
               let closeParen = trimmed.firstIndex(of: ")"),
               openParen < closeParen {
                let startIndex = trimmed.index(after: openParen)
                transportType = String(trimmed[startIndex..<closeParen])
            }

            let installed = MCPInstalledServer(
                serverName: serverName,
                displayName: serverName,
                agentId: agentId,
                packageType: nil,
                transportType: transportType?.lowercased(),
                configuredEnv: [:]
            )
            servers.append(installed)
        }

        return servers
    }

    private func extractServerName(from fullName: String) -> String {
        if let lastComponent = fullName.split(separator: "/").last {
            return String(lastComponent)
        }
        return fullName
    }
}

// MARK: - Errors

enum MCPManagerError: LocalizedError {
    case processLaunchFailed(String)
    case commandFailed(Int, String)
    case agentNotFound(String)

    var errorDescription: String? {
        switch self {
        case .processLaunchFailed(let reason):
            return "Failed to launch process: \(reason)"
        case .commandFailed(let code, let output):
            return "Command failed (\(code)): \(output)"
        case .agentNotFound(let agentId):
            return "Agent not found: \(agentId)"
        }
    }
}
