//
//  AgentTerminalDelegate.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Actor responsible for handling terminal operations for agent sessions
actor AgentTerminalDelegate {

    // MARK: - Private Properties

    private var terminals: [String: Process] = [:]
    private var terminalOutputs: [String: String] = [:]

    // MARK: - Initialization

    init() {}

    // MARK: - Terminal Operations

    /// Create a new terminal process
    func handleTerminalCreate(
        command: String,
        args: [String]?,
        cwd: String?,
        env: [String: String]?,
        outputLimit: Int?
    ) async throws -> CreateTerminalResponse {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args ?? []

        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        if let env = env {
            process.environment = env
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let terminalIdValue = UUID().uuidString
        let terminalId = TerminalId(terminalIdValue)

        terminals[terminalIdValue] = process
        terminalOutputs[terminalIdValue] = ""

        // Capture output asynchronously
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                Task {
                    await self?.appendOutput(terminalId: terminalIdValue, output: output)
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                Task {
                    await self?.appendOutput(terminalId: terminalIdValue, output: output)
                }
            }
        }

        try process.run()
        return CreateTerminalResponse(terminalId: terminalId)
    }

    /// Get output from a terminal process
    func handleTerminalOutput(terminalId: TerminalId) async throws -> TerminalOutputResponse {
        guard let process = terminals[terminalId.value] else {
            throw NSError(
                domain: "AgentTerminalDelegate",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Terminal not found"]
            )
        }

        let output = terminalOutputs[terminalId.value] ?? ""
        let exitCode = process.isRunning ? nil : Int(process.terminationStatus)

        // Clear the accumulated output after reading
        terminalOutputs[terminalId.value] = ""

        return TerminalOutputResponse(output: output, exitCode: exitCode)
    }

    /// Clean up all terminals
    func cleanup() async {
        for (_, process) in terminals {
            if process.isRunning {
                process.terminate()
            }
        }
        terminals.removeAll()
        terminalOutputs.removeAll()
    }

    // MARK: - Private Helpers

    private func appendOutput(terminalId: String, output: String) {
        terminalOutputs[terminalId, default: ""] += output
    }
}
