"""Minik Math (target MinikMath): Android Minik Math's web app, unchanged, in the iOS host.

Checks that Resources/MinikMathWeb is byte-identical to the copy recorded in docs/minik-math-web-manifest.json
(Android C:/Projects/minikMath app/src/main/assets/www at the recorded commit), that the Android web app has not
changed since (when that repository is on this computer), and the host contract the web files rely on.
"""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "Resources/MinikMathWeb"
ANDROID = Path("C:/Projects/minikMath")
problems = []


def check(ok, message):
    if not ok:
        problems.append(message)


def text(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


manifest = json.loads(text("docs/minik-math-web-manifest.json"))
copied = {path.relative_to(WEB).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
          for path in sorted(WEB.rglob("*")) if path.is_file()}
recorded = manifest["files"]
for name in sorted(set(copied) | set(recorded)):
    if copied.get(name) != recorded.get(name):
        state = "missing" if name not in copied else "added" if name not in recorded else "changed"
        check(False, f"Resources/MinikMathWeb/{name} is {state} compared with the Android copy (docs/minik-math-web-manifest.json)")

# Drift: the Android web app moved on since the copy (re-copy, then refresh the manifest).
if (ANDROID / ".git").exists():
    result = subprocess.run(["git", "-C", str(ANDROID), "rev-parse", "HEAD:app/src/main/assets/www"],
                            capture_output=True, text=True)
    if result.returncode == 0:
        check(result.stdout.strip() == manifest["androidTree"],
              f"Android Minik Math's web app changed since {manifest['androidCommit']}: copy app/src/main/assets/www again "
              "and refresh docs/minik-math-web-manifest.json (docs/minik-math-ios.md)")

project = text("project.yml").replace("\r\n", "\n")
targets = project.split("\nschemes:\n")[0]
math = targets.split("\n  MinikMath:\n", 1)[1].split("\n  MinikMathTests:\n", 1)[0]
check("path: Resources/MinikMathWeb\n        type: folder" in math, "The web app must be a folder resource (relative paths inside it)")
check('"$(inherited) MINIK_MATH_WEB"' in math, "MinikMath must compile with MINIK_MATH_WEB")
check("MINIK_MATH_BUNDLE_IDENTIFIER: com.appsbybros.minik.math\n" in math, "MinikMath must keep com.appsbybros.minik.math")
check("CFBundleLocalizations: [en, he]" in math, "The web app speaks English and Hebrew")
check("FirebaseApple" not in math, "Minik Math has no Firebase, as on Android's iOS-relevant path")
plus = targets.split("\n  MinikMathPlus:\n", 1)[1].split("\n  MinikMath:\n", 1)[0]
check("com.appsbybros.minik.math.plus" in plus and "CFBundleDisplayName: Minik Math Plus" in plus,
      "The original math app is Minik Math Plus")

bridge = text("Sources/MinikMathWeb/MinikMathWebBridge.swift")
check("MinikNative/Android" in bridge and "MinikNativeExit" not in bridge.split("static let userAgentMarkers", 1)[1].split("\n", 1)[0],
      "The host must present Android's app marker without the exit marker")
check("window.MinikAdsNative=Object.freeze" in bridge, "The bridge must define Android's MinikAdsNative before the page scripts")
monetization = (WEB / "minik-monetization.js").read_text(encoding="utf-8")
for call in ("native.prepare(", "native.playing(", "native.settings(", "native.finish("):
    check(call in monetization, f"minik-monetization.js no longer calls {call}; update the bridge")
    method = call.split(".")[1].rstrip("(")
    check(f"{method}:function" in bridge, f"The bridge does not define {method}")
check("window.MinikMonetization" in monetization and "complete(token)" in monetization,
      "minik-monetization.js no longer exposes MinikMonetization.complete(token)")
app = text("Sources/MinikApp.swift")
check("#elseif MINIK_MATH_WEB\n            MinikMathWebRootView()" in app.replace("\r\n", "\n"), "MinikApp must launch the Minik Math web host")
tests = text("Tests/MinikMathTests/MinikMathAdPolicyTests.swift")
check(len(re.findall(r"func test", tests)) >= 17, "All 17 Android AdPolicyTest cases must stay ported")

for problem in problems:
    print("FAIL " + problem)
print(f"{len(copied)} web files checked; {len(problems)} problem(s)")
sys.exit(1 if problems else 0)
