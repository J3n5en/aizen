//
//  ContentView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var repositoryManager: RepositoryManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)],
        animation: .default)
    private var workspaces: FetchedResults<Workspace>

    @State private var selectedWorkspace: Workspace?
    @State private var selectedRepository: Repository?
    @State private var selectedWorktree: Worktree?
    @State private var searchText = ""
    @State private var showingAddRepository = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var previousWorktree: Worktree?
    @AppStorage("hasShownOnboarding") private var hasShownOnboarding = false
    @State private var showingOnboarding = false

    init(context: NSManagedObjectContext) {
        _repositoryManager = StateObject(wrappedValue: RepositoryManager(viewContext: context))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left sidebar - workspaces and repositories
            WorkspaceSidebarView(
                workspaces: Array(workspaces),
                selectedWorkspace: $selectedWorkspace,
                selectedRepository: $selectedRepository,
                selectedWorktree: $selectedWorktree,
                searchText: $searchText,
                showingAddRepository: $showingAddRepository,
                repositoryManager: repositoryManager
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } content: {
            // Middle panel - worktree list or detail
            if let repository = selectedRepository {
                WorktreeListView(
                    repository: repository,
                    selectedWorktree: $selectedWorktree,
                    repositoryManager: repositoryManager
                )
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
            } else {
                placeholderView(
                    titleKey: "contentView.selectRepository",
                    systemImage: "folder.badge.gearshape",
                    descriptionKey: "contentView.selectRepositoryDescription"
                )
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
            }
        } detail: {
            // Right panel - worktree details
            if let worktree = selectedWorktree {
                WorktreeDetailView(
                    worktree: worktree,
                    repositoryManager: repositoryManager
                )
            } else {
                placeholderView(
                    titleKey: "contentView.selectWorktree",
                    systemImage: "arrow.triangle.branch",
                    descriptionKey: "contentView.selectWorktreeDescription"
                )
            }
        }
        .sheet(isPresented: $showingAddRepository) {
            if let workspace = selectedWorkspace ?? workspaces.first {
                RepositoryAddSheet(
                    workspace: workspace,
                    repositoryManager: repositoryManager,
                    onRepositoryAdded: { repository in
                        selectedWorktree = nil
                        selectedRepository = repository
                    }
                )
            }
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView()
        }
        .onAppear {
            if selectedWorkspace == nil {
                selectedWorkspace = workspaces.first
            }
            if !hasShownOnboarding {
                showingOnboarding = true
                hasShownOnboarding = true
            }
        }
        .onChange(of: selectedWorktree) { newValue in
            if let newWorktree = newValue, previousWorktree != newWorktree {
                withAnimation(.easeInOut(duration: 0.3)) {
                    columnVisibility = .doubleColumn
                }
                previousWorktree = newWorktree
            }
        }
        .onChange(of: selectedRepository) { newValue in
            if let repo = newValue, repo.isDeleted || repo.isFault {
                selectedRepository = nil
                selectedWorktree = nil
            } else if let repo = newValue {
                // Auto-select primary worktree when repository changes
                let worktrees = (repo.worktrees as? Set<Worktree>) ?? []
                selectedWorktree = worktrees.first(where: { $0.isPrimary })
            }
        }
    }
}

@ViewBuilder
private func placeholderView(
    titleKey: LocalizedStringKey,
    systemImage: String,
    descriptionKey: LocalizedStringKey
) -> some View {
    if #available(macOS 14.0, *) {
        ContentUnavailableView(
            titleKey,
            systemImage: systemImage,
            description: Text(descriptionKey)
        )
    } else {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(titleKey)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(descriptionKey)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ContentView(context: PersistenceController.preview.container.viewContext)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
