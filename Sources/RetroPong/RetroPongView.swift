import SwiftUI
import WebKit
import AVFoundation

/// The same Bounce game in every host. Hosts own navigation and, like Android, the ad boundary
/// after a finished game and the "For parents" entry.
struct RetroPongView: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    @State private var failure = false
    @State private var reload = UUID()
    var onExit: (() -> Void)? = nil
    /// Called after a finished game; the host shows its ad (if any) and then calls the completion.
    var onMatchFinished: ((@escaping () -> Void) -> Void)? = nil
    /// Opens the host's grown-up gate and purchases; nil hides the "For parents" link.
    var onParents: (() -> Void)? = nil
    /// Android Bounce `menuIdle`: called about every second while the setup with the "For parents"
    /// link is idle on screen, so the host can show its family reminder.
    var onMenuIdle: (() -> Void)? = nil
    private var hebrew: Bool { locale.language.languageCode?.identifier == "he" }
    var body: some View {
        ZStack {
            Color(red: 17 / 255, green: 24 / 255, blue: 43 / 255).ignoresSafeArea()
            if failure {
                VStack(spacing: 20) {
                    Text(hebrew ? "לא ניתן לפתוח את המשחק כרגע." : "The game could not be opened.").multilineTextAlignment(.center)
                    Button(hebrew ? "נסו שוב" : "Try again") { failure = false; reload = UUID() }.buttonStyle(.borderedProminent)
                    if let onExit { Button(hebrew ? "חזרה" : "Back", action: onExit) }
                }.foregroundStyle(.white).padding()
            } else {
                RetroPongWebView(language: hebrew ? "he" : "en", active: phase == .active,
                                 onExit: onExit, onMatchFinished: onMatchFinished, onParents: onParents,
                                 onMenuIdle: onMenuIdle, onFailure: { failure = true }).id(reload)
                // UIKit/WebKit receives the usable safe-area size; no double CSS notch padding.
            }
        }.preferredColorScheme(.light)
    }
}

private struct RetroPongWebView: UIViewRepresentable {
    let language: String, active: Bool
    let onExit: (() -> Void)?
    let onMatchFinished: ((@escaping () -> Void) -> Void)?
    let onParents: (() -> Void)?
    let onMenuIdle: (() -> Void)?
    let onFailure: () -> Void
    func makeCoordinator() -> Coordinator {
        Coordinator(language: language, active: active, onExit: onExit, onMatchFinished: onMatchFinished,
                    onParents: onParents, onMenuIdle: onMenuIdle, onFailure: onFailure)
    }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "MinikNative/iOS MinikNativeInsets/1 MinikNativeImmersive/1"
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "retroPong")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false; web.backgroundColor = UIColor(red: 17 / 255, green: 24 / 255, blue: 43 / 255, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        web.scrollView.alwaysBounceVertical = false; web.scrollView.alwaysBounceHorizontal = false
        web.allowsBackForwardNavigationGestures = false
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        context.coordinator.load()
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onExit = onExit; coordinator.onFailure = onFailure
        coordinator.onMatchFinished = onMatchFinished; coordinator.onParents = onParents
        coordinator.onMenuIdle = onMenuIdle
        coordinator.setActive(active)
        if coordinator.language != language {
            coordinator.language = language
            // A locale change intentionally reopens setup, retaining progress/settings.
            coordinator.load()
        }
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.close()
        web.configuration.userContentController.removeScriptMessageHandler(forName: "retroPong")
        web.navigationDelegate = nil; web.stopLoading()
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let storage = RetroPongStorage()
        weak var web: WKWebView?
        var language: String, active: Bool
        var onExit: (() -> Void)?, onFailure: () -> Void
        var onMatchFinished: ((@escaping () -> Void) -> Void)?
        var onParents: (() -> Void)?
        var onMenuIdle: (() -> Void)?
        private var music: AVAudioPlayer?, musicRequested = false, closed = false, exitSent = false
        private let directory = Bundle.main.url(forResource: "RetroPong", withExtension: nil)
        init(language: String, active: Bool, onExit: (() -> Void)?, onMatchFinished: ((@escaping () -> Void) -> Void)?,
             onParents: (() -> Void)?, onMenuIdle: (() -> Void)?, onFailure: @escaping () -> Void) {
            self.language = language; self.active = active; self.onExit = onExit
            self.onMatchFinished = onMatchFinished; self.onParents = onParents
            self.onMenuIdle = onMenuIdle; self.onFailure = onFailure
        }
        func load() {
            guard let directory else { onFailure(); return }
            music?.stop(); music = nil; musicRequested = false; exitSent = false
            web?.configuration.userContentController.removeAllUserScripts()
            let bootstrap = storage.bootstrap(language: language, paused: !active, canExit: onExit != nil,
                                              monetization: onMatchFinished != nil, parents: onParents != nil)
            web?.configuration.userContentController.addUserScript(WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            // App Store captures only: ios-host.js stages the named Bounce screen.
            if let scene = StoreScreenshotScene.value(after: "bounce"),
               scene.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
                web?.configuration.userContentController.addUserScript(WKUserScript(
                    source: "window.MinikScreenshotScene=\"\(scene)\";",
                    injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
            web?.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        }
        func setActive(_ value: Bool) {
            guard active != value else { return }; active = value
            web?.evaluateJavaScript("window.MinikRetroHost?.setActive(\(value ? "true" : "false"));", completionHandler: nil)
            syncMusic()
        }
        private func syncMusic() {
            guard active && musicRequested && !closed else { music?.pause(); return }
            if music == nil, let url = directory?.appendingPathComponent("assets/audio/cool_music2.mp3"), let player = try? AVAudioPlayer(contentsOf: url) {
                music = player; player.numberOfLoops = -1; player.prepareToPlay()
            }
            if music?.isPlaying == false { music?.play() }
        }
        func close() {
            closed = true; musicRequested = false; music?.stop(); music = nil
            web?.evaluateJavaScript("window.MinikRetroHost?.setActive(false);window.stopPongSession?.();", completionHandler: nil)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !closed, message.frameInfo.isMainFrame, let directory,
                  RetroPongNavigation.isBundled(message.frameInfo.request.url, directory: directory),
                  let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "save": if let state = body["state"] as? String { storage.save(state) }
            case "music": musicRequested = body["playing"] as? Bool == true; syncMusic()
            case "exit":
                musicRequested = false; music?.stop(); music = nil
                if !exitSent, let onExit { exitSent = true; onExit() }
            case "matchFinished":
                guard let token = body["token"] as? String, !token.isEmpty, token.count <= 12,
                      token.allSatisfy({ $0.isASCII && $0.isNumber }) else { return }
                let complete: () -> Void = { [weak self] in
                    self?.web?.evaluateJavaScript("window.MinikMonetization?.complete(\"\(token)\");", completionHandler: nil)
                }
                if let onMatchFinished { onMatchFinished(complete) } else { complete() }
            case "parents": onParents?()
            case "menuIdle": if active { onMenuIdle?() }
            default: break
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("window.MinikRetroHost?.setActive(\(active ? "true" : "false"));", completionHandler: nil)
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let directory, RetroPongNavigation.isBundled(action.request.url, directory: directory) { decisionHandler(.allow) }
            else { decisionHandler(.cancel) } // The bundled game has no external pages; ads and purchases stay native.
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { onFailure() } }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { onFailure() } }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // Reopen setup after a system process eviction; never invent a completed match.
            load()
        }
    }
}
