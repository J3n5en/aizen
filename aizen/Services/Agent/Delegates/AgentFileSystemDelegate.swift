//
//  AgentFileSystemDelegate.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Actor responsible for handling file system operations for agent sessions
actor AgentFileSystemDelegate {

    // MARK: - Initialization

    init() {}

    // MARK: - File Operations

    /// Handle file read request from agent
    func handleFileReadRequest(_ path: String, startLine: Int?, endLine: Int?) async throws -> ReadTextFileResponse {
        let url = URL(fileURLWithPath: path)
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        let filteredContent: String
        if let start = startLine, let end = endLine {
            let startIdx = max(0, start - 1)
            let endIdx = min(lines.count, end)
            filteredContent = lines[startIdx..<endIdx].joined(separator: "\n")
        } else {
            filteredContent = content
        }

        return ReadTextFileResponse(content: filteredContent, totalLines: lines.count)
    }

    /// Handle file write request from agent
    func handleFileWriteRequest(_ path: String, content: String) async throws -> WriteTextFileResponse {
        let url = URL(fileURLWithPath: path)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return WriteTextFileResponse(success: true)
    }
}
