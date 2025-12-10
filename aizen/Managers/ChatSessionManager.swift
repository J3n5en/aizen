//
//  ChatSessionManager.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

@MainActor
class ChatSessionManager {
    static let shared = ChatSessionManager()

    private var agentSessions: [UUID: AgentSession] = [:]
    private var pendingMessages: [UUID: String] = [:]
    private var pendingInputText: [UUID: String] = [:]
    private var pendingAttachments: [UUID: [ChatAttachment]] = [:]

    private init() {}

    func getAgentSession(for chatSessionId: UUID) -> AgentSession? {
        return agentSessions[chatSessionId]
    }

    func setAgentSession(_ session: AgentSession, for chatSessionId: UUID) {
        agentSessions[chatSessionId] = session
    }

    func removeAgentSession(for chatSessionId: UUID) {
        agentSessions.removeValue(forKey: chatSessionId)
    }

    // MARK: - Pending Messages

    func setPendingMessage(_ message: String, for chatSessionId: UUID) {
        pendingMessages[chatSessionId] = message
    }

    func consumePendingMessage(for chatSessionId: UUID) -> String? {
        return pendingMessages.removeValue(forKey: chatSessionId)
    }

    // MARK: - Pending Input Text (for prefilling input field without auto-sending)

    func setPendingInputText(_ text: String, for chatSessionId: UUID) {
        pendingInputText[chatSessionId] = text
    }

    func consumePendingInputText(for chatSessionId: UUID) -> String? {
        return pendingInputText.removeValue(forKey: chatSessionId)
    }

    // MARK: - Pending Attachments

    func setPendingAttachments(_ attachments: [ChatAttachment], for chatSessionId: UUID) {
        pendingAttachments[chatSessionId] = attachments
    }

    func consumePendingAttachments(for chatSessionId: UUID) -> [ChatAttachment]? {
        return pendingAttachments.removeValue(forKey: chatSessionId)
    }
}
