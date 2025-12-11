//
//  MarkdownListView.swift
//  aizen
//
//  Markdown list rendering component
//

import SwiftUI

// MARK: - List Item Wrapper for Stable IDs

struct ListItemWrapper: Identifiable {
    let id: String
    let index: Int
    let text: AttributedString

    init(index: Int, text: AttributedString) {
        self.index = index
        self.text = text
        // Convert AttributedString characters to String for hashing
        let textPrefix = String(text.characters.prefix(50))
        self.id = "li-\(index)-\(textPrefix.hashValue)"
    }
}

// MARK: - Markdown List View

struct MarkdownListView: View {
    let items: [AttributedString]
    let isOrdered: Bool

    private var wrappedItems: [ListItemWrapper] {
        items.enumerated().map { ListItemWrapper(index: $0.offset, text: $0.element) }
    }

    var body: some View {
        ForEach(wrappedItems) { item in
            HStack(alignment: .top, spacing: 8) {
                Text(isOrdered ? "\(item.index + 1)." : "•")
                    .foregroundStyle(.secondary)
                Text(item.text)
                    .textSelection(.enabled)
            }
        }
    }
}
