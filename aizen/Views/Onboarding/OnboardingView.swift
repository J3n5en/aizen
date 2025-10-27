//
//  OnboardingView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 27.10.25.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header section with app icon and title
            VStack(spacing: 16) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(16)

                Text("Welcome to Aizen")
                    .font(.system(size: 32, weight: .bold))

                Text("Your developer tool for Git worktrees with integrated terminal and AI agents")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 500)
            }
            .padding(.top, 48)
            .padding(.bottom, 32)

            // Features grid
            VStack(spacing: 24) {
                FeatureRow(
                    icon: "arrow.triangle.branch",
                    iconColor: .blue,
                    title: "Git Worktree Management",
                    description: "Manage multiple worktrees per repository. Switch between branches without losing work or stashing changes."
                )

                FeatureRow(
                    icon: "terminal",
                    iconColor: .green,
                    title: "Integrated Terminal",
                    description: "Built-in terminal with split pane support. Execute commands directly within your worktree context."
                )

                FeatureRow(
                    icon: "brain",
                    iconColor: .purple,
                    title: "Agents",
                    description: "Connect with Claude, Codex, or Gemini through the Agent Client Protocol for intelligent assistance."
                )

                FeatureRow(
                    icon: "play.circle",
                    iconColor: .orange,
                    title: "Quick Setup",
                    description: "Add your first repository from the sidebar, configure agents in Settings, and start managing worktrees."
                )
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 32)

            Spacer()

            // Get Started button
            Button {
                dismiss()
            } label: {
                Text("Get Started")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 48)
            .padding(.bottom, 32)
        }
        .frame(width: 600, height: 650)
    }
}

struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .foregroundStyle(iconColor.gradient)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

#Preview {
    OnboardingView()
}
