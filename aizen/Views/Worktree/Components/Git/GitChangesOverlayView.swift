//
//  GitChangesOverlayView.swift
//  aizen
//
//  Full-screen overlay for viewing all git changes
//

import SwiftUI

struct GitChangesOverlayView: View {
    let worktreePath: String
    let repository: Repository
    let repositoryManager: RepositoryManager
    let gitStatus: GitStatus
    let isOperationPending: Bool
    let onClose: () -> Void

    // Git operation callbacks
    var onStageFile: (String) -> Void
    var onUnstageFile: (String) -> Void
    var onStageAll: (@escaping () -> Void) -> Void
    var onUnstageAll: () -> Void
    var onCommit: (String) -> Void
    var onAmendCommit: (String) -> Void
    var onCommitWithSignoff: (String) -> Void
    var onSwitchBranch: (String) -> Void
    var onCreateBranch: (String) -> Void
    var onFetch: () -> Void
    var onPull: () -> Void
    var onPush: () -> Void

    @State private var diffOutput: String = ""
    @State private var rightPanelWidth: CGFloat = 350
    @State private var visibleFile: String?
    @State private var scrollToFile: String?

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("diffFontSize") private var diffFontSize: Double = 11.0

    private let minRightPanelWidth: CGFloat = 300
    private let maxRightPanelWidth: CGFloat = 500

    private var allChangedFiles: [String] {
        let files = Set(
            gitStatus.stagedFiles +
            gitStatus.modifiedFiles +
            gitStatus.untrackedFiles +
            gitStatus.conflictedFiles
        )
        return Array(files).sorted()
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: All files diff scroll
            leftPanel
                .frame(maxWidth: .infinity)

            // Divider
            resizableDivider

            // Right: Git sidebar
            rightPanel
                .frame(width: rightPanelWidth)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onExitCommand {
            onClose()
        }
    }

    private var leftPanelHeader: some View {
        HStack(spacing: 8) {
            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(gitStatus.currentBranch ?? "HEAD")
                .font(.system(size: 13, weight: .medium))

            CopyButton(text: gitStatus.currentBranch ?? "", iconSize: 11)

            Spacer()

            HStack(spacing: 8) {
                Text("+\(gitStatus.additions)")
                    .foregroundStyle(.green)
                Text("-\(gitStatus.deletions)")
                    .foregroundStyle(.red)
                Text("\(allChangedFiles.count) files")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var leftPanel: some View {
        VStack(spacing: 0) {
            leftPanelHeader
            Divider()

            if allChangedFiles.isEmpty {
                AllFilesDiffEmptyView()
            } else {
                DiffView(
                    diffOutput: diffOutput,
                    fontSize: diffFontSize,
                    fontFamily: editorFontFamily,
                    repoPath: worktreePath,
                    scrollToFile: scrollToFile,
                    onFileVisible: { file in
                        visibleFile = file
                    },
                    onOpenFile: { file in
                        let fullPath = (worktreePath as NSString).appendingPathComponent(file)
                        NotificationCenter.default.post(
                            name: .openFileInEditor,
                            object: nil,
                            userInfo: ["path": fullPath]
                        )
                        onClose()
                    }
                )
            }
        }
        .task {
            await loadFullDiff()
        }
    }

    private func loadFullDiff() async {
        let executor = GitCommandExecutor()
        var output = ""

        // Get diff for tracked files (--no-pager to avoid hanging)
        if let headDiff = try? await executor.executeGit(arguments: ["--no-pager", "diff", "HEAD"], at: worktreePath) {
            output = headDiff
        } else if let basicDiff = try? await executor.executeGit(arguments: ["--no-pager", "diff"], at: worktreePath) {
            output = basicDiff
        }

        // Add untracked files as "new file" diffs
        for file in gitStatus.untrackedFiles {
            let fullPath = (worktreePath as NSString).appendingPathComponent(file)
            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines)
                var fileDiff = "diff --git a/\(file) b/\(file)\n"
                fileDiff += "new file mode 100644\n"
                fileDiff += "--- /dev/null\n"
                fileDiff += "+++ b/\(file)\n"
                fileDiff += "@@ -0,0 +1,\(lines.count) @@\n"
                for line in lines {
                    fileDiff += "+\(line)\n"
                }
                output += fileDiff
            }
        }

        diffOutput = output
    }

    private func reloadDiff() {
        Task {
            await loadFullDiff()
        }
    }

    private var resizableDivider: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = rightPanelWidth - value.translation.width
                                rightPanelWidth = min(max(newWidth, minRightPanelWidth), maxRightPanelWidth)
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            )
    }

    private var rightPanel: some View {
        GitSidebarView(
            worktreePath: worktreePath,
            repository: repository,
            repositoryManager: repositoryManager,
            onClose: onClose,
            gitStatus: gitStatus,
            isOperationPending: isOperationPending,
            selectedDiffFile: visibleFile,
            onStageFile: { file in
                onStageFile(file)
                reloadDiff()
            },
            onUnstageFile: { file in
                onUnstageFile(file)
                reloadDiff()
            },
            onStageAll: { completion in
                onStageAll {
                    reloadDiff()
                    completion()
                }
            },
            onUnstageAll: {
                onUnstageAll()
                reloadDiff()
            },
            onCommit: { message in
                onCommit(message)
                reloadDiff()
            },
            onAmendCommit: { message in
                onAmendCommit(message)
                reloadDiff()
            },
            onCommitWithSignoff: { message in
                onCommitWithSignoff(message)
                reloadDiff()
            },
            onSwitchBranch: { branch in
                onSwitchBranch(branch)
                reloadDiff()
            },
            onCreateBranch: onCreateBranch,
            onFetch: onFetch,
            onPull: {
                onPull()
                reloadDiff()
            },
            onPush: onPush,
            onFileClick: { file in
                visibleFile = file  // Immediately highlight
                scrollToFile = file
                // Reset after a moment to allow re-clicking the same file
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scrollToFile = nil
                }
            }
        )
    }
}
