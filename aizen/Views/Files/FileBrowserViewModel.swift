//
//  FileBrowserViewModel.swift
//  aizen
//
//  View model for file browser state management
//

import Foundation
import SwiftUI
import Combine
import CoreData

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
}

struct OpenFileInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let path: String
    var content: String
    var hasUnsavedChanges: Bool

    init(id: UUID = UUID(), name: String, path: String, content: String, hasUnsavedChanges: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.content = content
        self.hasUnsavedChanges = hasUnsavedChanges
    }

    static func == (lhs: OpenFileInfo, rhs: OpenFileInfo) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class FileBrowserViewModel: ObservableObject {
    @Published var currentPath: String
    @Published var openFiles: [OpenFileInfo] = []
    @Published var selectedFileId: UUID?
    @Published var expandedPaths: Set<String> = []

    private let worktree: Worktree
    private let viewContext: NSManagedObjectContext
    private var session: FileBrowserSession?

    init(worktree: Worktree, context: NSManagedObjectContext) {
        self.worktree = worktree
        self.viewContext = context
        self.currentPath = worktree.path ?? ""

        // Load or create session
        loadSession()
    }

    private func loadSession() {
        // Try to get existing session from worktree
        if let existingSession = worktree.fileBrowserSession {
            self.session = existingSession

            // Restore state from session
            if let currentPath = existingSession.currentPath {
                self.currentPath = currentPath
            }

            if let expandedPathsArray = existingSession.value(forKey: "expandedPaths") as? [String] {
                self.expandedPaths = Set(expandedPathsArray)
            }

            if let selectedPath = existingSession.selectedFilePath {
                // Restore selected file if it was open
                if let openPathsArray = existingSession.value(forKey: "openFilesPaths") as? [String],
                   openPathsArray.contains(selectedPath) {
                    // Will be restored when files are reopened
                }
            }

            // Restore open files
            if let openPathsArray = existingSession.value(forKey: "openFilesPaths") as? [String] {
                Task {
                    for path in openPathsArray {
                        await openFile(path: path)
                    }

                    // Restore selection after files are opened
                    if let selectedPath = existingSession.selectedFilePath,
                       let selectedFile = openFiles.first(where: { $0.path == selectedPath }) {
                        selectedFileId = selectedFile.id
                    }
                }
            }
        } else {
            // Create new session
            let newSession = FileBrowserSession(context: viewContext)
            newSession.id = UUID()
            newSession.currentPath = currentPath
            newSession.setValue([], forKey: "expandedPaths")
            newSession.setValue([], forKey: "openFilesPaths")
            newSession.worktree = worktree
            self.session = newSession

            saveSession()
        }
    }

    private func saveSession() {
        guard let session = session else { return }

        session.currentPath = currentPath
        session.setValue(Array(expandedPaths), forKey: "expandedPaths")
        session.setValue(openFiles.map { $0.path }, forKey: "openFilesPaths")
        session.selectedFilePath = openFiles.first(where: { $0.id == selectedFileId })?.path

        do {
            try viewContext.save()
        } catch {
            print("Error saving FileBrowserSession: \(error)")
        }
    }

    func listDirectory(path: String) throws -> [FileItem] {
        let url = URL(fileURLWithPath: path)
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return contents.map { fileURL in
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return FileItem(
                name: fileURL.lastPathComponent,
                path: fileURL.path,
                isDirectory: isDir
            )
        }.sorted { item1, item2 in
            if item1.isDirectory != item2.isDirectory {
                return item1.isDirectory
            }
            return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
        }
    }

    func openFile(path: String) async {
        // Check if already open
        if let existing = openFiles.first(where: { $0.path == path }) {
            selectedFileId = existing.id
            return
        }

        // Load file content
        let fileURL = URL(fileURLWithPath: path)
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return
        }

        let fileInfo = OpenFileInfo(
            name: fileURL.lastPathComponent,
            path: path,
            content: content
        )

        openFiles.append(fileInfo)
        selectedFileId = fileInfo.id
        saveSession()
    }

    func closeFile(id: UUID) {
        openFiles.removeAll { $0.id == id }
        if selectedFileId == id {
            selectedFileId = openFiles.last?.id
        }
        saveSession()
    }

    func saveFile(id: UUID) throws {
        guard let index = openFiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let file = openFiles[index]
        try file.content.write(toFile: file.path, atomically: true, encoding: .utf8)
        openFiles[index].hasUnsavedChanges = false
    }

    func updateFileContent(id: UUID, content: String) {
        guard let index = openFiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        openFiles[index].content = content
        openFiles[index].hasUnsavedChanges = true
    }

    func toggleExpanded(path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
        saveSession()
    }

    func isExpanded(path: String) -> Bool {
        expandedPaths.contains(path)
    }
}
