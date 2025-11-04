//
//  NPMAgentInstaller.swift
//  aizen
//
//  NPM package installation for ACP agents
//

import Foundation

actor NPMAgentInstaller {
    static let shared = NPMAgentInstaller()

    private let shellLoader: ShellEnvironmentLoader

    init(shellLoader: ShellEnvironmentLoader = .shared) {
        self.shellLoader = shellLoader
    }

    // MARK: - Installation

    func install(package: String, targetDir: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "install", "--prefix", targetDir, package]

        // Load shell environment to get PATH with npm
        let shellEnv = await shellLoader.loadShellEnvironment()
        process.environment = shellEnv

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AgentInstallError.installFailed(message: errorMessage)
        }
    }
}
