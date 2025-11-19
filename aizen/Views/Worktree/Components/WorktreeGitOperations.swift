//
//  WorktreeGitOperations.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

struct WorktreeGitOperations {
    let gitRepositoryService: GitRepositoryService
    let repositoryManager: RepositoryManager
    let worktree: Worktree
    let logger: Logger

    private var gitOperationHandler: GitOperationHandler?

    init(
        gitRepositoryService: GitRepositoryService,
        repositoryManager: RepositoryManager,
        worktree: Worktree,
        logger: Logger
    ) {
        self.gitRepositoryService = gitRepositoryService
        self.repositoryManager = repositoryManager
        self.worktree = worktree
        self.logger = logger
    }

    private func ensureHandler() -> GitOperationHandler {
        GitOperationHandler(
            gitService: gitRepositoryService,
            repositoryManager: repositoryManager,
            logger: logger
        )
    }

    func stageFile(_ file: String) {
        ensureHandler().stageFile(file)
    }

    func unstageFile(_ file: String) {
        ensureHandler().unstageFile(file)
    }

    func stageAll(onComplete: @escaping () -> Void) {
        ensureHandler().stageAll(onComplete: onComplete)
    }

    func unstageAll() {
        ensureHandler().unstageAll()
    }

    func commit(_ message: String) {
        ensureHandler().commit(message)
    }

    func amendCommit(_ message: String) {
        ensureHandler().amendCommit(message)
    }

    func commitWithSignoff(_ message: String) {
        ensureHandler().commitWithSignoff(message)
    }

    func switchBranch(_ branch: String) {
        ensureHandler().switchBranch(branch, repository: worktree.repository)
    }

    func createBranch(_ name: String) {
        ensureHandler().createBranch(name, repository: worktree.repository)
    }

    func fetch() {
        ensureHandler().fetch(repository: worktree.repository)
    }

    func pull() {
        ensureHandler().pull(repository: worktree.repository)
    }

    func push() {
        ensureHandler().push(repository: worktree.repository)
    }
}
