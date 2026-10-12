import XCTest
@testable import MinikMath

/// The host contract with Android's web app: the checks of Android's MonetizationBridge, the
/// trusted pages of its MainActivity, and the bundled files that call the bridge.
final class MinikMathWebBridgeTests: XCTestCase {
    func testRoundIDsAndTokensFollowAndroidsChecks() {
        XCTAssertTrue(MinikMathWebBridge.isValidRoundID("math/0f8fdd2b-6c1a-4b5e-9d1e-3c7a2b1f4e55"))
        XCTAssertTrue(MinikMathWebBridge.isValidRoundID("retro/l2m3n4_x"))
        XCTAssertFalse(MinikMathWebBridge.isValidRoundID(""))
        XCTAssertFalse(MinikMathWebBridge.isValidRoundID("math/a,b"))
        XCTAssertFalse(MinikMathWebBridge.isValidRoundID("math/<script>"))
        XCTAssertFalse(MinikMathWebBridge.isValidRoundID(String(repeating: "a", count: 181)))
        XCTAssertTrue(MinikMathWebBridge.isValidToken("1"))
        XCTAssertTrue(MinikMathWebBridge.isValidToken("123456789012"))
        XCTAssertFalse(MinikMathWebBridge.isValidToken(""))
        XCTAssertFalse(MinikMathWebBridge.isValidToken("1234567890123"))
        XCTAssertFalse(MinikMathWebBridge.isValidToken("1a"))
        XCTAssertEqual(MinikMathWebBridge.completion(token: "42"), "window.MinikMonetization?.complete(\"42\");")
    }

    func testTheWebAppSpeaksEnglishOrHebrew() {
        XCTAssertEqual(MinikMathWebBridge.language("he"), "he")
        XCTAssertEqual(MinikMathWebBridge.language("en"), "en")
        XCTAssertEqual(MinikMathWebBridge.language(nil), "en")
        XCTAssertEqual(MinikMathWebBridge.language("fr"), "en")
    }

    func testOnlyTheMathAndPingPongPagesAreTrusted() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MinikMathWeb")
        let math = directory.appendingPathComponent("index.html")
        var pong = URLComponents(url: directory.appendingPathComponent("pingpong/index.html"), resolvingAgainstBaseURL: false)!
        pong.query = "from=math&madness=off&lang=he"
        let script = directory.appendingPathComponent("app.js")
        XCTAssertTrue(MinikMathWebPages.isTrusted(math, directory: directory))
        XCTAssertTrue(MinikMathWebPages.isTrusted(pong.url, directory: directory))
        XCTAssertFalse(MinikMathWebPages.isTrusted(script, directory: directory))
        XCTAssertTrue(MinikMathWebPages.isBundled(script, directory: directory))
        XCTAssertTrue(MinikMathWebPages.isPingPong(pong.url, directory: directory))
        XCTAssertFalse(MinikMathWebPages.isPingPong(math, directory: directory))
        XCTAssertFalse(MinikMathWebPages.isBundled(URL(string: "https://miniklearn.com/"), directory: directory))
        XCTAssertFalse(MinikMathWebPages.isBundled(directory.deletingLastPathComponent().appendingPathComponent("other.html"),
                                                   directory: directory))
    }

    func testTheBridgeDefinesAndroidsInterface() {
        let script = MinikMathWebBridge.script
        for method in ["prepare:", "playing:", "settings:", "finish:"] {
            XCTAssertTrue(script.contains(method), method)
        }
        XCTAssertTrue(script.contains("window.MinikAdsNative="))
        XCTAssertTrue(script.contains("messageHandlers.\(MinikMathWebBridge.handlerName)."))
        XCTAssertTrue(MinikMathWebBridge.userAgentMarkers.contains("MinikNative/Android"))
        XCTAssertFalse(MinikMathWebBridge.userAgentMarkers.contains("MinikNativeExit"),
                       "iOS apps do not close themselves")
    }

    /// The bundled web app is Android's, and still calls the bridge this host provides.
    func testTheBundledWebAppUsesTheBridge() throws {
        let directory = try XCTUnwrap(Bundle.main.url(forResource: "MinikMathWeb", withExtension: nil))
        for page in ["index.html", "pingpong/index.html", "app.js", "minik-monetization.js"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(page).path), page)
        }
        let bridge = try String(contentsOf: directory.appendingPathComponent("minik-monetization.js"), encoding: .utf8)
        XCTAssertTrue(bridge.contains("window.MinikAdsNative"))
        for call in ["native.playing(", "native.finish(", "native.prepare(", "native.settings("] {
            XCTAssertTrue(bridge.contains(call), call)
        }
        let app = try String(contentsOf: directory.appendingPathComponent("app.js"), encoding: .utf8)
        XCTAssertTrue(app.contains("MinikNative\\/Android"), "The web app still looks for Android's host marker")
    }
}
