//
//  ACPContentTypes.swift
//  aizen
//
//  Agent Client Protocol - Content Block Types
//

import Foundation

// MARK: - Content Types

enum ContentBlock: Codable {
    case text(TextContent)
    case image(ImageContent)
    case resource(ResourceContent)
    case audio(AudioContent)
    case embeddedResource(EmbeddedResourceContent)
    case diff(DiffContent)
    case terminalEmbed(TerminalEmbedContent)

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try TextContent(from: decoder))
        case "image":
            self = .image(try ImageContent(from: decoder))
        case "resource":
            self = .resource(try ResourceContent(from: decoder))
        case "audio":
            self = .audio(try AudioContent(from: decoder))
        case "embedded_resource":
            self = .embeddedResource(try EmbeddedResourceContent(from: decoder))
        case "diff":
            self = .diff(try DiffContent(from: decoder))
        case "terminal_embed":
            self = .terminalEmbed(try TerminalEmbedContent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .image(let content):
            try content.encode(to: encoder)
        case .resource(let content):
            try content.encode(to: encoder)
        case .audio(let content):
            try content.encode(to: encoder)
        case .embeddedResource(let content):
            try content.encode(to: encoder)
        case .diff(let content):
            try content.encode(to: encoder)
        case .terminalEmbed(let content):
            try content.encode(to: encoder)
        }
    }
}

struct TextContent: Codable {
    let type: String = "text"
    let text: String
}

struct ImageContent: Codable {
    let type: String = "image"
    let data: String
    let mimeType: String
}

struct ResourceContent: Codable {
    let type: String = "resource"
    let resource: ResourceData

    struct ResourceData: Codable {
        let uri: String
        let mimeType: String?
        let text: String?
        let blob: String?

        enum CodingKeys: String, CodingKey {
            case uri, mimeType, text, blob
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(uri, forKey: .uri)
            // Only encode non-nil optional fields
            if let mimeType = mimeType {
                try container.encode(mimeType, forKey: .mimeType)
            }
            if let text = text {
                try container.encode(text, forKey: .text)
            }
            if let blob = blob {
                try container.encode(blob, forKey: .blob)
            }
        }
    }

    init(uri: String, mimeType: String?, text: String?, blob: String?) {
        self.resource = ResourceData(uri: uri, mimeType: mimeType, text: text, blob: blob)
    }

    enum CodingKeys: String, CodingKey {
        case type, resource
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(resource, forKey: .resource)
    }
}

struct AudioContent: Codable {
    let type: String = "audio"
    let data: String
    let mimeType: String
}

struct EmbeddedResourceContent: Codable {
    let type: String = "embedded_resource"
    let uri: String
    let mimeType: String?
    let content: [ContentBlock]
}

struct DiffContent: Codable {
    let type: String = "diff"
    let oldText: String
    let newText: String
    let path: String?

    enum CodingKeys: String, CodingKey {
        case type, path
        case oldText = "old_text"
        case newText = "new_text"
    }
}

struct TerminalEmbedContent: Codable {
    let type: String = "terminal_embed"
    let terminalId: TerminalId
    let command: String
    let output: String
    let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case type, command, output
        case terminalId = "terminal_id"
        case exitCode = "exit_code"
    }
}

