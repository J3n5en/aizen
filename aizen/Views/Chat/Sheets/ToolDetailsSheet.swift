//
//  ToolDetailsSheet.swift
//  aizen
//
//  Tool details display dialog
//

import SwiftUI

struct ToolDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let toolCalls: [ToolCall]
    @State private var expandedTools: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("chat.tool.details.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(toolCalls) { toolCall in
                        toolCallDetailView(toolCall)
                    }
                }
                .padding(16)
            }
        }
        .background(.ultraThinMaterial)
        .frame(width: 650, height: 550)
    }

    @ViewBuilder
    private func toolCallDetailView(_ toolCall: ToolCall) -> some View {
        let isExpanded = expandedTools.contains(toolCall.toolCallId)

        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if isExpanded {
                        expandedTools.remove(toolCall.toolCallId)
                    } else {
                        expandedTools.insert(toolCall.toolCallId)
                    }
                }
            }) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(statusColor(for: toolCall.status))
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(toolCall.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)

                        Text(statusLabel(for: toolCall.status))
                            .font(.system(size: 10))
                            .foregroundStyle(statusColor(for: toolCall.status))
                    }

                    Spacer()

                    if !toolCall.content.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            if isExpanded && !toolCall.content.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(toolCall.content.enumerated()), id: \.offset) { _, block in
                        CompactContentBlockView(block: block)
                    }
                }
                .padding(10)
                .padding(.horizontal, 2)
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.2))
        .cornerRadius(6)
    }

    private func statusColor(for status: ToolStatus) -> Color {
        switch status {
        case .pending: return .yellow
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func statusLabel(for status: ToolStatus) -> String {
        switch status {
        case .pending: return String(localized: "chat.status.pending")
        case .inProgress: return String(localized: "chat.tool.status.running")
        case .completed: return String(localized: "chat.tool.status.done")
        case .failed: return String(localized: "chat.tool.status.failed")
        }
    }
}

// MARK: - Compact Content Block View

struct CompactContentBlockView: View {
    let block: ContentBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch block {
            case .text(let content):
                ScrollView([.horizontal, .vertical]) {
                    Text(content.text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)

            case .image(let content):
                Text(String(localized: "chat.content.imageType \(content.mimeType)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

            case .resource(let content):
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "chat.content.resourceUri \(content.resource.uri)"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let text = content.resource.text {
                        ScrollView([.horizontal, .vertical]) {
                            Text(text)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                    }
                }

            case .audio(let content):
                Text(String(localized: "chat.content.audioType \(content.mimeType)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

            case .embeddedResource(let content):
                Text(String(localized: "chat.content.resourceUri \(content.uri)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

            case .diff(let content):
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let path = content.path {
                            Text(String(localized: "chat.content.file \(path)"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 4)
                        }

                        let diffText = "--- \(content.path ?? "original")\n+++ \(content.path ?? "modified")\n\(content.oldText)\n\(content.newText)"
                        ForEach(diffText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(diffLineColor(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)

            case .terminalEmbed(let content):
                ScrollView([.horizontal, .vertical]) {
                    Text(content.output)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color.black.opacity(0.8))
                .cornerRadius(4)
                .foregroundStyle(.white)
            }
        }
    }

    private func diffLineColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return .green
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return .red
        } else if line.hasPrefix("@@") {
            return .blue
        }
        return .primary
    }
}
