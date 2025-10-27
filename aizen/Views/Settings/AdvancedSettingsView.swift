//
//  AdvancedSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 27.10.25.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reset App")
                        .font(.headline)

                    Text("This will delete all workspaces, repositories, worktrees, and chat sessions. This action cannot be undone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset All Data", systemImage: "trash")
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .alert("Reset App?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetApp()
            }
        } message: {
            Text("This will permanently delete all your data including workspaces, repositories, worktrees, and chat sessions. The app will quit after reset.")
        }
    }

    private func resetApp() {
        // Clear Core Data
        let entities = ["Workspace", "Repository", "Worktree", "ChatSession", "ChatMessage"]
        for entity in entities {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            do {
                try viewContext.execute(deleteRequest)
            } catch {
                print("Failed to delete \(entity): \(error)")
            }
        }

        // Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        // Quit app
        NSApplication.shared.terminate(nil)
    }
}

#Preview {
    AdvancedSettingsView()
}
