//
//  GitDomainService.swift
//  aizen
//
//  Base protocol for Git domain services with shared functionality
//

import Foundation

/// Protocol for Git domain services that provides common execution and parsing utilities
protocol GitDomainService: Actor {
    var executor: GitCommandExecutor { get }
}

extension GitDomainService {
    /// Execute git command and return trimmed output
    func execute(_ args: [String], at path: String) async throws -> String {
        let output = try await executor.executeGit(arguments: args, at: path)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Execute git command without caring about output (for side-effect operations)
    func executeVoid(_ args: [String], at path: String) async throws {
        _ = try await executor.executeGit(arguments: args, at: path)
    }

    /// Execute git command and return parsed lines (empty lines removed)
    func executeLines(_ args: [String], at path: String) async throws -> [String] {
        let output = try await execute(args, at: path)
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
