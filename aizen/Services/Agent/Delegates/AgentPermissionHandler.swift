//
//  AgentPermissionHandler.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import Combine

/// Main actor class responsible for handling permission requests from agents
@MainActor
class AgentPermissionHandler: ObservableObject {

    // MARK: - Published Properties

    @Published var permissionRequest: RequestPermissionRequest?
    @Published var showingPermissionAlert: Bool = false

    // MARK: - Private Properties

    private var permissionContinuation: CheckedContinuation<RequestPermissionResponse, Never>?

    // MARK: - Initialization

    init() {}

    // MARK: - Permission Handling

    /// Handle permission request from agent - suspends until user responds
    func handlePermissionRequest(request: RequestPermissionRequest) async -> RequestPermissionResponse {
        return await withCheckedContinuation { continuation in
            self.permissionRequest = request
            self.showingPermissionAlert = true
            self.permissionContinuation = continuation
        }
    }

    /// Respond to a permission request with user's choice
    func respondToPermission(optionId: String) {
        showingPermissionAlert = false
        permissionRequest = nil

        if let continuation = permissionContinuation {
            let outcome = PermissionOutcome(optionId: optionId)
            let response = RequestPermissionResponse(outcome: outcome)
            continuation.resume(returning: response)
            permissionContinuation = nil
        }
    }

    /// Cancel any pending permission request
    func cancelPendingRequest() {
        if let continuation = permissionContinuation {
            let outcome = PermissionOutcome(optionId: "deny")
            let response = RequestPermissionResponse(outcome: outcome)
            continuation.resume(returning: response)
            permissionContinuation = nil
        }

        showingPermissionAlert = false
        permissionRequest = nil
    }
}
