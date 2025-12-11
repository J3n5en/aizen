//
//  MarkdownTableView.swift
//  aizen
//
//  Markdown table rendering component
//

import SwiftUI
import Markdown

// MARK: - Table Cell Wrapper

struct TableCellWrapper: Identifiable {
    let id: String
    let colIndex: Int
    let text: AttributedString

    init(colIndex: Int, text: AttributedString, rowIndex: Int = -1) {
        self.colIndex = colIndex
        self.text = text
        let textPrefix = String(text.characters.prefix(20))
        self.id = "cell-\(rowIndex)-\(colIndex)-\(textPrefix.hashValue)"
    }
}

// MARK: - Table Row Wrapper

struct TableRowWrapper: Identifiable {
    let id: String
    let rowIndex: Int
    let cells: [TableCellWrapper]

    init(rowIndex: Int, cells: [AttributedString]) {
        self.rowIndex = rowIndex
        self.cells = cells.enumerated().map { TableCellWrapper(colIndex: $0.offset, text: $0.element, rowIndex: rowIndex) }
        self.id = "row-\(rowIndex)-\(cells.count)"
    }
}

// MARK: - Markdown Table View

struct MarkdownTableView: View {
    let header: [AttributedString]
    let rows: [[AttributedString]]
    let alignments: [Markdown.Table.ColumnAlignment?]

    private var wrappedHeader: [TableCellWrapper] {
        header.enumerated().map { TableCellWrapper(colIndex: $0.offset, text: $0.element, rowIndex: -1) }
    }

    private var wrappedRows: [TableRowWrapper] {
        rows.enumerated().map { TableRowWrapper(rowIndex: $0.offset, cells: $0.element) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(wrappedHeader) { cell in
                        Text(cell.text)
                            .fontWeight(.semibold)
                            .frame(minWidth: 80, alignment: alignment(for: cell.colIndex))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))

                Divider()

                // Body rows
                ForEach(wrappedRows) { row in
                    HStack(spacing: 0) {
                        ForEach(row.cells) { cell in
                            Text(cell.text)
                                .frame(minWidth: 80, alignment: alignment(for: cell.colIndex))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(row.rowIndex % 2 == 1 ? Color(nsColor: .textBackgroundColor).opacity(0.2) : Color.clear)
                }
            }
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.1))
        .cornerRadius(6)
    }

    private func alignment(for column: Int) -> Alignment {
        guard column < alignments.count, let align = alignments[column] else {
            return .leading
        }
        switch align {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}
