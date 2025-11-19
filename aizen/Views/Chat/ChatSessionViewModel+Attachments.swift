//
//  ChatSessionViewModel+Attachments.swift
//  aizen
//
//  Attachment handling for chat sessions
//

import Foundation
import SwiftUI

extension ChatSessionViewModel {
    // MARK: - Attachment Management

    func removeAttachment(_ attachment: URL) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            attachments.removeAll { $0 == attachment }
        }
    }
}
