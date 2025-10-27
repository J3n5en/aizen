//
//  GeneralSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct GeneralSettingsView: View {
    @Binding var defaultEditor: String

    var body: some View {
        Form {
            Section("Editor") {
                TextField("Default Editor Command", text: $defaultEditor)
                    .help("Command to launch your preferred code editor (e.g., 'code', 'cursor', 'subl')")

                Text("Common editors: code (VS Code), cursor (Cursor), subl (Sublime), atom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
