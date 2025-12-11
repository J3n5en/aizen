//
//  MermaidDiagramView.swift
//  aizen
//
//  Mermaid diagram rendering using WKWebView
//

import SwiftUI
import WebKit

// MARK: - Mermaid Diagram View

struct MermaidDiagramView: NSViewRepresentable {
    let code: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <script type="module">
                    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
                    mermaid.initialize({
                        startOnLoad: true,
                        theme: 'dark',
                        themeVariables: {
                            darkMode: true,
                            background: 'transparent',
                            mainBkg: 'transparent',
                            primaryColor: '#89b4fa',
                            primaryTextColor: '#cdd6f4',
                            primaryBorderColor: '#89b4fa',
                            lineColor: '#6c7086',
                            secondaryColor: '#f5c2e7',
                            tertiaryColor: '#94e2d5',
                            fontSize: '14px',
                            nodeBorder: '#6c7086',
                            clusterBkg: 'transparent',
                            clusterBorder: '#6c7086',
                            defaultLinkColor: '#6c7086',
                            titleColor: '#cdd6f4',
                            edgeLabelBackground: 'transparent',
                            nodeTextColor: '#cdd6f4'
                        }
                    });
                </script>
                <style>
                    body {
                        background-color: transparent;
                        color: #cdd6f4;
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                        margin: 16px;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                    }
                    .mermaid {
                        background-color: transparent;
                    }
                </style>
            </head>
            <body>
                <pre class="mermaid">
            \(code)
                </pre>
            </body>
            </html>
            """

        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Adjust height after content loads
            webView.evaluateJavaScript("document.body.scrollHeight") { height, error in
                if let height = height as? CGFloat {
                    DispatchQueue.main.async {
                        webView.frame.size.height = height + 32 // Add padding
                    }
                }
            }
        }
    }
}
