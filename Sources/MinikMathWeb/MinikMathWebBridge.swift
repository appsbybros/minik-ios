#if MINIK_MATH_WEB
import Foundation

/// What the bundled web app expects from Android's host (MainActivity and its MonetizationBridge),
/// recreated for WKWebView. The web files themselves stay byte-identical to Android's.
enum MinikMathWebBridge {
    static let handlerName = "minikMath"

    /// Android's host markers in the user agent. The web files turn on their app behaviour (native
    /// insets; Ping Pong's arrows and paddle ranks) only for "MinikNative/Android", so the iOS host
    /// sends it too. "MinikNativeExit/1" is left out: iOS apps do not close themselves, so the web
    /// app shows no exit button.
    static let userAgentMarkers = "MinikNative/Android MinikNativeInsets/1 MinikNativeImmersive/1 MinikHost/iOS"

    /// Defines window.MinikAdsNative, Android's JavaScript interface, before the web app's scripts
    /// run (minik-monetization.js reads it once), and reports the page language, which the web
    /// app's EN/HE switch sets, for the native sheets.
    static let script = """
    (function(){
      var post=function(message){try{window.webkit.messageHandlers.minikMath.postMessage(message);}catch(_){}};
      window.MinikAdsNative=Object.freeze({
        prepare:function(){post({type:"prepare"});},
        playing:function(active){post({type:"playing",active:!!active});},
        settings:function(lang){post({type:"settings",lang:String(lang||"")});},
        finish:function(id,token){post({type:"finish",id:String(id),token:String(token)});}
      });
      var language=function(){post({type:"language",lang:String(document.documentElement.lang||"")});};
      new MutationObserver(language).observe(document.documentElement,{attributes:true,attributeFilter:["lang"]});
      document.addEventListener("DOMContentLoaded",language);
    })();
    """

    /// Android's checks in MonetizationBridge.finish: a round ID and a callback token.
    static func isValidRoundID(_ id: String) -> Bool {
        id.range(of: "^[a-zA-Z0-9/_-]{1,180}$", options: .regularExpression) != nil
    }

    static func isValidToken(_ token: String) -> Bool {
        token.range(of: "^[0-9]{1,12}$", options: .regularExpression) != nil
    }

    /// The web app speaks English or Hebrew.
    static func language(_ value: String?) -> String {
        value == "he" ? "he" : "en"
    }

    /// The JavaScript that releases a finished round's results (the token is digits only).
    static func completion(token: String) -> String {
        "window.MinikMonetization?.complete(\"\(token)\");"
    }
}

/// The bundled pages, as Android's MainActivity tells them apart.
enum MinikMathWebPages {
    /// Any file inside the bundled web app folder.
    static func isBundled(_ url: URL?, directory: URL) -> Bool {
        guard let path = path(of: url) else { return false }
        return path.hasPrefix(root(directory) + "/")
    }

    /// Android's trustedMoneyPage: the Math page or the Ping Pong page, which alone may talk
    /// to the ad and purchase host.
    static func isTrusted(_ url: URL?, directory: URL) -> Bool {
        guard let path = path(of: url) else { return false }
        return path == root(directory) + "/index.html" || path == root(directory) + "/pingpong/index.html"
    }

    /// Android's isEmbeddedPingPong.
    static func isPingPong(_ url: URL?, directory: URL) -> Bool {
        path(of: url) == root(directory) + "/pingpong/index.html"
    }

    private static func root(_ directory: URL) -> String {
        directory.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func path(of url: URL?) -> String? {
        guard let url, url.isFileURL else { return nil }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
#endif
