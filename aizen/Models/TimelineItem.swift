//
//  TimelineItem.swift
//  aizen
//
//  Timeline item combining messages and tool calls
//

import Foundation

enum TimelineItem {
    case message(MessageItem)
    case toolCall(ToolCall)

    var id: String {
        switch self {
        case .message(let msg):
            return msg.id
        case .toolCall(let tool):
            return tool.id
        }
    }

    var timestamp: Date {
        switch self {
        case .message(let msg):
            return msg.timestamp
        case .toolCall(let tool):
            return tool.timestamp
        }
    }
}
