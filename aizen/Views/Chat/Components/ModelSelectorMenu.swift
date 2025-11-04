//
//  ModelSelectorMenu.swift
//  aizen
//
//  Model selection menu component
//

import SwiftUI

struct ModelSelectorMenu: View {
    @ObservedObject var session: AgentSession
    let selectedAgent: String

    var body: some View {
        Menu {
            ForEach(session.availableModels, id: \.modelId) { modelInfo in
                Button {
                    Task {
                        try? await session.setModel(modelInfo.modelId)
                    }
                } label: {
                    HStack {
                        Text(modelInfo.name)
                        Spacer()
                        if modelInfo.modelId == session.currentModelId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                AgentIconView(agent: selectedAgent, size: 12)
                if let currentModel = session.availableModels.first(where: { $0.modelId == session.currentModelId }) {
                    Text(currentModel.name)
                        .font(.system(size: 11, weight: .medium))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help(String(localized: "chat.model.select"))
    }
}
