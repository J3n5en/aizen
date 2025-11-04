//
//  AgentMetadata.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Metadata for an agent configuration
struct AgentMetadata: Codable, Identifiable {
    let id: String
    var name: String
    var description: String?
    var iconType: AgentIconType
    var isBuiltIn: Bool
    var isEnabled: Bool
    var executablePath: String?
    var launchArgs: [String]
    var installMethod: AgentInstallMethod?

    init(
        id: String,
        name: String,
        description: String? = nil,
        iconType: AgentIconType,
        isBuiltIn: Bool,
        isEnabled: Bool = true,
        executablePath: String? = nil,
        launchArgs: [String] = [],
        installMethod: AgentInstallMethod? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconType = iconType
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.executablePath = executablePath
        self.launchArgs = launchArgs
        self.installMethod = installMethod
    }
}
