#!/usr/bin/env python3
r"""Offline audit of how the Triple Shot iOS port (TripleShot/, target MinikTripleShot) is built, tested and released,
against the read-only Android project it is ported from (TripleShotGame, com.appsbybros.minik.swish). It writes no
file and contacts no server.

Checks (one line each, then RESULT: PASS or FAIL):
  project    project.yml: the MinikTripleShot target (sources, generated Info.plist, settings, Firebase products), the
             TripleShotTests target and the MinikTripleShot scheme; the Android label, application id and versions; the
             scene delegate the Info.plist names; the release script's naming rule; loose resources that the groups
             copy into the bundle root; the Firebase registration (committed, listed, allowed by .gitignore and
             registered for this app) or its absence.
  ci         The Compile Check builds the app, compiles and runs TripleShotTests; the workflows start only by hand; the
             App Store Connect script and the release-configuration audit know the app.
  icon       The target's one app icon set: a 1024 x 1024 opaque RGB PNG, Android's art/store-ready/launcher-source.png
             scaled with Lanczos (the same framing as the Play icon).
  privacy    Resources/Privacy/TripleShot/PrivacyInfo.xcprivacy: no tracking; UserDefaults (CA92.1) and SystemBootTime
             (35F9.1) exactly as the app code needs them; the online-play data types; no other required-reason API
             named in the app code (the same scan as Scripts/audit-release-configuration.ps1).
  family     The family catalogue entry "tripleshot" belongs to this bundle id and its art is bundled.
  resources  TripleShot/Res is what Scripts/tripleshot-sync-resources.py makes from Android (its --check).
  swift      TripleShot/ has exactly one @main; no Swift file of the app or its tests holds a raw bidi or control
             character, or would be committed with CR line endings.
  release    Only when the owner's release script is found: its own project.yml parser sees the app, its scheme and
             its inputs. The entries its tables still need are printed as notes (they are outside this repository).

Usage:  python Scripts/audit-tripleshot.py [--android PATH] [--release PATH] [--skip-resources]
--android defaults to the Android project Scripts/tripleshot-sync-resources.py reads. Requires PyYAML and Pillow.
"""
import argparse
import ast
import importlib.util
import json
import os
import plistlib
import re
import subprocess
import sys

sys.dont_write_bytecode = True

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = "MinikTripleShot"
TESTS = "TripleShotTests"
BUNDLE_ID = "com.appsbybros.minik.swish"
CATALOG_KEY = "tripleshot"
FIREBASE_PROJECT = "minikswish"
DATABASE_URL = "https://minikswish-default-rtdb.europe-west1.firebasedatabase.app"
FIREBASE_PLIST = "Config/Firebase/MinikTripleShot/GoogleService-Info.plist"
PRIVACY = "Resources/Privacy/TripleShot/PrivacyInfo.xcprivacy"
ICON_SET = "TripleShot/Assets.xcassets/AppIcon.appiconset"
APP_SHELL = "TripleShot/App/TripleShotApp.swift"
SYNC = "Scripts/tripleshot-sync-resources.py"
RELEASE = r"C:\Projects\Minik-to-IOS\public-export\release_ios.py"

IPHONE_ORIENTATIONS = ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft",
                       "UIInterfaceOrientationLandscapeRight"]
IPAD_ORIENTATIONS = ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                     "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
# Android res/values (the default resources) is Hebrew, res/values-en English.
LOCALIZATIONS = ["he", "en"]
FIREBASE_PRODUCTS = ["FirebaseCore", "FirebaseAuth", "FirebaseDatabase"]
# Scripts/audit-release-configuration.ps1: required-reason APIs outside the UserDefaults / SystemBootTime inventory.
OTHER_REASON_APIS = re.compile(
    r"\b(mach_absolute_time|creationDate|modificationDate|fileModificationDate|contentModificationDateKey|"
    r"creationDateKey|volumeAvailableCapacityKey|volumeAvailableCapacityForImportantUsageKey|"
    r"volumeAvailableCapacityForOpportunisticUsageKey|volumeTotalCapacityKey|activeInputModes)\b")
# Clocks that count from boot: Apple's "system boot time" category (reason 35F9.1).
BOOT_TIME_APIS = re.compile(r"\bsystemUptime\b|\bCLOCK_UPTIME_RAW\b|\bCLOCK_MONOTONIC_RAW\b|\bmach_absolute_time\b|"
                            r"\bmach_continuous_time\b|\bCACurrentMediaTime\b")
# Characters a Swift source must spell as \u{...} escapes: bidi controls and marks, the byte-order mark, line and
# paragraph separators and C0/C1 controls other than tab, line feed and carriage return (CR is checked apart).
FORBIDDEN = sorted({0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069,
                    0xFEFF, 0x2028, 0x2029} | (set(range(0x20)) - {0x09, 0x0A, 0x0D}) | set(range(0x7F, 0xA0)))
FORBIDDEN_CHARACTERS = re.compile("[" + "".join(re.escape(chr(code)) for code in FORBIDDEN) + "]")


def path(rel):
    return os.path.join(ROOT, *rel.split("/"))


def read_bytes(rel):
    with open(path(rel), "rb") as handle:
        return handle.read()


def read_text(rel):
    return read_bytes(rel).decode("utf-8")


def git(*args):
    result = subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True, encoding="utf-8", errors="replace")
    return result.stdout if result.returncode == 0 else ""


def text_attributes(files):
    """git's "text" attribute per path (set, unset = "-text", unspecified or a value). NUL-separated bytes: a
    text-mode pipe on Windows would add a CR to every path."""
    result = subprocess.run(["git", "-C", ROOT, "check-attr", "-z", "--stdin", "text"], capture_output=True,
                            input=b"".join(name.encode("utf-8") + b"\0" for name in files))
    if result.returncode:
        return {}
    fields = result.stdout.decode("utf-8", "replace").split("\0")
    return {fields[i]: fields[i + 2] for i in range(0, len(fields) - 2, 3)}


def swift_files(*folders):
    found = []
    for folder in folders:
        for base, dirs, files in os.walk(path(folder)):
            dirs.sort()
            for name in sorted(files):
                if name.endswith(".swift"):
                    found.append(os.path.relpath(os.path.join(base, name), ROOT).replace(os.sep, "/"))
    return found


class Check:
    """The problems and notes of one check; done() prints its line."""

    def __init__(self, name):
        self.name = name
        self.problems = []
        self.notes = []

    def require(self, condition, message):
        if not condition:
            self.problems.append(message)
        return bool(condition)

    def note(self, message):
        self.notes.append(message)

    def done(self, summary):
        print("%s: %s" % (self.name, "PROBLEMS" if self.problems else summary))
        for message in self.problems:
            print("  " + message)
        for message in self.notes:
            print("  note: " + message)
        return not self.problems


# ---------------------------------------------------------------- project.yml

def load_yaml(rel):
    import yaml
    return yaml.safe_load(read_text(rel))


def entries_of(target):
    return [dict(item) if isinstance(item, dict) else {"path": item} for item in target.get("sources") or []]


def two_space_blocks(text, section):
    """release_ios.py's view of project.yml: names at exactly two spaces under a top-level key."""
    names, inside = [], False
    for line in text.splitlines():
        top = re.match(r"([A-Za-z]\w*):", line)
        if top:
            inside = top.group(1) == section
            continue
        child = re.match(r"  ([A-Za-z]\w*):", line)
        if inside and child:
            names.append(child.group(1))
    return names


def android_facts(android):
    facts = {}
    gradle = os.path.join(android, "app", "build.gradle.kts")
    manifest = os.path.join(android, "app", "src", "main", "AndroidManifest.xml")
    if os.path.isfile(gradle):
        text = open(gradle, encoding="utf-8").read()
        for key, pattern in (("applicationId", r'applicationId\s*=\s*"([^"]+)"'), ("versionCode", r"versionCode\s*=\s*(\d+)"),
                             ("versionName", r'versionName\s*=\s*"([^"]+)"')):
            match = re.search(pattern, text)
            if match:
                facts[key] = match.group(1)
    if os.path.isfile(manifest):
        text = open(manifest, encoding="utf-8").read()
        application = re.search(r"<application\b[^>]*>", text, re.S)
        label = re.search(r'android:label="([^"]*)"', application.group(0)) if application else None
        if label:
            facts["label"] = label.group(1)
    return facts


def loose_resources():
    """Non-Swift files the TripleShot (minus Res) and Family groups copy flat into the bundle root (XcodeGen skips only
    .DS_Store and *.orig; asset catalogues compile, .lproj folders localize)."""
    names = []
    for folder in ("TripleShot", "Family"):
        for base, dirs, files in os.walk(path(folder)):
            rel = os.path.relpath(base, ROOT).replace(os.sep, "/")
            dirs[:] = sorted(d for d in dirs if not d.endswith((".xcassets", ".lproj")) and
                             not (rel == "TripleShot" and d == "Res"))
            for name in sorted(files):
                if not name.endswith((".swift", ".orig")) and name != ".DS_Store":
                    names.append((rel + "/" + name, name))
    return names


def check_project(android):
    c = Check("project")
    text = read_text("project.yml")
    project = load_yaml("project.yml")
    targets, schemes = project.get("targets") or {}, project.get("schemes") or {}
    target = targets.get(APP)
    if not c.require(isinstance(target, dict), "project.yml has no target " + APP):
        return c.done("")
    facts = android_facts(android)
    c.require(facts, "Android project not found at %s (pass --android)" % android)

    c.require(target.get("type") == "application" and target.get("platform") == "iOS", APP + " is not an iOS application")
    c.require("templates" not in target, APP + " must not use a target template (game ports list their own sources)")
    entries = entries_of(target)
    by_path = {e["path"]: e for e in entries}
    expected = {
        "TripleShot": {"excludes": ["Res/**"]},
        "TripleShot/Res": {"type": "folder", "buildPhase": "resources"},
        "TripleShot/Res/R.swift": {},
        "Family": {},
        PRIVACY: {"buildPhase": "resources"},
    }
    for rel, keys in expected.items():
        entry = by_path.get(rel)
        if c.require(entry is not None, "%s sources lack %s" % (APP, rel)):
            got = {k: v for k, v in entry.items() if k != "path"}
            c.require(got == keys, "%s source %s is %r, expected %r" % (APP, rel, got, keys))
    for entry in entries:
        rel = entry["path"]
        c.require(os.path.exists(path(rel)), "%s source %s does not exist (XcodeGen fails)" % (APP, rel))
        if rel not in expected and rel != FIREBASE_PLIST:
            c.note("extra source " + rel)

    info = target.get("info") or {}
    c.require(info.get("path") == "GeneratedInfoPlists/%s-Info.plist" % APP, APP + " info.path is not generated")
    properties = info.get("properties") or {}
    delegates = re.findall(r"\bclass\s+(\w+)\s*:[^{]*\bUIWindowSceneDelegate\b", read_text(APP_SHELL))
    c.require(len(delegates) == 1, "%s declares %d window scene delegates" % (APP_SHELL, len(delegates)))
    want = {
        "CFBundleDisplayName": facts.get("label", "Triple Shot"),
        "CFBundleDevelopmentRegion": "he",
        "MinikFamilyCatalogKey": CATALOG_KEY,
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "CFBundleLocalizations": LOCALIZATIONS,
        "ITSAppUsesNonExemptEncryption": False,
        "UILaunchScreen": {},
        "UIApplicationSceneManifest": {
            "UIApplicationSupportsMultipleScenes": False,
            "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [{
                "UISceneConfigurationName": "Default Configuration",
                "UISceneDelegateClassName": "$(PRODUCT_MODULE_NAME)." + (delegates[0] if delegates else "?"),
            }]},
        },
        "UIRequiresFullScreen": True,
        "UISupportedInterfaceOrientations": IPHONE_ORIENTATIONS,
        "UISupportedInterfaceOrientations~ipad": IPAD_ORIENTATIONS,
    }
    for key, value in want.items():
        c.require(properties.get(key) == value, "Info.plist %s is %r, expected %r" % (key, properties.get(key), value))
    for key in sorted(set(properties) - set(want)):
        c.note("extra Info.plist key " + key)

    settings = (target.get("settings") or {}).get("base") or {}
    want = {
        "PRODUCT_BUNDLE_IDENTIFIER": facts.get("applicationId", BUNDLE_ID),
        # testflight.yml archives "$SCHEME.app"; the tests import the module of this name.
        "PRODUCT_NAME": APP,
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "MINIK_MARKETING_VERSION": facts.get("versionName", "1.0"),
        "MINIK_BUILD_NUMBER": facts.get("versionCode", "1"),
    }
    for key, value in want.items():
        c.require(str(settings.get(key)) == value, "setting %s is %r, expected %r" % (key, settings.get(key), value))
    c.require("-ObjC" in str(settings.get("OTHER_LDFLAGS", "")).split(), "OTHER_LDFLAGS lacks -ObjC (Firebase)")
    c.require(os.path.isdir(path(ICON_SET)), ICON_SET + " is missing")
    products = [(d.get("package"), d.get("product")) for d in target.get("dependencies") or []]
    c.require(products == [("FirebaseApple", p) for p in FIREBASE_PRODUCTS],
              "dependencies are %r, expected FirebaseApple %s (Android has no ads or purchases)" % (products, FIREBASE_PRODUCTS))

    tests = targets.get(TESTS)
    if c.require(isinstance(tests, dict), "project.yml has no target " + TESTS):
        c.require(tests.get("type") == "bundle.unit-test" and tests.get("platform") == "iOS", TESTS + " is not an iOS unit-test bundle")
        c.require([e["path"] for e in entries_of(tests)] == ["Tests/" + TESTS], TESTS + " sources are not Tests/" + TESTS)
        c.require(tests.get("dependencies") == [{"target": APP}], TESTS + " is not hosted in " + APP)
        base = (tests.get("settings") or {}).get("base") or {}
        c.require(base.get("PRODUCT_BUNDLE_IDENTIFIER") == BUNDLE_ID + ".tests", TESTS + " bundle id is not %s.tests" % BUNDLE_ID)
        c.require(base.get("GENERATE_INFOPLIST_FILE") is True, TESTS + " must generate its Info.plist")
    scheme = schemes.get(APP)
    c.require(scheme == {"build": {"targets": {APP: "all", TESTS: ["test"]}}, "test": {"targets": [TESTS]}},
              "scheme %s is %r" % (APP, scheme))
    # release_ios.py reads target and scheme names at exactly two spaces; the scheme carries the app's name.
    c.require(APP in two_space_blocks(text, "targets") and TESTS in two_space_blocks(text, "targets"),
              "release_ios.py would not see the targets (names must sit at two spaces under targets:)")
    c.require(APP in two_space_blocks(text, "schemes"), "release_ios.py would not see the scheme " + APP)

    # Android's resources live in TripleShot/Res (one folder reference); any other non-Swift file under TripleShot/
    # (a stray temporary file, a copied Android file) would land in the bundle root.
    for rel, name in loose_resources():
        c.require(rel == "Family/minik-family-catalog.json",
                  "%s would be copied into the bundle root as %s (move it to TripleShot/Res or delete it)" % (rel, name))

    ignore = read_text(".gitignore")
    c.require(re.search(r"(?m)^!" + re.escape(FIREBASE_PLIST) + r"\s*$", ignore),
              ".gitignore does not allow " + FIREBASE_PLIST)
    listed = by_path.get(FIREBASE_PLIST)
    if os.path.isfile(path(FIREBASE_PLIST)):
        c.require(listed == {"path": FIREBASE_PLIST, "buildPhase": "resources"} or
                  FIREBASE_PLIST in str(settings.get("MINIK_FIREBASE_PLIST_PATH", "")),
                  FIREBASE_PLIST + " exists but the target does not bundle it")
        plist = plistlib.loads(read_bytes(FIREBASE_PLIST))
        c.require(plist.get("BUNDLE_ID") == BUNDLE_ID, "the Firebase plist is registered for %r" % plist.get("BUNDLE_ID"))
        c.require(plist.get("PROJECT_ID") == FIREBASE_PROJECT, "the Firebase plist belongs to %r" % plist.get("PROJECT_ID"))
        c.require(str(plist.get("DATABASE_URL", DATABASE_URL)).rstrip("/") == DATABASE_URL,
                  "the Firebase plist DATABASE_URL is not " + DATABASE_URL)
        firebase = "registered"
    else:
        c.require(listed is None, FIREBASE_PLIST + " is listed but missing (XcodeGen fails)")
        firebase = "not registered yet (online play off)"
    for folder in ("TripleShot", "Family"):
        for base, _, files in os.walk(path(folder)):
            for name in files:
                c.require(not name.startswith("GoogleService-Info"),
                          "%s/%s would be bundled; the registration lives at %s" % (base, name, FIREBASE_PLIST))
    return c.done("%s, %s, scheme %s; Firebase %s" % (APP, TESTS, APP, firebase))


# ---------------------------------------------------------------- CI and release scripts

def check_ci():
    c = Check("ci")
    compile_check = read_text(".github/workflows/ios-compile-check.yml")
    loop = re.search(r"for SCHEME in ([^;\n]+); do", compile_check)
    c.require(loop and APP in loop.group(1).split(), "ios-compile-check.yml does not compile " + APP)
    c.require(re.search(r"\b%s\) TESTS=%s ;;" % (APP, TESTS), compile_check), "ios-compile-check.yml does not map %s to %s" % (APP, TESTS))
    c.require('[ "$SCHEME" = "%s" ]' % APP in compile_check, "ios-compile-check.yml does not run " + TESTS)
    for name in ("ios-compile-check.yml", "testflight.yml"):
        workflow = load_yaml(".github/workflows/" + name)
        triggers = workflow.get("on", workflow.get(True))  # YAML 1.1 reads the key "on" as true
        if isinstance(triggers, dict):
            triggers = sorted(triggers)
        elif isinstance(triggers, str):
            triggers = [triggers]
        c.require(triggers == ["workflow_dispatch"], "%s must start only by hand (workflow_dispatch), not %r" % (name, triggers))

    tree = ast.parse(read_text("Scripts/appstore-register-bundle-ids.py"))
    values = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            try:
                values[node.targets[0].id] = ast.literal_eval(node.value)
            except (ValueError, TypeError, SyntaxError):
                pass  # not a literal (an expression the audit does not need)
    apps = [entry for entry in values.get("APPS", []) if entry[0] == BUNDLE_ID]
    c.require(len(apps) == 1, "appstore-register-bundle-ids.py APPS lists %s %d times" % (BUNDLE_ID, len(apps)))
    if apps:
        c.require(re.fullmatch(r"[A-Za-z0-9 ]+", apps[0][1]) and apps[0][2] is False,
                  "the App ID entry %r needs a plain name and no App Attest" % (apps[0],))
    c.require(values.get("SCHEME_BUNDLES", {}).get(APP) == BUNDLE_ID, "SCHEME_BUNDLES does not map %s to %s" % (APP, BUNDLE_ID))
    audit = read_text("Scripts/audit-release-configuration.ps1")
    folders = re.search(r"\$appCodeText = \(@\(([^)]*)\)", audit)
    c.require(folders and "'TripleShot'" in folders.group(1), "audit-release-configuration.ps1 does not scan TripleShot/")
    return c.done("compiled, tests compiled and run, manual starts, App Store Connect %s" % BUNDLE_ID)


# ---------------------------------------------------------------- icon

def check_icon(android):
    c = Check("icon")
    try:
        from PIL import Image, ImageChops, ImageStat
    except ImportError:
        c.require(False, "Pillow is missing")
        return c.done("")
    contents = json.loads(read_text(ICON_SET + "/Contents.json"))
    c.require(contents.get("images") == [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
              "AppIcon Contents.json is not one universal 1024x1024 entry")
    sets = []
    for folder in ("TripleShot", "Family"):
        for base, dirs, _ in os.walk(path(folder)):
            sets += [os.path.relpath(os.path.join(base, d), ROOT).replace(os.sep, "/") for d in dirs if d.endswith(".appiconset")]
    c.require(sets == [ICON_SET], "the target's app icon sets are %r" % sets)
    icon = Image.open(path(ICON_SET + "/AppIcon.png"))
    icon.load()
    c.require(icon.format == "PNG" and icon.size == (1024, 1024) and icon.mode == "RGB",
              "AppIcon.png is %s %s %s, expected an opaque RGB PNG of 1024 x 1024" % (icon.format, icon.size, icon.mode))
    master = os.path.join(android, "art", "store-ready", "launcher-source.png")
    if not c.require(os.path.isfile(master), "Android master not found: " + master):
        return c.done("")
    reference = Image.open(master).convert("RGB").resize((1024, 1024), Image.LANCZOS)
    if reference.tobytes() == icon.convert("RGB").tobytes():
        return c.done("1024 x 1024 RGB, the Android master scaled with Lanczos (identical)")
    mean = max(ImageStat.Stat(ImageChops.difference(reference, icon.convert("RGB"))).mean)
    c.require(mean <= 1.0, "AppIcon.png differs from the scaled Android master (mean difference %.2f of 255)" % mean)
    return c.done("1024 x 1024 RGB, the Android master scaled with Lanczos (mean difference %.2f of 255)" % mean)


# ---------------------------------------------------------------- privacy

def check_privacy():
    c = Check("privacy")
    manifest = plistlib.loads(read_bytes(PRIVACY))
    c.require(manifest.get("NSPrivacyTracking") is False, "NSPrivacyTracking must be false")
    c.require(manifest.get("NSPrivacyTrackingDomains") == [], "NSPrivacyTrackingDomains must be empty")
    reasons = {}
    for entry in manifest.get("NSPrivacyAccessedAPITypes", []):
        reasons[entry.get("NSPrivacyAccessedAPIType")] = entry.get("NSPrivacyAccessedAPITypeReasons")
    code = {rel: read_text(rel) for rel in swift_files("TripleShot", "Family")}
    joined = "\n".join(code.values())
    want = {}
    if re.search(r"\bUserDefaults\b", joined):
        want["NSPrivacyAccessedAPICategoryUserDefaults"] = ["CA92.1"]
    if BOOT_TIME_APIS.search(joined):
        want["NSPrivacyAccessedAPICategorySystemBootTime"] = ["35F9.1"]
    c.require(reasons == want, "accessed API reasons are %r; the app code needs %r" % (reasons, want))
    for rel, text in code.items():
        for number, line in enumerate(text.splitlines(), 1):
            for match in OTHER_REASON_APIS.finditer(line):
                where = " (in a comment; reword it)" if "//" in line[:match.start()] else ""
                c.require(False, "%s:%d names %s, a required-reason API outside the manifest%s" % (rel, number, match.group(1), where))
    collected = manifest.get("NSPrivacyCollectedDataTypes", [])
    # Online play: the anonymous Firebase uid and the 1-5 letter online nickname (a screen name: Apple's "User ID");
    # rooms, shots, scores, streaks and answers (gameplay content). The full player name stays on the device.
    c.require([e.get("NSPrivacyCollectedDataType") for e in collected] ==
              ["NSPrivacyCollectedDataTypeUserID", "NSPrivacyCollectedDataTypeGameplayContent"],
              "collected data types are not UserID and GameplayContent")
    for entry in collected:
        c.require(entry.get("NSPrivacyCollectedDataTypeLinked") is True and entry.get("NSPrivacyCollectedDataTypeTracking") is False and
                  entry.get("NSPrivacyCollectedDataTypePurposes") == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"],
                  "%s must be linked, not tracking, for app functionality" % entry.get("NSPrivacyCollectedDataType"))
    return c.done("no tracking; %s; UserID and GameplayContent for online play" %
                  ", ".join("%s %s" % (k.replace("NSPrivacyAccessedAPICategory", ""), "/".join(v)) for k, v in sorted(want.items())))


# ---------------------------------------------------------------- family

def check_family():
    c = Check("family")
    catalogue = json.loads(read_text("Family/minik-family-catalog.json"))
    entry = (catalogue.get("apps") or {}).get(CATALOG_KEY)
    if not c.require(isinstance(entry, dict), "the family catalogue has no %r entry" % CATALOG_KEY):
        return c.done("")
    c.require(entry.get("applicationId") == BUNDLE_ID, "catalogue entry %r is for %r" % (CATALOG_KEY, entry.get("applicationId")))
    art = entry.get("artAsset") or {}
    for language in ("en", "he"):
        name = os.path.splitext(os.path.basename(str(art.get(language, ""))))[0]
        c.require(name and os.path.isdir(path("Family/FamilyArt.xcassets/family-%s.imageset" % name)),
                  "family art for %s (%r) is not in Family/FamilyArt.xcassets" % (language, art.get(language)))
    return c.done("catalogue key %r = %s, art bundled" % (CATALOG_KEY, BUNDLE_ID))


# ---------------------------------------------------------------- resources

def check_resources(android):
    c = Check("resources")
    result = subprocess.run([sys.executable, "-B", path(SYNC), "--check", "--android", android], cwd=ROOT,
                            capture_output=True, text=True, encoding="utf-8", errors="replace")
    lines = [line for line in (result.stdout + result.stderr).splitlines() if line.strip()]
    c.require(result.returncode == 0, "%s --check exited %d" % (SYNC, result.returncode))
    for line in lines[:15]:
        if result.returncode:
            c.problems.append(line)
        else:
            c.note(line)
    if len(lines) > 15:
        c.note("... %d more line(s)" % (len(lines) - 15))
    return c.done("TripleShot/Res is up to date with the Android project")


# ---------------------------------------------------------------- Swift sources

def check_swift():
    c = Check("swift")
    files = swift_files("TripleShot", "Tests/" + TESTS)
    autocrlf = git("config", "--get", "core.autocrlf").strip().lower()
    attributes = text_attributes(files)
    c.require(attributes.get("TripleShot/Res/R.swift") == "unset", "git attributes are unreadable or TripleShot/Res is not -text")
    index = {}
    for line in git("ls-files", "--eol", "--", "TripleShot", "Tests/" + TESTS).splitlines():
        info, _, name = line.partition("\t")
        index[name] = info.split()[0] if info.split() else ""
    mains = []
    for rel in files:
        data = read_bytes(rel)
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError as error:
            c.require(False, "%s is not UTF-8 (%s)" % (rel, error))
            continue
        if rel.startswith("TripleShot/"):
            mains += [rel] * len(re.findall(r"(?m)^@main\b", text))
        for match in list(FORBIDDEN_CHARACTERS.finditer(text))[:3]:
            code, number = ord(match.group(0)), text.count("\n", 0, match.start()) + 1
            c.require(False, "%s:%d holds a raw U+%04X (write it as \\u{%X})" % (rel, number, code, code))
        # Committed bytes: git turns CRLF into LF on commit with core.autocrlf, except under "-text" attributes.
        if index.get(rel) in ("i/crlf", "i/mixed"):
            c.require(False, "%s is committed with CR line endings" % rel)
        elif b"\r" in data and (attributes.get(rel) == "unset" or autocrlf not in ("true", "input")):
            c.require(False, "%s has CR line endings and would be committed with them" % rel)
    c.require(mains == [APP_SHELL], "@main must appear once, in %s; found %r" % (APP_SHELL, mains))
    return c.done("%d files, one @main (%s)" % (len(files), APP_SHELL))


# ---------------------------------------------------------------- the owner's release script

def check_release(release):
    if not os.path.isfile(release):
        print("release: skipped (no release script at %s)" % release)
        return True
    c = Check("release")
    spec = importlib.util.spec_from_file_location("release_ios_readonly", release)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # its top level only defines constants and functions
    text = read_text("project.yml")
    sections = module.top_sections(text)
    targets, schemes = module.children(sections.get("targets")), module.children(sections.get("schemes"))
    c.require(APP in targets and TESTS in targets, "its parser does not find the targets %s and %s" % (APP, TESTS))
    c.require(APP in schemes, "its parser does not find the scheme " + APP)
    entries, refs = module.app_inputs(APP, text)
    roots = [root for root, _ in entries]
    for rel in ("TripleShot", "TripleShot/Res", "TripleShot/Res/R.swift", "Family", PRIVACY):
        c.require(rel in roots, "app_inputs(%s) lacks %s" % (APP, rel))
    samples = {APP_SHELL: True, "TripleShot/Res/strings/he.json": True, "TripleShot/Res/assets/question_banks/en/arithmetic.xml": True,
               ICON_SET + "/AppIcon.png": True, "Family/FamilyMessages.swift": True, PRIVACY: True,
               "Tests/%s/IntegrationTests.swift" % TESTS: False, SYNC: False, "Splash/SplashApp.swift": False}
    for rel, used in samples.items():
        c.require(module.uses(entries, refs, rel) == used, "uses(%s) is %s, expected %s" % (rel, not used, used))
    c.require("%s: [test]" % TESTS in module.project_part(APP, text), "project_part(%s) lacks its scheme" % APP)
    # Its tables live outside this repository: print the entries it still needs.
    if APP not in module.APPS:
        c.note("release_ios.py APPS: add '%s'" % APP)
    if APP in module.WAITING:
        c.note("release_ios.py WAITING holds %s (skipped until its App Store Connect record exists)" % APP)
    elif APP not in module.APPS:
        c.note("release_ios.py WAITING: add '%s' until its App Store Connect record exists" % APP)
    if module.TEST_TARGETS.get(TESTS) != [APP]:
        c.note("release_ios.py TEST_TARGETS: add '%s': ['%s'] (else a test-compile failure blocks a phantom app)" % (TESTS, APP))
    if APP in getattr(module, "OWN_FOLDERS", {}):
        c.require(False, "release_ios.py OWN_FOLDERS must not list %s (it is a project.yml app)" % APP)
    return c.done("its parser sees %s, %s and the scheme; inputs %s" % (APP, TESTS, ", ".join(roots)))


def default_android():
    spec = importlib.util.spec_from_file_location("tripleshot_sync_readonly", path(SYNC))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # main() runs only as a script
    return str(module.DEFAULT_ANDROID)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--android", default=None, help="Android TripleShotGame root (default: the sync script's)")
    parser.add_argument("--release", default=RELEASE, help="the owner's release_ios.py (checked only if present)")
    parser.add_argument("--skip-resources", action="store_true", help="skip the TripleShot/Res comparison (slow)")
    args = parser.parse_args()
    android = args.android or default_android()
    results = [check_project(android), check_ci(), check_icon(android), check_privacy(), check_family()]
    if args.skip_resources:
        print("resources: skipped")
    else:
        results.append(check_resources(android))
    results += [check_swift(), check_release(args.release)]
    print("RESULT: " + ("PASS" if all(results) else "FAIL"))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
