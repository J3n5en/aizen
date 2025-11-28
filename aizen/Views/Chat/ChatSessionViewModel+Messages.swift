//
//  ChatSessionViewModel+Messages.swift
//  aizen
//
//  Message operations for chat sessions
//

import Foundation
import SwiftUI

extension ChatSessionViewModel {
    // MARK: - Message Operations

    func sendMessage() {
        let messageText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        let messageAttachments = attachments

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            inputText = ""
            attachments = []
            isProcessing = true
            // Re-enable auto-scroll when user sends a message
            isNearBottom = true
        }

        Task {
            do {
                guard let agentSession = self.currentAgentSession else {
                    throw NSError(domain: "ChatSessionView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No agent session"])
                }

                if !agentSession.isActive {
                    try await agentSession.start(agentName: self.selectedAgent, workingDir: self.worktree.path!)
                }

                try await agentSession.sendMessage(content: messageText, attachments: messageAttachments)

                self.messageHandler.saveMessage(content: messageText, role: "user", agentName: self.selectedAgent)
                self.scrollToBottom()
            } catch {
                let errorMessage = MessageItem(
                    id: UUID().uuidString,
                    role: .system,
                    content: String(localized: "chat.error.prefix \(error.localizedDescription)"),
                    timestamp: Date()
                )

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.messages.append(errorMessage)
                    self.rebuildTimeline()
                }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.attachments = messageAttachments
                }
            }
            // isProcessing is now derived from message state in setupSessionObservers
        }
    }

    func cancelCurrentPrompt() {
        Task {
            await currentAgentSession?.cancelCurrentPrompt()
        }
    }

    func loadMessages() {
        guard let messageSet = session.messages as? Set<ChatMessage> else {
            return
        }

        let sortedMessages = messageSet.sorted { $0.timestamp! < $1.timestamp! }

        let loadedMessages = sortedMessages.map { msg in
            MessageItem(
                id: msg.id!.uuidString,
                role: messageRoleFromString(msg.role!),
                content: msg.contentJSON!,
                timestamp: msg.timestamp!
            )
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            messages = loadedMessages
            rebuildTimeline()
        }

        scrollToBottom()
    }

    // MARK: - Private Helpers

    func messageRoleFromString(_ role: String) -> MessageRole {
        switch role.lowercased() {
        case "user":
            return .user
        case "agent":
            return .agent
        default:
            return .system
        }
    }
}
