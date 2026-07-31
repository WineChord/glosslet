import AppKit
import GlossletCore
import SwiftUI
import WebKit

struct MarkdownTranscriptView: NSViewRepresentable {
    let selection: SelectionSnapshot?
    let messages: [ConversationMessage]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.userContentController.add(
            context.coordinator,
            name: Coordinator.copyCodeHandler
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Coordinator.openLinkHandler
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Coordinator.readyHandler
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = webView
        context.coordinator.loadRenderer(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let payload = RenderPayload(
            selection: selection.map {
                RenderSelection(
                    source: $0.sourceApplicationName,
                    preview: $0.preview
                )
            },
            messages: messages.map {
                RenderMessage(
                    id: $0.id.uuidString,
                    role: $0.role == .user ? "user" : "assistant",
                    text: $0.text,
                    isStreaming: $0.isStreaming,
                    activityText: $0.activityText,
                    startedAtMilliseconds: $0.startedAt.map {
                        Int64(
                            ($0.timeIntervalSince1970 * 1_000).rounded()
                        )
                    }
                )
            },
            labels: RenderLabels(
                thinking: L10n.thinking,
                elapsedSecondsSuffix: L10n.elapsedSecondsSuffix,
                copyCode: L10n.copyCode,
                copied: L10n.copied,
                selectedFrom: L10n.selectedFrom,
                image: L10n.image
            )
        )
        context.coordinator.render(payload)
    }

    static func dismantleNSView(
        _ webView: WKWebView,
        coordinator: Coordinator
    ) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(
            forName: Coordinator.copyCodeHandler
        )
        controller.removeScriptMessageHandler(
            forName: Coordinator.openLinkHandler
        )
        controller.removeScriptMessageHandler(
            forName: Coordinator.readyHandler
        )
        webView.navigationDelegate = nil
        coordinator.webView = nil
    }

    fileprivate struct RenderPayload: Encodable {
        let selection: RenderSelection?
        let messages: [RenderMessage]
        let labels: RenderLabels
    }

    fileprivate struct RenderSelection: Encodable {
        let source: String
        let preview: String
    }

    fileprivate struct RenderMessage: Encodable {
        let id: String
        let role: String
        let text: String
        let isStreaming: Bool
        let activityText: String?
        let startedAtMilliseconds: Int64?
    }

    fileprivate struct RenderLabels: Encodable {
        let thinking: String
        let elapsedSecondsSuffix: String
        let copyCode: String
        let copied: String
        let selectedFrom: String
        let image: String
    }

    final class Coordinator: NSObject, WKNavigationDelegate,
        WKScriptMessageHandler
    {
        static let copyCodeHandler = "copyCode"
        static let openLinkHandler = "openLink"
        static let readyHandler = "rendererReady"

        weak var webView: WKWebView?
        private var isReady = false
        private var pendingScript: String?
        private var lastPayload: Data?

        func loadRenderer(in webView: WKWebView) {
            guard let directory = Self.rendererDirectory,
                FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(
                        "index.html"
                    ).path
                )
            else {
                webView.loadHTMLString(
                    Self.fallbackHTML,
                    baseURL: nil
                )
                return
            }

            webView.loadFileURL(
                directory.appendingPathComponent("index.html"),
                allowingReadAccessTo: directory
            )
        }

        fileprivate func render(_ payload: RenderPayload) {
            guard let data = try? JSONEncoder().encode(payload),
                data != lastPayload,
                let json = String(data: data, encoding: .utf8),
                let literalData = try? JSONEncoder().encode(json),
                let literal = String(
                    data: literalData,
                    encoding: .utf8
                )
            else {
                return
            }
            lastPayload = data
            let script =
                "window.glosslet?.render(JSON.parse(\(literal)));"
            if isReady {
                webView?.evaluateJavaScript(script)
            } else {
                pendingScript = script
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case Self.readyHandler:
                isReady = true
                if let pendingScript {
                    self.pendingScript = nil
                    webView?.evaluateJavaScript(pendingScript)
                }

            case Self.copyCodeHandler:
                guard let text = message.body as? String else {
                    return
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)

            case Self.openLinkHandler:
                guard let string = message.body as? String,
                    let url = URL(string: string),
                    Self.allowedExternalSchemes.contains(
                        url.scheme?.lowercased() ?? ""
                    )
                else {
                    return
                }
                NSWorkspace.shared.open(url)

            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            if Self.allowedExternalSchemes.contains(
                url.scheme?.lowercased() ?? ""
            ) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            isReady = false
            lastPayload = nil
            loadRenderer(in: webView)
        }

        private static let allowedExternalSchemes: Set<String> = [
            "file",
            "http",
            "https",
            "mailto",
        ]

        private static var rendererDirectory: URL? {
            guard let resources = Bundle.module.resourceURL else {
                return nil
            }
            let nested = resources.appendingPathComponent(
                "MarkdownRenderer",
                isDirectory: true
            )
            if FileManager.default.fileExists(atPath: nested.path) {
                return nested
            }
            return resources
        }

        private static let fallbackHTML = """
            <!doctype html>
            <meta charset="utf-8">
            <style>
              :root { color-scheme: light dark; }
              body {
                margin: 24px;
                color: CanvasText;
                background: transparent;
                font: 13px -apple-system, sans-serif;
              }
            </style>
            <p>The local transcript renderer could not be loaded.</p>
            """
    }
}
