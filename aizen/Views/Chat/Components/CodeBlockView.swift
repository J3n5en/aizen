//
//  CodeBlockView.swift
//  aizen
//
//  Code block rendering with syntax highlighting
//

import SwiftUI
import CodeEditSourceEditor
import CodeEditLanguages

struct CodeBlockView: View {
    let code: String
    let language: String?

    @State private var showCopyConfirmation = false
    @State private var highlightedText: AttributedString?
    @AppStorage("editorTheme") private var editorTheme: String = "Catppuccin Mocha"

    private let highlighter = TreeSitterHighlighter()

    var body: some View {
      
        
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: copyCode) {
                    Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "chat.code.copy"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            ScrollView(.horizontal, showsIndicators: true) {
                Group  {
                    if let highlighted = highlightedText {
                        Text(highlighted)
                    } else {
                        Text(code)
                            .foregroundColor(.primary)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .padding(8)
            .task(id: code) {
                await performHighlight()
            }
         
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        withAnimation {
            showCopyConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyConfirmation = false
            }
        }
    }

    private func performHighlight() async {
        do {
            let detectedLanguage: CodeLanguage
            if let lang = language, !lang.isEmpty {
                detectedLanguage = LanguageDetection.languageFromFence(lang)
            } else {
                detectedLanguage = .default
            }

            // Load theme
            let theme = GhosttyThemeParser.loadTheme(named: editorTheme) ?? defaultTheme()

            // Highlight using tree-sitter
            let attributed = try await highlighter.highlightCode(
                code,
                language: detectedLanguage,
                theme: theme
            )
            highlightedText = attributed
        } catch {
            // Fallback to plain text on error
            highlightedText = AttributedString(code)
        }
    }

    private func defaultTheme() -> EditorTheme {
        let bg = NSColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
        let fg = NSColor(red: 0.8, green: 0.84, blue: 0.96, alpha: 1.0)

        return EditorTheme(
            text: .init(color: fg),
            insertionPoint: fg,
            invisibles: .init(color: .systemGray),
            background: bg,
            lineHighlight: bg.withAlphaComponent(0.05),
            selection: .selectedTextBackgroundColor,
            keywords: .init(color: .systemPurple),
            commands: .init(color: .systemBlue),
            types: .init(color: .systemYellow),
            attributes: .init(color: .systemRed),
            variables: .init(color: .systemCyan),
            values: .init(color: .systemOrange),
            numbers: .init(color: .systemOrange),
            strings: .init(color: .systemGreen),
            characters: .init(color: .systemGreen),
            comments: .init(color: .systemGray)
        )
    }
}
