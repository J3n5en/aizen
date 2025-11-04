//
//  AgentPlanSidebarView.swift
//  aizen
//
//  Sidebar displaying agent plan progress
//

import SwiftUI

struct AgentPlanSidebarView: View {
    let plan: Plan
    @Binding var isShowing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("chat.plan.sidebar.title", bundle: .main)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button { isShowing = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(plan.entries.enumerated()), id: \.offset) { index, entry in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(statusColor(for: entry.status))
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)

                            VStack(alignment: .leading, spacing: 4) {
                                PlanContentView(content: entry.content)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)

                                if let activeForm = entry.activeForm, entry.status == .inProgress {
                                    PlanContentView(content: activeForm)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .italic()
                                }

                                Text(statusLabel(for: entry.status))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(statusColor(for: entry.status))
                                    .textCase(.uppercase)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(entry.status == .inProgress ? Color.blue.opacity(0.05) : Color.clear)
                        )

                        if index < plan.entries.count - 1 {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.separator)
                .frame(width: 1)
        }
    }

    private func statusColor(for status: PlanEntryStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .cancelled:
            return .red
        }
    }

    private func statusLabel(for status: PlanEntryStatus) -> String {
        switch status {
        case .pending:
            return String(localized: "chat.status.pending")
        case .inProgress:
            return String(localized: "chat.status.inProgress")
        case .completed:
            return String(localized: "chat.status.completed")
        case .cancelled:
            return String(localized: "chat.status.cancelled")
        }
    }
}
