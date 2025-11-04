//
//  CommandAutocompleteView.swift
//  aizen
//
//  Command autocomplete suggestions
//

import SwiftUI

struct CommandAutocompleteView: View {
    let suggestions: [AvailableCommand]
    let onSelect: (AvailableCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions.prefix(5), id: \.name) { command in
                Button {
                    onSelect(command)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("/\(command.name)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)

                        Text(command.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.clear)

                if command.name != suggestions.prefix(5).last?.name {
                    Divider()
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .padding(.horizontal, 12)
    }
}
