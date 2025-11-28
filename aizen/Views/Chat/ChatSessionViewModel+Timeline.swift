//
//  ChatSessionViewModel+Timeline.swift
//  aizen
//
//  Timeline and scrolling operations for chat sessions
//

import Foundation
import SwiftUI

extension ChatSessionViewModel {
    // MARK: - Timeline

    /// Full rebuild - used only for initial load or major state changes
    func rebuildTimeline() {
        timelineItems = (messages.map { .message($0) } + toolCalls.map { .toolCall($0) })
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Sync messages incrementally - update existing or insert new
    func syncMessages(_ newMessages: [MessageItem]) {
        let oldIds = Set(messages.map { $0.id })
        let newIds = Set(newMessages.map { $0.id })

        withAnimation(.easeInOut(duration: 0.2)) {
            // Update existing messages (content may have changed during streaming)
            for newMsg in newMessages where oldIds.contains(newMsg.id) {
                if let idx = timelineItems.firstIndex(where: { $0.id == newMsg.id }) {
                    timelineItems[idx] = .message(newMsg)
                }
            }

            // Insert new messages
            let addedIds = newIds.subtracting(oldIds)
            for newMsg in newMessages where addedIds.contains(newMsg.id) {
                insertTimelineItem(.message(newMsg))
            }
        }

        messages = newMessages
    }

    /// Sync tool calls incrementally - update existing or insert new
    func syncToolCalls(_ newToolCalls: [ToolCall]) {
        let oldIds = Set(toolCalls.map { $0.id })
        let newIds = Set(newToolCalls.map { $0.id })

        withAnimation(.easeInOut(duration: 0.2)) {
            // Update existing tool calls (status/content may change)
            for newCall in newToolCalls where oldIds.contains(newCall.id) {
                if let idx = timelineItems.firstIndex(where: { $0.id == newCall.id }) {
                    timelineItems[idx] = .toolCall(newCall)
                }
            }

            // Insert new tool calls
            let addedIds = newIds.subtracting(oldIds)
            for newCall in newToolCalls where addedIds.contains(newCall.id) {
                insertTimelineItem(.toolCall(newCall))
            }
        }

        toolCalls = newToolCalls
    }

    /// Insert timeline item maintaining sorted order by timestamp
    private func insertTimelineItem(_ item: TimelineItem) {
        let timestamp = item.timestamp

        // Binary search for insert position
        var low = 0
        var high = timelineItems.count

        while low < high {
            let mid = (low + high) / 2
            if timelineItems[mid].timestamp < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }

        timelineItems.insert(item, at: low)
    }

    // MARK: - Tool Call Grouping

    /// Get child tool calls for a parent Task
    func childToolCalls(for parentId: String) -> [ToolCall] {
        toolCalls.filter { $0.parentToolCallId == parentId }
    }

    /// Check if a tool call has children (is a Task with nested calls)
    func hasChildToolCalls(toolCallId: String) -> Bool {
        toolCalls.contains { $0.parentToolCallId == toolCallId }
    }

    // MARK: - Scrolling

    func scrollToBottom() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.3)) {
                if let lastMessage = messages.last {
                    scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                } else if isProcessing {
                    scrollProxy?.scrollTo("processing", anchor: .bottom)
                }
            }
        }
    }
}
