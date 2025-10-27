//
//  MarkdownContentView.swift
//  aizen
//
//  Markdown rendering components
//

import SwiftUI
import Markdown

// MARK: - Message Content View

struct MessageContentView: View {
    let content: String
    var isComplete: Bool = true

    var body: some View {
        MarkdownRenderedView(content: content, isStreaming: !isComplete)
    }
}

// MARK: - Markdown Rendered View

struct MarkdownRenderedView: View {
    let content: String
    var isStreaming: Bool = false

    private var renderedBlocks: [MarkdownBlock] {
        let document = Document(parsing: content)
        return convertMarkdown(document)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(renderedBlocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .paragraph(let attributedText):
                    Text(attributedText)
                        .textSelection(.enabled)
                        .opacity(isStreaming && index == renderedBlocks.count - 1 ? 0.9 : 1.0)
                case .heading(let attributedText, let level):
                    Text(attributedText)
                        .font(fontForHeading(level: level))
                        .fontWeight(.bold)
                        .textSelection(.enabled)
                case .codeBlock(let code, let language):
                    CodeBlockView(code: code, language: language)
                case .list(let items, let isOrdered):
                    ForEach(Array(items.enumerated()), id: \.offset) { itemIndex, item in
                        HStack(alignment: .top, spacing: 8) {
                            Text(isOrdered ? "\(itemIndex + 1)." : "•")
                                .foregroundStyle(.secondary)
                            Text(item)
                                .textSelection(.enabled)
                        }
                    }
                case .blockQuote(let attributedText):
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 3)
                        Text(attributedText)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func convertMarkdown(_ document: Document) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []

        for child in document.children {
            if let paragraph = child as? Paragraph {
                let attributedText = renderInlineContent(paragraph.children)
                blocks.append(.paragraph(attributedText))
            } else if let heading = child as? Heading {
                let attributedText = renderInlineContent(heading.children)
                blocks.append(.heading(attributedText, level: heading.level))
            } else if let codeBlock = child as? CodeBlock {
                blocks.append(.codeBlock(codeBlock.code, language: codeBlock.language))
            } else if let list = child as? UnorderedList {
                let items = Array(list.listItems.map { renderInlineContent($0.children) })
                blocks.append(.list(items, isOrdered: false))
            } else if let list = child as? OrderedList {
                let items = Array(list.listItems.map { renderInlineContent($0.children) })
                blocks.append(.list(items, isOrdered: true))
            } else if let blockQuote = child as? BlockQuote {
                let text = renderBlockQuoteContent(blockQuote.children)
                blocks.append(.blockQuote(text))
            }
        }

        return blocks
    }

    private func renderInlineContent(_ inlineElements: some Sequence<Markup>) -> AttributedString {
        var result = AttributedString()

        for element in inlineElements {
            if let text = element as? Markdown.Text {
                result += AttributedString(text.string)
            } else if let strong = element as? Strong {
                var boldText = renderInlineContent(strong.children)
                boldText.font = .body.bold()
                result += boldText
            } else if let emphasis = element as? Emphasis {
                var italicText = renderInlineContent(emphasis.children)
                italicText.font = .body.italic()
                result += italicText
            } else if let code = element as? InlineCode {
                var codeText = AttributedString(code.code)
                codeText.font = .system(.body, design: .monospaced)
                codeText.backgroundColor = Color(nsColor: .textBackgroundColor)
                result += codeText
            } else if let link = element as? Markdown.Link {
                var linkText = renderInlineContent(link.children)
                if let url = URL(string: link.destination ?? "") {
                    linkText.link = url
                }
                linkText.foregroundColor = Color.blue
                linkText.underlineStyle = .single
                result += linkText
            } else if let strikethrough = element as? Strikethrough {
                var strikethroughText = renderInlineContent(strikethrough.children)
                strikethroughText.strikethroughStyle = .single
                result += strikethroughText
            } else if let paragraph = element as? Paragraph {
                result += renderInlineContent(paragraph.children)
            }
        }

        return result
    }

    private func renderBlockQuoteContent(_ children: some Sequence<Markup>) -> AttributedString {
        var result = AttributedString()

        for child in children {
            if let paragraph = child as? Paragraph {
                result += renderInlineContent(paragraph.children)
            }
        }

        return result
    }

    private func fontForHeading(level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        case 4: return .title3
        case 5: return .headline
        default: return .body
        }
    }
}

// MARK: - Markdown Block Type

enum MarkdownBlock {
    case paragraph(AttributedString)
    case heading(AttributedString, level: Int)
    case codeBlock(String, language: String?)
    case list([AttributedString], isOrdered: Bool)
    case blockQuote(AttributedString)
}
