//
//  WorktreeTabStateManager.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorktreeTabStateManager {
    let worktree: Worktree
    @Binding var tabStatesData: String
    @Binding var selectedTab: String

    func loadTabState() {
        guard let worktreeId = worktree.id?.uuidString else { return }

        if let data = tabStatesData.data(using: .utf8),
           let tabStates = try? JSONDecoder().decode([String: String].self, from: data),
           let savedTab = tabStates[worktreeId] {
            selectedTab = savedTab
        } else {
            selectedTab = "chat"
        }
    }

    func saveTabState() {
        guard let worktreeId = worktree.id?.uuidString else { return }

        var tabStates: [String: String] = [:]
        if let data = tabStatesData.data(using: .utf8),
           let existing = try? JSONDecoder().decode([String: String].self, from: data) {
            tabStates = existing
        }

        tabStates[worktreeId] = selectedTab

        if let encoded = try? JSONEncoder().encode(tabStates),
           let jsonString = String(data: encoded, encoding: .utf8) {
            tabStatesData = jsonString
        }
    }
}
