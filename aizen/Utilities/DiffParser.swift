//
//  DiffParser.swift
//  aizen
//
//  Unified diff parsing utilities
//

import Foundation

enum DiffParser {
    /// Parse unified diff output into DiffLine array
    static func parseUnifiedDiff(_ diffOutput: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        var lineCounter = 0
        var oldLineNum = 0
        var newLineNum = 0

        let diffLines = diffOutput.components(separatedBy: .newlines)

        for line in diffLines {
            if line.hasPrefix("@@") {
                // Hunk header
                let components = line.components(separatedBy: " ")
                for component in components {
                    if component.hasPrefix("-") && !component.hasPrefix("---") {
                        let rangeStr = String(component.dropFirst())
                        if let num = rangeStr.components(separatedBy: ",").first, let start = Int(num) {
                            oldLineNum = start - 1
                        }
                    } else if component.hasPrefix("+") && !component.hasPrefix("+++") {
                        let rangeStr = String(component.dropFirst())
                        if let num = rangeStr.components(separatedBy: ",").first, let start = Int(num) {
                            newLineNum = start - 1
                        }
                    }
                }

                lines.append(DiffLine(
                    lineNumber: lineCounter,
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    content: line,
                    type: .header
                ))
                lineCounter += 1
            } else if line.hasPrefix("+++") || line.hasPrefix("---") ||
                      line.hasPrefix("diff ") || line.hasPrefix("index ") {
                // Skip file headers
                continue
            } else if line.hasPrefix("+") {
                // Added line
                newLineNum += 1
                lines.append(DiffLine(
                    lineNumber: lineCounter,
                    oldLineNumber: nil,
                    newLineNumber: String(newLineNum),
                    content: String(line.dropFirst()),
                    type: .added
                ))
                lineCounter += 1
            } else if line.hasPrefix("-") {
                // Deleted line
                oldLineNum += 1
                lines.append(DiffLine(
                    lineNumber: lineCounter,
                    oldLineNumber: String(oldLineNum),
                    newLineNumber: nil,
                    content: String(line.dropFirst()),
                    type: .deleted
                ))
                lineCounter += 1
            } else if line.hasPrefix(" ") {
                // Context line
                oldLineNum += 1
                newLineNum += 1
                lines.append(DiffLine(
                    lineNumber: lineCounter,
                    oldLineNumber: String(oldLineNum),
                    newLineNumber: String(newLineNum),
                    content: String(line.dropFirst()),
                    type: .context
                ))
                lineCounter += 1
            }
        }

        return lines
    }

    /// Split multi-file diff output by file path
    static func splitDiffByFile(_ diffOutput: String) -> [String: [DiffLine]] {
        var result: [String: [DiffLine]] = [:]

        // Split by "diff --git" boundaries
        let chunks = diffOutput.components(separatedBy: "\ndiff --git ")

        for (index, chunk) in chunks.enumerated() {
            let diffChunk = index == 0 ? chunk : "diff --git " + chunk

            // Skip if not a valid diff chunk
            guard diffChunk.hasPrefix("diff --git ") else { continue }

            // Extract file path from "+++ b/<path>" line - more reliable than diff --git line
            var filePath: String?
            for line in diffChunk.components(separatedBy: .newlines) {
                if line.hasPrefix("+++ b/") {
                    filePath = String(line.dropFirst(6))
                    break
                }
            }

            guard let path = filePath else { continue }

            let lines = parseUnifiedDiff(diffChunk)
            if !lines.isEmpty {
                result[path] = lines
            }
        }

        return result
    }
}
