//
//  SettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultEditor") private var defaultEditor = "code"
    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"
    @AppStorage("acpAgentPath_claude") private var claudePath = ""
    @AppStorage("acpAgentPath_codex") private var codexPath = ""
    @AppStorage("acpAgentPath_gemini") private var geminiPath = ""
    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalBackgroundColor") private var terminalBackgroundColor = "#1e1e2e"
    @AppStorage("terminalForegroundColor") private var terminalForegroundColor = "#cdd6f4"
    @AppStorage("terminalCursorColor") private var terminalCursorColor = "#f5e0dc"
    @AppStorage("terminalSelectionBackground") private var terminalSelectionBackground = "#585b70"
    @AppStorage("terminalPalette") private var terminalPalette = "#45475a,#f38ba8,#a6e3a1,#f9e2af,#89b4fa,#f5c2e7,#94e2d5,#a6adc8,#585b70,#f37799,#89d88b,#ebd391,#74a8fc,#f2aede,#6bd7ca,#bac2de"

    @State private var testingAgent: String? = nil
    @State private var testResult: String? = nil

    var body: some View {
        TabView {
            GeneralSettingsView(defaultEditor: $defaultEditor)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("general")

            TerminalSettingsView(
                fontName: $terminalFontName,
                fontSize: $terminalFontSize,
                backgroundColor: $terminalBackgroundColor,
                foregroundColor: $terminalForegroundColor,
                cursorColor: $terminalCursorColor,
                selectionBackground: $terminalSelectionBackground,
                palette: $terminalPalette
            )
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }
            .tag("terminal")

            AgentsSettingsView(
                defaultACPAgent: $defaultACPAgent,
                claudePath: $claudePath,
                codexPath: $codexPath,
                geminiPath: $geminiPath,
                testingAgent: $testingAgent,
                testResult: $testResult
            )
            .tabItem {
                Label("Agents", systemImage: "brain")
            }
            .tag("agents")

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .tag("advanced")
        }
        .frame(width: 600, height: 600)
    }
}
