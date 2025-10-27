//
//  CodeBlockView.swift
//  aizen
//
//  Code block rendering with syntax highlighting
//

import SwiftUI
import HighlightSwift

struct CodeBlockView: View {
    let code: String
    let language: String?

    @State private var showCopyConfirmation = false

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
                .help("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                if let lang = language,
                   !lang.isEmpty,
                   !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let highlightLang = LanguageDetection.highlightLanguageFromFence(lang) {
                    CodeText(code)
                        .highlightLanguage(highlightLang)
                        .codeTextColors(.theme(.github))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 400)
            .background(Color(nsColor: .textBackgroundColor))
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
}
