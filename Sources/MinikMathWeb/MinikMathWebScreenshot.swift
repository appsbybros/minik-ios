#if MINIK_MATH_WEB
import Foundation

/// App Store captures only: `-MinikScreenshotScene web.<scene>` (appstore/screenshots.json) opens one screen of the
/// bundled web app, which itself stays byte-identical to Android's. The script is added only for such a launch, so
/// players never get it. It seeds Math.random (the same questions in every capture) and stages Ping Pong's progress
/// in memory, never in the web app's storage.
enum MinikMathWebScreenshot {
    static let scenes: Set<String> = ["choose", "quiz", "result", "train", "madness"]

    static var script: String? {
        guard let scene = StoreScreenshotScene.value(after: "web"), scenes.contains(scene) else { return nil }
        return source(scene: scene)
    }

    static func source(scene: String) -> String {
        """
        (function(){
          var scene = "\(scene)";
          var seed = 20261024;
          Math.random = function(){
            seed = (seed + 0x6D2B79F5) | 0;
            var t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
            t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
          };
          if (/\\/pingpong\\/index\\.html$/.test(location.pathname)) {
            var key = "minik.pong.progress.v1";
            var train = scene === "train";
            var staged = JSON.stringify({version: 1, points: train ? 1280 : 240, operation: "addition",
              levels: {addition: train ? 12 : 1, subtraction: 1, multiply: 1, divide: 1},
              controlDesktop: "arrows", controlTouch: "arrows", trainMode: train ? "tap" : "off",
              opponentDifficulty: "beginner", targetScore: 5, balloonMadness: !train});
            var get = Storage.prototype.getItem, set = Storage.prototype.setItem;
            Storage.prototype.getItem = function(name){
              if (this === localStorage && name === key) return staged;
              return get.call(this, name);
            };
            Storage.prototype.setItem = function(name, value){
              if (this === localStorage && name === key) { staged = String(value); return; }
              return set.call(this, name, value);
            };
            window.addEventListener("load", function(){
              setTimeout(function(){ if (window.resetPong) window.resetPong(); }, 1200);
            }, {once: true});
            return;
          }
          window.addEventListener("load", function(){
            setTimeout(function(){
              if (scene === "choose") {
                chooseModeFromHome("multiply");
              } else if (scene === "quiz") {
                selectedN = 7; startQuiz("addition", "choose"); qIndex = 3; good = 3; render();
              } else if (scene === "result") {
                selectedN = 6; startQuiz("multiply", "choose"); qIndex = 9; good = 9; bad = 1; view = "result"; render();
              } else {
                openPongPage();
              }
            }, 800);
          }, {once: true});
        })();
        """
    }
}
#endif
