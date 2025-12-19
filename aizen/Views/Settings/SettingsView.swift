//
//  SettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

private extension View {
    @ViewBuilder
    func removingSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

// MARK: - Settings Selection

enum SettingsSelection: Hashable {
    case general
    case git
    case terminal
    case editor
    case agent(String) // agent id
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("defaultEditor") private var defaultEditor = "code"
    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"
    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0

    @State private var selection: SettingsSelection? = .general
    @State private var agents: [AgentMetadata] = []
    @State private var showingAddCustomAgent = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                // Static settings items
                Label("General", systemImage: "gear")
                    .tag(SettingsSelection.general)

                Label("Git", systemImage: "arrow.triangle.branch")
                    .tag(SettingsSelection.git)

                Label("Terminal", systemImage: "terminal")
                    .tag(SettingsSelection.terminal)

                Label("Editor", systemImage: "doc.text")
                    .tag(SettingsSelection.editor)

                // Agents section
                Section("Agents") {
                    ForEach(agents, id: \.id) { agent in
                        HStack(spacing: 8) {
                            AgentIconView(metadata: agent, size: 20)
                            Text(agent.name)
                            Spacer()
                            if agent.id == defaultACPAgent {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .tag(SettingsSelection.agent(agent.id))
                        .contextMenu {
                            if agent.id != defaultACPAgent {
                                Button("Make Default") {
                                    defaultACPAgent = agent.id
                                }
                            }
                        }
                    }

                    Button {
                        showingAddCustomAgent = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                            Text("Add Custom Agent")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220)
            .navigationSplitViewColumnWidth(220)
            .removingSidebarToggle()
        } detail: {
            Group {
                switch selection {
                case .general:
                    GeneralSettingsView(defaultEditor: $defaultEditor)
                        .navigationTitle("General")
                        .navigationSubtitle("Default apps, layout, and toolbar")
                case .git:
                    GitSettingsView()
                        .navigationTitle("Git")
                        .navigationSubtitle("Branch templates and preferences")
                case .terminal:
                    TerminalSettingsView(
                        fontName: $terminalFontName,
                        fontSize: $terminalFontSize
                    )
                    .navigationTitle("Terminal")
                    .navigationSubtitle("Font, theme, and session settings")
                case .editor:
                    EditorSettingsView()
                        .navigationTitle("Editor")
                        .navigationSubtitle("Theme, font, and display options")
                case .agent(let agentId):
                    if let index = agents.firstIndex(where: { $0.id == agentId }) {
                        AgentDetailView(
                            metadata: $agents[index],
                            isDefault: agentId == defaultACPAgent,
                            onSetDefault: { defaultACPAgent = agentId }
                        )
                        .navigationTitle(agents[index].name)
                        .navigationSubtitle("Agent Configuration")
                    }
                case .none:
                    GeneralSettingsView(defaultEditor: $defaultEditor)
                        .navigationTitle("General")
                        .navigationSubtitle("Default apps, layout, and toolbar")
                }
            }
            .toolbarBackground(.visible, for: .windowToolbar)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 800, height: 550)
        .onAppear {
            loadAgents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentMetadataDidChange)) { _ in
            loadAgents()
        }
        .sheet(isPresented: $showingAddCustomAgent) {
            CustomAgentFormView(
                onSave: { _ in
                    loadAgents()
                },
                onCancel: {}
            )
        }
    }

    private func loadAgents() {
        Task {
            agents = await AgentRegistry.shared.getAllAgents()
        }
    }
}
