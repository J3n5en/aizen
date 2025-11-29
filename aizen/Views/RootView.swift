//
//  RootView.swift
//  aizen
//
//  Root view that handles full-window overlays above the toolbar
//

import SwiftUI
import CoreData

struct RootView: View {
    let context: NSManagedObjectContext

    @State private var gitChangesContext: GitChangesContext?
    @StateObject private var repositoryManager: RepositoryManager

    init(context: NSManagedObjectContext) {
        self.context = context
        _repositoryManager = StateObject(wrappedValue: RepositoryManager(viewContext: context))
    }

    var body: some View {
        GeometryReader { geometry in
            ContentView(
                context: context,
                repositoryManager: repositoryManager,
                gitChangesContext: $gitChangesContext
            )
            .sheet(item: $gitChangesContext) { context in
                if let repository = context.worktree.repository, !context.worktree.isDeleted {
                    GitChangesOverlayContainer(
                        worktree: context.worktree,
                        repository: repository,
                        repositoryManager: repositoryManager,
                        gitRepositoryService: context.service,
                        showingGitChanges: Binding(
                            get: { gitChangesContext != nil },
                            set: { if !$0 { gitChangesContext = nil } }
                        )
                    )
                    .frame(
                        minWidth: max(900, geometry.size.width - 100),
                        idealWidth: geometry.size.width - 40,
                        minHeight: max(500, geometry.size.height - 100),
                        idealHeight: geometry.size.height - 40
                    )
                }
            }
        }
    }
}

// Context for git changes sheet
struct GitChangesContext: Identifiable {
    let id = UUID()
    let worktree: Worktree
    let service: GitRepositoryService
}
