//
//  ACPTerminalTypes.swift
//  aizen
//
//  Agent Client Protocol - Terminal Types
//

import Foundation

// MARK: - Terminal Types

struct TerminalId: Codable, Hashable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct CreateTerminalRequest: Codable {
    let command: String
    let args: [String]?
    let cwd: String?
    let env: [String: String]?
    let outputLimit: Int?

    enum CodingKeys: String, CodingKey {
        case command, args, cwd, env
        case outputLimit = "output_limit"
    }
}

struct CreateTerminalResponse: Codable {
    let terminalId: TerminalId

    enum CodingKeys: String, CodingKey {
        case terminalId = "terminal_id"
    }
}

struct TerminalOutputRequest: Codable {
    let terminalId: TerminalId

    enum CodingKeys: String, CodingKey {
        case terminalId = "terminal_id"
    }
}

struct TerminalOutputResponse: Codable {
    let output: String
    let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case output
        case exitCode = "exit_code"
    }
}

struct WaitForExitRequest: Codable {
    let terminalId: TerminalId

    enum CodingKeys: String, CodingKey {
        case terminalId = "terminal_id"
    }
}

struct KillTerminalRequest: Codable {
    let terminalId: TerminalId

    enum CodingKeys: String, CodingKey {
        case terminalId = "terminal_id"
    }
}

struct ReleaseTerminalRequest: Codable {
    let terminalId: TerminalId

    enum CodingKeys: String, CodingKey {
        case terminalId = "terminal_id"
    }
}
