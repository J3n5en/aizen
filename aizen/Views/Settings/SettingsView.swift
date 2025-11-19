//
//  SettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "general"
    case terminal = "terminal"
    case editor = "editor"
    case appearance = "appearance"
    case agents = "agents"
    case advanced = "advanced"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return String(localized: "settings.general.title")
        case .terminal: return String(localized: "settings.terminal.title")
        case .editor: return String(localized: "settings.editor.title")
        case .appearance: return "Appearance"
        case .agents: return String(localized: "settings.agents.title")
        case .advanced: return String(localized: "settings.advanced.title")
        }
    }
    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .terminal: return "terminal"
        case .editor: return "doc.text"
        case .appearance: return "paintpalette"
        case .agents: return "brain"
        case .advanced: return "gearshape.2"
        }
    }
}

struct SettingsView: View {
    @AppStorage("defaultEditor") private var defaultEditor = "code"
    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"
    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0

    var body: some View {
        TabView {
            GeneralSettingsView(defaultEditor: $defaultEditor)
                .tabItem {
                    Label(SettingsSection.general.title, systemImage: SettingsSection.general.systemImage)
                }
                .tag(SettingsSection.general)

            TerminalSettingsView(
                fontName: $terminalFontName,
                fontSize: $terminalFontSize
            )
            .tabItem {
                Label(SettingsSection.terminal.title, systemImage: SettingsSection.terminal.systemImage)
            }
            .tag(SettingsSection.terminal)

            EditorSettingsView()
                .tabItem {
                    Label(SettingsSection.editor.title, systemImage: SettingsSection.editor.systemImage)
                }
                .tag(SettingsSection.editor)

            AppearanceSettingsView()
                .tabItem {
                    Label(SettingsSection.appearance.title, systemImage: SettingsSection.appearance.systemImage)
                }
                .tag(SettingsSection.appearance)

            AgentsSettingsView(defaultACPAgent: $defaultACPAgent)
                .tabItem {
                    Label(SettingsSection.agents.title, systemImage: SettingsSection.agents.systemImage)
                }
                .tag(SettingsSection.agents)

            AdvancedSettingsView()
                .tabItem {
                    Label(SettingsSection.advanced.title, systemImage: SettingsSection.advanced.systemImage)
                }
                .tag(SettingsSection.advanced)
        }
        .frame(width: 600, height: 500)
    }
}
