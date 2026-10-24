#if MINIK_MATH_WEB
import SwiftUI
import UIKit
import WebKit

/// Android Minik Math's MainActivity WebView: the bundled web app (Resources/MinikMathWeb) with
/// the web app's own storage for progress (Android's DOM storage), sound without a tap, no
/// overscroll and no back-swipe. The page talks to the host only through MinikMathWebBridge.
struct MinikMathWebView: UIViewRepresentable {
    let model: MinikMathWebModel
    /// The app is on screen and no sheet covers the web app (Android's onResume / onPause).
    let active: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = MinikMathWebBridge.userAgentMarkers
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // iPad gets the web app's touch layout, as Android tablets do.
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.userContentController.addUserScript(WKUserScript(
            source: MinikMathWebBridge.script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        // App Store captures only (-MinikScreenshotScene web.<scene>); never added for players.
        if let screenshot = MinikMathWebScreenshot.script {
            config.userContentController.addUserScript(WKUserScript(
                source: screenshot,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        config.userContentController.add(context.coordinator, name: MinikMathWebBridge.handlerName)
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        web.scrollView.alwaysBounceVertical = false
        web.scrollView.alwaysBounceHorizontal = false
        web.allowsBackForwardNavigationGestures = false
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        context.coordinator.paint(pingPong: false)
        context.coordinator.load()
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.setActive(active)
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: MinikMathWebBridge.handlerName)
        web.navigationDelegate = nil
        web.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        private let model: MinikMathWebModel
        private let directory = Bundle.main.url(forResource: "MinikMathWeb", withExtension: nil)
        private var active = true
        /// Android's pageEpoch: a result is released only on the page that finished the round.
        private var pageEpoch = 0

        init(model: MinikMathWebModel) {
            self.model = model
        }

        func load() {
            guard let directory else {
                model.failed = true
                return
            }
            web?.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        }

        /// Android's onPause stops every sound and pauses Ping Pong; onResume resumes Ping Pong.
        func setActive(_ value: Bool) {
            guard active != value else { return }
            active = value
            if value {
                if isPingPong(web?.url) {
                    web?.evaluateJavaScript("window.PongExtras?.nativePause(false);", completionHandler: nil)
                }
            } else {
                model.setPlaying(false)
                web?.evaluateJavaScript("window.MinikAudio?.stopAll(); window.PongExtras?.nativePause(true);",
                                        completionHandler: nil)
            }
        }

        /// Android's backgrounds: white behind the Math pages, dark navy behind Ping Pong.
        func paint(pingPong: Bool) {
            let color = pingPong ? MinikMathWebColors.pingPongBackground : UIColor.white
            web?.backgroundColor = color
            web?.scrollView.backgroundColor = color
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let directory,
                  MinikMathWebPages.isTrusted(message.frameInfo.request.url, directory: directory),
                  let body = message.body as? [String: Any], let type = body["type"] as? String else {
                return
            }
            switch type {
            case "playing":
                model.setPlaying(active && body["active"] as? Bool == true)
            case "settings":
                model.openParents(language: body["lang"] as? String)
            case "language":
                model.setLanguage(body["lang"] as? String)
            case "finish":
                guard let id = body["id"] as? String, MinikMathWebBridge.isValidRoundID(id),
                      let token = body["token"] as? String, MinikMathWebBridge.isValidToken(token) else {
                    return
                }
                let epoch = pageEpoch
                model.finishRound(id) { [weak self] in
                    guard let self, epoch == self.pageEpoch, let web = self.web,
                          MinikMathWebPages.isTrusted(web.url, directory: directory) else {
                        return
                    }
                    web.evaluateJavaScript(MinikMathWebBridge.completion(token: token), completionHandler: nil)
                }
            default:
                // "prepare": Android loads an ad on a menu. The shared ad service already keeps one
                // loaded (it loads at start and after every ad).
                break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else {
                decisionHandler(.cancel)
                return
            }
            if let directory, MinikMathWebPages.isBundled(url, directory: directory) {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            // Android opens web links in the browser; here a grown-up confirms first, as Apple
            // asks of apps for children. minik://exit never comes: no exit button is offered.
            if let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
                model.openLink(url)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            pageEpoch += 1
            model.setPlaying(false)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let pingPong = isPingPong(webView.url)
            paint(pingPong: pingPong)
            model.pageChanged(pingPong: pingPong)
            if pingPong {
                webView.evaluateJavaScript("window.PongExtras?.nativePause(\(active ? "false" : "true"));",
                                           completionHandler: nil)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // The system ended the web content process: reopen Math home. Progress is in the
            // web app's storage; a round in progress is not counted.
            pageEpoch += 1
            load()
        }

        private func report(_ error: Error) {
            let error = error as NSError
            // A cancelled load (a new page, or a link handed to the grown-up gate) is no failure.
            if error.code == NSURLErrorCancelled { return }
            if error.domain == "WebKitErrorDomain" && error.code == 102 { return }
            model.failed = true
        }

        private func isPingPong(_ url: URL?) -> Bool {
            guard let directory else { return false }
            return MinikMathWebPages.isPingPong(url, directory: directory)
        }
    }
}
#endif
