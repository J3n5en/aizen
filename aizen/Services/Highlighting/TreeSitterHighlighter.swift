//
//  TreeSitterHighlighter.swift
//  aizen
//
//  Tree-sitter based syntax highlighting service
//

import Foundation
import SwiftUI
import SwiftTreeSitter
import CodeEditLanguages
import CodeEditSourceEditor

actor TreeSitterHighlighter {
    private var parsers: [CodeLanguage: Parser] = [:]

    /// Highlight code using tree-sitter and return attributed string
    func highlightCode(
        _ text: String,
        language: CodeLanguage,
        theme: EditorTheme
    ) async throws -> AttributedString {
        // Get language for tree-sitter
        guard let tsLanguage = language.language else {
            // Language not supported, return plain text
            return AttributedString(text)
        }

        // Get or create parser for language
        let parser = try await getParser(for: language, tsLanguage: tsLanguage)

        // Parse the code
        guard let tree = parser.parse(text) else {
            // If parsing fails, return plain text
            return AttributedString(text)
        }

        // Get highlights query URL
        guard let queryURL = language.queryURL else {
            // No highlights query available, return plain text
            return AttributedString(text)
        }

        // Load query from file
        guard let queryData = try? Data(contentsOf: queryURL) else {
            return AttributedString(text)
        }

        // Create query
        let query = try Query(language: tsLanguage, data: queryData)

        // Execute query
        let queryCursor = query.execute(node: tree.rootNode!, in: tree)

        // Build attributed string with highlights
        var attributedString = AttributedString(text)

        // Apply colors based on capture names
        for match in queryCursor {
            for capture in match.captures {
                guard let captureName = query.captureName(for: Int(capture.index)) else {
                    continue
                }

                if let color = HighlightThemeMapper.color(
                    for: captureName,
                    theme: theme
                ) {
                    // Convert byte range to string indices
                    let utf8View = text.utf8
                    let startIndex = utf8View.index(utf8View.startIndex, offsetBy: Int(capture.node.byteRange.lowerBound))
                    let endIndex = utf8View.index(utf8View.startIndex, offsetBy: Int(capture.node.byteRange.upperBound))

                    // Convert to String.Index
                    let stringStart = String.Index(startIndex, within: text)!
                    let stringEnd = String.Index(endIndex, within: text)!

                    // Apply color to attributed string
                    if let attrStart = AttributedString.Index(stringStart, within: attributedString),
                       let attrEnd = AttributedString.Index(stringEnd, within: attributedString) {
                        attributedString[attrStart..<attrEnd].foregroundColor = Color(nsColor: color)
                    }
                }
            }
        }

        return attributedString
    }

    /// Get or create parser for a language
    private func getParser(for language: CodeLanguage, tsLanguage: Language) async throws -> Parser {
        if let existingParser = parsers[language] {
            return existingParser
        }

        let parser = Parser()
        try parser.setLanguage(tsLanguage)
        parsers[language] = parser
        return parser
    }
}

enum HighlightError: Error {
    case unsupportedLanguage(CodeLanguage)
    case parsingFailed
}

/// Maps tree-sitter capture names to theme colors
struct HighlightThemeMapper {
    /// Map a tree-sitter capture name to a color from the theme
    static func color(for captureName: String, theme: EditorTheme) -> NSColor? {
        // Tree-sitter capture names follow patterns like:
        // @keyword, @string, @comment, @function, @type, @variable, etc.

        let name = captureName.lowercased()

        // Keywords
        if name.contains("keyword") {
            return theme.keywords.color
        }

        // Strings
        if name.contains("string") || name.contains("character") {
            return theme.strings.color
        }

        // Comments
        if name.contains("comment") {
            return theme.comments.color
        }

        // Types
        if name.contains("type") || name.contains("class") || name.contains("interface") {
            return theme.types.color
        }

        // Functions
        if name.contains("function") || name.contains("method") {
            return theme.commands.color
        }

        // Variables and properties
        if name.contains("variable") || name.contains("property") || name.contains("parameter") {
            return theme.variables.color
        }

        // Numbers
        if name.contains("number") || name.contains("float") || name.contains("integer") {
            return theme.numbers.color
        }

        // Operators
        if name.contains("operator") {
            return theme.attributes.color
        }

        // Constants and values
        if name.contains("constant") || name.contains("boolean") {
            return theme.values.color
        }

        // Attributes and decorators
        if name.contains("attribute") || name.contains("decorator") || name.contains("annotation") {
            return theme.attributes.color
        }

        // Punctuation (use default text color)
        if name.contains("punctuation") || name.contains("delimiter") || name.contains("bracket") {
            return theme.text.color
        }

        // Default: return nil to use default text color
        return nil
    }
}
