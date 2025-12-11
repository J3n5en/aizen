//
//  DiffView.swift
//  aizen
//
//  NSTableView-based diff renderer for git changes
//

import SwiftUI
import AppKit

struct DiffView: NSViewRepresentable {
    // Input mode 1: Raw diff string (for multi-file view)
    private let diffOutput: String?

    // Input mode 2: Pre-parsed lines (for single-file view)
    private let preloadedLines: [DiffLine]?

    let fontSize: Double
    let fontFamily: String
    let repoPath: String
    let showFileHeaders: Bool
    let scrollToFile: String?
    let onFileVisible: ((String) -> Void)?
    let onOpenFile: ((String) -> Void)?
    let commentedLines: Set<String>
    let onAddComment: ((DiffLine, String) -> Void)?

    // Init for raw diff output (used by GitChangesOverlayView)
    init(
        diffOutput: String,
        fontSize: Double,
        fontFamily: String,
        repoPath: String = "",
        scrollToFile: String? = nil,
        onFileVisible: ((String) -> Void)? = nil,
        onOpenFile: ((String) -> Void)? = nil,
        commentedLines: Set<String> = [],
        onAddComment: ((DiffLine, String) -> Void)? = nil
    ) {
        self.diffOutput = diffOutput
        self.preloadedLines = nil
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.repoPath = repoPath
        self.showFileHeaders = true
        self.scrollToFile = scrollToFile
        self.onFileVisible = onFileVisible
        self.onOpenFile = onOpenFile
        self.commentedLines = commentedLines
        self.onAddComment = onAddComment
    }

    // Init for pre-parsed lines (used by FileDiffSectionView)
    init(
        lines: [DiffLine],
        fontSize: Double,
        fontFamily: String,
        repoPath: String = "",
        showFileHeaders: Bool = false,
        commentedLines: Set<String> = [],
        onAddComment: ((DiffLine, String) -> Void)? = nil
    ) {
        self.diffOutput = nil
        self.preloadedLines = lines
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.repoPath = repoPath
        self.showFileHeaders = showFileHeaders
        self.scrollToFile = nil
        self.onFileVisible = nil
        self.onOpenFile = nil
        self.commentedLines = commentedLines
        self.onAddComment = onAddComment
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()

        tableView.style = .plain
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsColumnSelection = false
        tableView.usesAutomaticRowHeights = true
        tableView.gridStyleMask = []
        tableView.gridColor = .clear

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diff"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        context.coordinator.tableView = tableView
        context.coordinator.repoPath = repoPath
        context.coordinator.showFileHeaders = showFileHeaders
        context.coordinator.setupScrollObserver(for: scrollView)

        if let lines = preloadedLines {
            context.coordinator.loadLines(lines, fontSize: fontSize, fontFamily: fontFamily)
        } else if let output = diffOutput {
            context.coordinator.parseAndReload(diffOutput: output, fontSize: fontSize, fontFamily: fontFamily)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onFileVisible = onFileVisible
        context.coordinator.onOpenFile = onOpenFile
        context.coordinator.repoPath = repoPath
        context.coordinator.showFileHeaders = showFileHeaders
        context.coordinator.onAddComment = onAddComment

        let commentedLinesChanged = context.coordinator.commentedLines != commentedLines
        context.coordinator.commentedLines = commentedLines

        if let lines = preloadedLines {
            context.coordinator.loadLines(lines, fontSize: fontSize, fontFamily: fontFamily)
        } else if let output = diffOutput {
            context.coordinator.parseAndReload(diffOutput: output, fontSize: fontSize, fontFamily: fontFamily)
        }

        // Refresh cells if commented lines changed
        if commentedLinesChanged {
            context.coordinator.tableView?.reloadData()
        }

        // Handle scroll to file request
        if let file = scrollToFile, file != context.coordinator.lastScrolledFile {
            context.coordinator.scrollToFile(file)
            context.coordinator.lastScrolledFile = file
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            repoPath: repoPath,
            showFileHeaders: showFileHeaders,
            onOpenFile: onOpenFile,
            commentedLines: commentedLines,
            onAddComment: onAddComment
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        weak var tableView: NSTableView?
        var rows: [DiffRow] = []
        var rowHeight: CGFloat = 20
        var fontSize: Double = 12
        var fontFamily: String = "Menlo"
        var repoPath: String = ""
        var showFileHeaders: Bool = true
        var onFileVisible: ((String) -> Void)?
        var onOpenFile: ((String) -> Void)?
        var lastScrolledFile: String?
        var commentedLines: Set<String> = []
        var onAddComment: ((DiffLine, String) -> Void)?

        private var lastDataHash: Int = 0
        private var fileRowIndices: [String: Int] = [:]
        private var rowToFilePath: [Int: String] = [:]
        private var lastVisibleFile: String?
        private var scrollObserver: NSObjectProtocol?
        private var rawLines: [String] = []
        private var parsedRows: [Int: DiffRow] = [:]
        private var lineParser: DiffLineParser?

        enum DiffRow {
            case fileHeader(path: String)
            case line(DiffLine)
            case lazyLine(rawIndex: Int)
        }

        init(
            repoPath: String,
            showFileHeaders: Bool,
            onOpenFile: ((String) -> Void)?,
            commentedLines: Set<String>,
            onAddComment: ((DiffLine, String) -> Void)?
        ) {
            self.repoPath = repoPath
            self.showFileHeaders = showFileHeaders
            self.onOpenFile = onOpenFile
            self.commentedLines = commentedLines
            self.onAddComment = onAddComment
            super.init()
        }

        deinit {
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func setupScrollObserver(for scrollView: NSScrollView) {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.updateVisibleFile()
            }
            scrollView.contentView.postsBoundsChangedNotifications = true
        }

        private func updateVisibleFile() {
            guard let tableView = tableView else { return }
            let visibleRect = tableView.visibleRect

            // Constants for visibility thresholds
            let headerAboveThreshold: CGFloat = 20
            let headerNearTopThreshold: CGFloat = 50

            var currentFile: String?
            var lastFileBeforeVisible: String?

            for (index, row) in rows.enumerated() {
                if case .fileHeader(let path) = row {
                    let rowRect = tableView.rect(ofRow: index)

                    if rowRect.maxY <= visibleRect.minY + headerAboveThreshold {
                        lastFileBeforeVisible = path
                    } else if rowRect.minY < visibleRect.maxY {
                        if rowRect.minY <= visibleRect.minY + headerNearTopThreshold {
                            currentFile = path
                        } else if currentFile == nil {
                            currentFile = path
                        }
                    }
                }
            }

            if currentFile == nil {
                currentFile = lastFileBeforeVisible
            }

            if let file = currentFile, file != lastVisibleFile {
                lastVisibleFile = file
                onFileVisible?(file)
            }
        }

        func scrollToFile(_ file: String) {
            guard let tableView = tableView,
                  let rowIndex = fileRowIndices[file] else { return }

            tableView.scrollRowToVisible(rowIndex)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let rowRect = tableView.rect(ofRow: rowIndex)
                tableView.enclosingScrollView?.contentView.scroll(to: NSPoint(x: 0, y: rowRect.minY))
            }
        }

        // Load pre-parsed DiffLine array
        func loadLines(_ lines: [DiffLine], fontSize: Double, fontFamily: String) {
            let newHash = lines.hashValue ^ fontSize.hashValue ^ fontFamily.hashValue
            guard newHash != lastDataHash else { return }

            lastDataHash = newHash
            self.fontSize = fontSize
            self.fontFamily = fontFamily

            let font = NSFont(name: fontFamily, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            rowHeight = ceil(font.ascender - font.descender + font.leading) + 6

            rows = lines.map { .line($0) }
            tableView?.reloadData()
        }

        // Parse raw diff output - store raw lines for lazy parsing
        func parseAndReload(diffOutput: String, fontSize: Double, fontFamily: String) {
            let newHash = diffOutput.hashValue ^ fontSize.hashValue ^ fontFamily.hashValue
            guard newHash != lastDataHash else { return }

            lastDataHash = newHash
            self.fontSize = fontSize
            self.fontFamily = fontFamily

            let font = NSFont(name: fontFamily, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            rowHeight = ceil(font.ascender - font.descender + font.leading) + 6

            // Store raw lines for lazy parsing
            rawLines = []
            rawLines.reserveCapacity(diffOutput.count / 40)
            diffOutput.enumerateLines { [self] line, _ in
                rawLines.append(line)
            }

            // Initialize parser
            lineParser = DiffLineParser(rawLines: rawLines)

            // Clear parsed cache
            parsedRows.removeAll(keepingCapacity: true)
            fileRowIndices.removeAll()
            rows.removeAll(keepingCapacity: true)

            // Build row metadata quickly (just count and identify file headers)
            buildRowMetadata()

            tableView?.reloadData()
        }

        private func buildRowMetadata() {
            var rowIndex = 0
            var currentFilePath: String?
            rowToFilePath.removeAll()

            for (lineIndex, line) in rawLines.enumerated() {
                let firstChar = line.first

                if line.hasPrefix("diff --git ") {
                    continue
                } else if line.hasPrefix("+++ b/") {
                    let path = String(line.dropFirst(6))
                    currentFilePath = path
                    if showFileHeaders {
                        fileRowIndices[path] = rowIndex
                        rows.append(.fileHeader(path: path))
                        rowIndex += 1
                    }
                } else if firstChar == "-" && line.hasPrefix("--- ") {
                    continue
                } else if line.hasPrefix("index ") || line.hasPrefix("new file") || line.hasPrefix("deleted file") {
                    continue
                } else if firstChar == "@" || firstChar == "+" || firstChar == "-" || firstChar == " " {
                    rows.append(.lazyLine(rawIndex: lineIndex))
                    if let path = currentFilePath {
                        rowToFilePath[rowIndex] = path
                    }
                    rowIndex += 1
                }
            }
        }

        func getRow(at index: Int) -> DiffRow {
            guard index < rows.count else {
                return .line(DiffLine(lineNumber: 0, oldLineNumber: nil, newLineNumber: nil, content: "", type: .context))
            }

            switch rows[index] {
            case .lazyLine(let rawIndex):
                if let cached = parsedRows[index] {
                    return cached
                }
                let parsed = DiffRow.line(lineParser?.parseLine(at: rawIndex) ?? DiffLine(lineNumber: rawIndex, oldLineNumber: nil, newLineNumber: nil, content: "", type: .context))
                parsedRows[index] = parsed
                return parsed
            default:
                return rows[index]
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < rows.count else { return nil }

            let resolvedRow = getRow(at: row)
            switch resolvedRow {
            case .fileHeader(let path):
                return makeFileHeaderCell(path: path, tableView: tableView)
            case .line(let diffLine):
                return makeLineCell(diffLine: diffLine, row: row, tableView: tableView)
            case .lazyLine:
                return nil
            }
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard row < rows.count else { return nil }
            let rowView = DiffNSRowView()

            let resolvedRow = getRow(at: row)
            switch resolvedRow {
            case .fileHeader:
                rowView.lineType = nil
            case .line(let diffLine):
                rowView.lineType = diffLine.type
            case .lazyLine:
                rowView.lineType = .context
            }

            return rowView
        }

        private func makeFileHeaderCell(path: String, tableView: NSTableView) -> NSView {
            let id = NSUserInterfaceItemIdentifier("FileHeader")
            if let cell = tableView.makeView(withIdentifier: id, owner: nil) as? FileHeaderCellView {
                cell.configure(path: path, repoPath: repoPath, fontSize: fontSize, fontFamily: fontFamily, onOpenFile: onOpenFile)
                return cell
            }
            let cell = FileHeaderCellView(identifier: id)
            cell.configure(path: path, repoPath: repoPath, fontSize: fontSize, fontFamily: fontFamily, onOpenFile: onOpenFile)
            return cell
        }

        private func makeLineCell(diffLine: DiffLine, row: Int, tableView: NSTableView) -> NSView {
            let id = NSUserInterfaceItemIdentifier("DiffLine")
            let filePath = rowToFilePath[row] ?? ""
            let commentKey = "\(filePath):\(diffLine.lineNumber)"
            let hasComment = commentedLines.contains(commentKey)

            let cell: LineCellView
            if let existingCell = tableView.makeView(withIdentifier: id, owner: nil) as? LineCellView {
                cell = existingCell
            } else {
                cell = LineCellView(identifier: id)
            }

            cell.configure(
                diffLine: diffLine,
                fontSize: fontSize,
                fontFamily: fontFamily,
                hasComment: hasComment,
                onCommentTap: { [weak self] in
                    self?.onAddComment?(diffLine, filePath)
                }
            )
            return cell
        }
    }
}
