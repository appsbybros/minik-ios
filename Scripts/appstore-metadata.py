"""Fills in the App Store page of the Minik iOS apps in App Store Connect: the store texts, the build and
the screenshots. It never submits anything for review: the owner does that by hand in App Store Connect.

    python3 Scripts/appstore-metadata.py --apps MinikPlus,MinikMathPlus --dry-run
    python3 Scripts/appstore-metadata.py --apps all --attach-build --screenshots build/AppStore-screenshots
    python3 Scripts/appstore-metadata.py --check-only --apps all      (offline: checks the texts, needs no key)

For each app (Xcode scheme) it
- finds the App Store Connect app by bundle ID (SCHEME_BUNDLES in Scripts/appstore-register-bundle-ids.py);
- finds the editable App Store version for the app's version in project.yml (Minik Maze: Maze/game/
  export_presets.cfg). A new app record comes with an editable "1.0"; that one is renamed. Otherwise the version is
  created. A version that is in review, approved or live is left alone;
- sets the version texts per language (description, keywords, promotional text, what's new, support and
  marketing URLs) and the app information (name, subtitle, privacy policy URL), adding a language that is missing;
- with --attach-build, picks the newest processed (VALID) build of that version;
- with --screenshots <folder>, replaces each language's screenshots per device slot, in file-name order. The folder
  is the "AppStore-screenshots" artifact of the "App Store screenshots" workflow:
  <folder>/<Scheme>/<App Store locale>/<iphone-6.9|ipad-13|...>/NN-scene.png.

The texts are appstore/metadata/<Scheme>/<App Store locale>/<field>.txt (FIELDS below). A missing or empty file
leaves that field as it is in App Store Connect.

--dry-run reads App Store Connect and prints every change without making one. call() refuses every review,
submission and release endpoint, and every write outside the short list of store-page edits this script makes.

Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY (the .p8 text) in the environment and PyJWT with
cryptography. Prints no secret values.
"""
import argparse
import ast
import hashlib
import json
import os
import re
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API = "https://api.appstoreconnect.apple.com/v1"
METADATA_ROOT = ROOT / "appstore" / "metadata"
REGISTER_SCRIPT = ROOT / "Scripts" / "appstore-register-bundle-ids.py"

# ---- Store texts --------------------------------------------------------------------------------------------------

# file name -> (App Store Connect resource, attribute, limit, unit). Limits are App Store Connect's.
FIELDS = {
    "name.txt": ("appInfo", "name", 30, "characters"),
    "subtitle.txt": ("appInfo", "subtitle", 30, "characters"),
    "privacy_url.txt": ("appInfo", "privacyPolicyUrl", 255, "characters"),
    "description.txt": ("version", "description", 4000, "characters"),
    "keywords.txt": ("version", "keywords", 100, "bytes"),
    "promotional_text.txt": ("version", "promotionalText", 170, "characters"),
    "whats_new.txt": ("version", "whatsNew", 4000, "characters"),
    "support_url.txt": ("version", "supportUrl", 255, "characters"),
    "marketing_url.txt": ("version", "marketingUrl", 255, "characters"),
}
URL_FIELDS = {"privacy_url.txt", "support_url.txt", "marketing_url.txt"}
SINGLE_LINE_FIELDS = {"name.txt", "subtitle.txt", "keywords.txt"} | URL_FIELDS
# App Store Connect's language codes (the ones the Minik apps use, and the rest of Apple's list).
STORE_LOCALES = {
    "ar-SA", "ca", "cs", "da", "de-DE", "el", "en-AU", "en-CA", "en-GB", "en-US", "es-ES", "es-MX", "fi", "fr-CA",
    "fr-FR", "he", "hi", "hr", "hu", "id", "it", "ja", "ko", "ms", "nl-NL", "no", "pl", "pt-BR", "pt-PT", "ro", "ru",
    "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
}


def field_length(text, unit):
    return len(text.encode("utf-8")) if unit == "bytes" else len(text)


def check_field(file_name, text):
    """The problems of one field's text (empty list = fine)."""
    _, _, limit, unit = FIELDS[file_name]
    problems = []
    length = field_length(text, unit)
    if length > limit:
        problems.append(f"{length} {unit}, over App Store Connect's limit of {limit}")
    if file_name in SINGLE_LINE_FIELDS and "\n" in text:
        problems.append("must be a single line")
    if file_name in URL_FIELDS and not re.fullmatch(r"https?://[^\s<>\"]+", text):
        problems.append(f"not a web address: {text!r}")
    if file_name == "keywords.txt":
        words = text.split(",")
        if any(not word.strip() for word in words):
            problems.append("has an empty keyword (two commas in a row, or a comma at an end)")
    if file_name == "name.txt" and len(text) < 2:
        problems.append("an app name needs at least 2 characters")
    if "\ufffd" in text:
        problems.append("contains a replacement character (broken encoding)")
    return problems


def read_text(path):
    text = path.read_bytes().decode("utf-8-sig")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return "\n".join(line.rstrip() for line in text.split("\n")).strip()


def read_metadata(app_dir):
    """({locale: {file name: text}}, problems, notes) for appstore/metadata/<Scheme>."""
    locales, problems, notes = {}, [], []
    if not app_dir.is_dir():
        return locales, problems, notes
    for folder in sorted(path for path in app_dir.iterdir() if path.is_dir()):
        locale = folder.name
        if locale not in STORE_LOCALES:
            problems.append(f"{locale}: not an App Store Connect language code")
            continue
        values = {}
        for path in sorted(folder.iterdir()):
            if path.name not in FIELDS:
                notes.append(f"{locale}/{path.name}: not a known field file, ignored")
                continue
            text = read_text(path)
            if not text:
                continue
            for problem in check_field(path.name, text):
                problems.append(f"{locale}/{path.name}: {problem}")
            values[path.name] = text
        if values:
            locales[locale] = values
    return locales, problems, notes


# ---- Apps and versions --------------------------------------------------------------------------------------------

def scheme_bundles(source=None):
    """SCHEME_BUNDLES from Scripts/appstore-register-bundle-ids.py, read without importing it."""
    tree = ast.parse(source if source is not None else REGISTER_SCRIPT.read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(getattr(t, "id", None) == "SCHEME_BUNDLES" for t in node.targets):
            return ast.literal_eval(node.value)
    raise SystemExit("SCHEME_BUNDLES not found in Scripts/appstore-register-bundle-ids.py")


def yaml_children(lines, indent):
    """{key: lines} of the mapping keys at exactly this indent."""
    blocks, key = {}, None
    for line in lines:
        match = re.match(r"^( *)([A-Za-z0-9_.-]+):", line)
        if match and len(match.group(1)) == indent:
            key = match.group(2)
            blocks[key] = []
        elif key and (not line.strip() or line.startswith(" " * (indent + 1)) or line.lstrip().startswith("#")):
            blocks[key].append(line)
        elif match and len(match.group(1)) < indent:
            key = None
    return blocks


def setting(lines, name):
    for line in lines:
        match = re.match(r'^\s+%s:\s*"?([^"#\s]+)"?' % re.escape(name), line)
        if match:
            return match.group(1)
    return None


def project_settings(project_text, name):
    """{target: value} of one build setting in project.yml: the target's own value, else its template's, else the
    project-wide one."""
    lines = project_text.splitlines()
    top = yaml_children(lines, 0)
    base = setting(top.get("settings", []), name)
    templates = yaml_children(top.get("targetTemplates", []), 2)
    values = {}
    for target, block in yaml_children(top.get("targets", []), 2).items():
        value = setting(block, name)
        if value is None:
            used = re.search(r"^\s+templates:\s*\[([^\]]*)\]", "\n".join(block), re.M)
            for template in (used.group(1).split(",") if used else []):
                value = value or setting(templates.get(template.strip(), []), name)
        values[target] = value or base
    return values


def maze_version(presets_text):
    match = re.search(r'^application/short_version="([^"]+)"', presets_text, re.M)
    return match.group(1) if match else None


def app_versions():
    """{scheme: marketing version} from project.yml and, for Minik Maze, Maze/game/export_presets.cfg."""
    versions = project_settings((ROOT / "project.yml").read_text(encoding="utf-8"), "MINIK_MARKETING_VERSION")
    presets = ROOT / "Maze" / "game" / "export_presets.cfg"
    if presets.is_file():
        versions["MinikMaze"] = maze_version(presets.read_text(encoding="utf-8"))
    return versions


# ---- Screenshots --------------------------------------------------------------------------------------------------

# Folder names of the screenshot artifact (and common alternatives) -> App Store Connect screenshotDisplayType.
# The 6.9-inch iPhone slot is APP_IPHONE_67 in the API; the 13-inch iPad slot is APP_IPAD_PRO_3GEN_129.
SLOT_TYPES = {
    "iphone-6.9": "APP_IPHONE_67",
    "iphone-6.7": "APP_IPHONE_67",
    "iphone-6.5": "APP_IPHONE_65",
    "iphone-6.1": "APP_IPHONE_61",
    "iphone-5.8": "APP_IPHONE_58",
    "iphone-5.5": "APP_IPHONE_55",
    "ipad-13": "APP_IPAD_PRO_3GEN_129",
    "ipad-12.9": "APP_IPAD_PRO_3GEN_129",
    "ipad-11": "APP_IPAD_PRO_3GEN_11",
}
# Portrait pixel sizes App Store Connect accepts per slot (landscape is the same turned).
TYPE_SIZES = {
    "APP_IPHONE_67": [(1320, 2868), (1290, 2796), (1260, 2736)],
    "APP_IPHONE_65": [(1284, 2778), (1242, 2688)],
    "APP_IPHONE_61": [(1179, 2556), (1170, 2532), (1125, 2436), (1080, 2340)],
    "APP_IPHONE_58": [(1170, 2532), (1125, 2436), (1080, 2340)],
    "APP_IPHONE_55": [(1242, 2208)],
    "APP_IPAD_PRO_3GEN_129": [(2064, 2752), (2048, 2732)],
    "APP_IPAD_PRO_3GEN_11": [(1668, 2420), (1668, 2388), (1640, 2360), (1488, 2266)],
}
# App Store Connect needs one iPhone slot (6.9" or 6.5") and, for an app that runs on iPad, the 13" iPad slot;
# it scales these for the smaller devices.
REQUIRED_SLOTS = [("iPhone 6.9\" or 6.5\"", {"APP_IPHONE_67", "APP_IPHONE_65"}),
                  ("iPad 13\"", {"APP_IPAD_PRO_3GEN_129", "APP_IPAD_PRO_129"})]
IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg")


def display_type(folder_name):
    """The screenshotDisplayType a slot folder holds, or None. A display type name itself is accepted too."""
    if folder_name in SLOT_TYPES:
        return SLOT_TYPES[folder_name]
    if folder_name in TYPE_SIZES:
        return folder_name
    return SLOT_TYPES.get(folder_name.lower())


def image_size(path):
    """(width, height) of a PNG or JPEG file, read from its header; None if it is neither."""
    with open(path, "rb") as handle:
        head = handle.read(26)
        if head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR":
            return struct.unpack(">II", head[16:24])
        if head[:2] != b"\xff\xd8":
            return None
        handle.seek(2)
        while True:
            marker = handle.read(2)
            if len(marker) < 2 or marker[0] != 0xFF:
                return None
            while marker[1] == 0xFF:
                marker = marker[:1] + handle.read(1)
            code = marker[1]
            if code in (0xD8, 0x01) or 0xD0 <= code <= 0xD7:
                continue
            length_bytes = handle.read(2)
            if len(length_bytes) < 2:
                return None
            length = struct.unpack(">H", length_bytes)[0]
            if code in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                height, width = struct.unpack(">xHH", handle.read(5))
                return width, height
            handle.seek(length - 2, 1)


def size_fits(kind, size):
    return any(size in (accepted, accepted[::-1]) for accepted in TYPE_SIZES.get(kind, []))


def collect_screenshots(root, scheme):
    """({locale: {display type: [files in upload order]}}, notes about what was left out)."""
    found, notes = {}, []
    app_dir = Path(root) / scheme
    if not app_dir.is_dir():
        return found, notes
    for locale_dir in sorted(path for path in app_dir.iterdir() if path.is_dir()):
        locale = locale_dir.name
        if locale not in STORE_LOCALES:
            notes.append(f"{scheme}/{locale}: not an App Store Connect language code, skipped")
            continue
        for slot_dir in sorted(path for path in locale_dir.iterdir() if path.is_dir()):
            kind = display_type(slot_dir.name)
            label = f"{scheme}/{locale}/{slot_dir.name}"
            if kind is None:
                notes.append(f"{label}: unknown device folder, skipped")
                continue
            files = []
            for path in sorted(slot_dir.iterdir()):
                if not path.is_file():
                    continue
                if path.suffix.lower() not in IMAGE_SUFFIXES:
                    notes.append(f"{label}/{path.name}: not a PNG or JPEG, skipped")
                    continue
                size = image_size(path)
                if size is None or not size_fits(kind, size):
                    shown = "unreadable" if size is None else f"{size[0]}x{size[1]}"
                    notes.append(f"{label}/{path.name}: {shown} does not fit {kind}, skipped")
                    continue
                files.append(path)
            if not files:
                notes.append(f"{label}: no usable screenshots")
                continue
            if len(files) > 10:
                notes.append(f"{label}: {len(files)} screenshots; App Store Connect takes 10, the rest are left out")
                files = files[:10]
            found.setdefault(locale, {}).setdefault(kind, []).extend(files)
    for slots in found.values():
        for kind in slots:
            slots[kind] = slots[kind][:10]
    return found, notes


def missing_slots(present_types, ipad=True):
    """Labels of the required slots none of present_types fills."""
    missing = []
    for label, kinds in REQUIRED_SLOTS:
        if not ipad and "iPad" in label:
            continue
        if not kinds & set(present_types):
            missing.append(label)
    return missing


def md5(path):
    digest = hashlib.md5()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


# ---- The App Store Connect API, with the no-submit guard -------------------------------------------------------------

class Refused(Exception):
    """A request this script must never send."""


# Any path naming a review submission, a submission or a release request is refused, also for reading.
FORBIDDEN_PATH = re.compile(r"submi|releaseRequest|phasedRelease|reviewDetail|customerReview", re.I)
# The only writes this script makes: (method, path, attributes the body may set; None = no attributes).
ALLOWED_WRITES = [
    ("POST", r"/appStoreVersions", {"platform", "versionString"}),
    ("PATCH", r"/appStoreVersions/[\w-]+", {"versionString"}),
    ("PATCH", r"/appStoreVersions/[\w-]+/relationships/build", None),
    ("POST", r"/appStoreVersionLocalizations", {"locale", "description", "keywords", "promotionalText",
                                                "whatsNew", "supportUrl", "marketingUrl"}),
    ("PATCH", r"/appStoreVersionLocalizations/[\w-]+", {"description", "keywords", "promotionalText",
                                                        "whatsNew", "supportUrl", "marketingUrl"}),
    ("POST", r"/appInfoLocalizations", {"locale", "name", "subtitle", "privacyPolicyUrl"}),
    ("PATCH", r"/appInfoLocalizations/[\w-]+", {"name", "subtitle", "privacyPolicyUrl"}),
    ("POST", r"/appScreenshotSets", {"screenshotDisplayType"}),
    ("PATCH", r"/appScreenshotSets/[\w-]+/relationships/appScreenshots", None),
    ("POST", r"/appScreenshots", {"fileName", "fileSize"}),
    ("PATCH", r"/appScreenshots/[\w-]+", {"uploaded", "sourceFileChecksum"}),
    ("DELETE", r"/appScreenshots/[\w-]+", None),
]


def check_request(method, path, body=None):
    """Raises Refused unless this request is a read or one of the store-page edits in ALLOWED_WRITES."""
    method = method.upper()
    bare = path.split("?", 1)[0]
    if not bare.startswith("/") or "//" in bare or ".." in bare or "://" in path:
        raise Refused(f"{method} {path}: not a plain App Store Connect API path")
    if FORBIDDEN_PATH.search(path):
        raise Refused(f"{method} {path}: this script never touches review submissions or releases")
    if body is not None and re.search(r'"(submitted|submit)"\s*:', json.dumps(body), re.I):
        raise Refused(f"{method} {path}: the body asks to submit")
    if method == "GET":
        return
    for allowed_method, pattern, attributes in ALLOWED_WRITES:
        if method == allowed_method and re.fullmatch(pattern, bare):
            data = (body or {}).get("data")
            sent = set(data.get("attributes", {})) if isinstance(data, dict) else set()
            extra = sent - (attributes or set())
            if extra:
                raise Refused(f"{method} {path}: may not set {', '.join(sorted(extra))}")
            return
    raise Refused(f"{method} {path}: not one of the store-page edits this script may make")


def token():
    import jwt  # PyJWT; imported here so the offline checks and tests need no packages.
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        os.environ["ASC_PRIVATE_KEY"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def http_call(method, path, body=None):
    """Sends one App Store Connect API request (the style of appstore-register-bundle-ids.py's call()).
    Busy or failing Apple servers (429/5xx) get up to four more tries."""
    for attempt in range(5):
        request = urllib.request.Request(
            API + path,
            method=method,
            data=None if body is None else json.dumps(body).encode("utf-8"),
            headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.status, json.loads(response.read() or b"{}")
        except urllib.error.HTTPError as error:
            payload = error.read()
            if error.code in (429, 500, 502, 503, 504) and attempt < 4:
                time.sleep(2 ** attempt)
                continue
            try:
                return error.code, json.loads(payload or b"{}")
            except json.JSONDecodeError:
                return error.code, {"raw": payload.decode("utf-8", "replace")}
        except (urllib.error.URLError, TimeoutError) as error:
            if attempt < 4:
                time.sleep(2 ** attempt)
                continue
            return 0, {"errors": [{"detail": f"network error: {error}"}]}


def errors_text(payload):
    items = (payload or {}).get("errors", [])
    return "; ".join(item.get("detail") or item.get("title", "") for item in items) or json.dumps(payload)[:300]


class Asc:
    """The API with the guard. In a dry run every write is printed and not sent."""

    def __init__(self, dry_run, transport=None):
        self.dry_run = dry_run
        self.transport = transport or http_call

    def call(self, method, path, body=None):
        check_request(method, path, body)
        if self.dry_run and method.upper() != "GET":
            raise Refused(f"{method} {path}: a dry run sends no changes")
        return self.transport(method.upper(), path, body)

    def get(self, path):
        return self.call("GET", path)

    def get_all(self, path):
        """(status, every item of a list, following its next links)."""
        items = []
        while path:
            status, payload = self.get(path)
            if status != 200:
                return status, payload
            items += payload.get("data", [])
            next_link = (payload.get("links") or {}).get("next")
            if next_link and not next_link.startswith(API + "/"):
                raise Refused(f"next link outside the API: {next_link}")
            path = next_link[len(API):] if next_link else None
        return 200, items

    def write(self, report, what, method, path, body=None, expect=(200, 201, 204)):
        """Makes one change, or in a dry run prints it. Returns the payload (None in a dry run)."""
        check_request(method, path, body)
        if self.dry_run:
            report.done.append("would " + what)
            return None
        status, payload = self.call(method, path, body)
        if status not in expect:
            report.errors.append(f"{what}: HTTP {status}: {errors_text(payload)}")
            return False
        report.done.append(what)
        return payload or {}


def put_chunk(operation, data):
    """Sends one upload operation to Apple's asset upload URL (not the API)."""
    headers = {item["name"]: item["value"] for item in operation.get("requestHeaders") or []}
    detail = ""
    for attempt in range(5):
        request = urllib.request.Request(operation["url"], method=operation["method"], data=data, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                response.read()
                return None
        except urllib.error.HTTPError as error:
            detail = f"HTTP {error.code}: {error.read()[:500].decode('utf-8', 'replace')}"
            if error.code not in (429, 500, 502, 503, 504):
                return detail
        except (urllib.error.URLError, TimeoutError) as error:
            detail = f"network error: {error}"
        if attempt < 4:
            time.sleep(2 ** attempt)
    return detail


# ---- Filling in one app -----------------------------------------------------------------------------------------------

EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
RELEASED = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_VERSION", "REMOVED_FROM_SALE",
            "DEVELOPER_REMOVED_FROM_SALE", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE",
            "PROCESSING_FOR_APP_STORE", "PROCESSING_FOR_DISTRIBUTION"}
NEW = "(new)"


class Report:
    def __init__(self, scheme):
        self.scheme = scheme
        self.done, self.skipped, self.errors, self.missing = [], [], [], []

    def print(self):
        print(f"\n===== {self.scheme} =====")
        for title, items in (("Set", self.done), ("Skipped", self.skipped),
                             ("Missing screenshot sizes", self.missing), ("ERRORS", self.errors)):
            if items:
                print(f"{title}:")
                for item in items:
                    print(f"  - {item}")
        if not (self.done or self.skipped or self.errors or self.missing):
            print("Nothing to do.")


def state_of(item):
    attributes = item.get("attributes", {})
    return attributes.get("appVersionState") or attributes.get("state") or attributes.get("appStoreState") or "?"


def shown(text):
    one_line = text.replace("\n", " / ")
    return one_line if len(one_line) <= 90 else one_line[:87] + "..."


def changed_attributes(wanted, current):
    return {key: value for key, value in wanted.items()
            if (current.get(key) or "").replace("\r\n", "\n").strip() != value}


def describe(attributes):
    return "; ".join(f"{key} = {shown(value)} ({len(value)} chars)" for key, value in attributes.items())


class AppFiller:
    def __init__(self, asc, scheme, bundle_id, version, metadata, screenshots, attach_build, ipad=True):
        self.asc, self.scheme, self.bundle_id, self.version = asc, scheme, bundle_id, version
        self.metadata, self.screenshots, self.attach_build, self.ipad = metadata, screenshots, attach_build, ipad
        self.report = Report(scheme)

    def run(self):
        try:
            self._run()
        except Refused as error:
            self.report.errors.append(f"refused: {error}")
        return self.report

    def _run(self):
        report = self.report
        status, apps = self.asc.get_all("/apps?" + urllib.parse.urlencode({"filter[bundleId]": self.bundle_id}))
        if status != 200:
            report.errors.append(f"could not look up {self.bundle_id} (HTTP {status}): {errors_text(apps)}")
            return
        apps = [item for item in apps if item.get("attributes", {}).get("bundleId") == self.bundle_id]
        if not apps:
            report.skipped.append(f"no App Store Connect app record for {self.bundle_id}; create it first")
            return
        app_id = apps[0]["id"]
        primary = apps[0].get("attributes", {}).get("primaryLocale")
        print(f"{self.scheme}: app {app_id} ({self.bundle_id}), primary language {primary}, version {self.version}")

        version_id, released = self._version(app_id)
        if version_id is None:
            return
        self._app_info(app_id)
        localizations = self._version_texts(version_id, released)
        if self.attach_build:
            self._build(app_id, version_id)
        self._screenshots(localizations)

    # The App Store version

    def _version(self, app_id):
        report = self.report
        query = urllib.parse.urlencode({"filter[platform]": "IOS", "limit": 200})
        status, versions = self.asc.get_all(f"/apps/{app_id}/appStoreVersions?{query}")
        if status != 200:
            report.errors.append(f"could not read the App Store versions (HTTP {status}): {errors_text(versions)}")
            return None, False
        released = any(state_of(item) in RELEASED for item in versions)
        same = [item for item in versions if item.get("attributes", {}).get("versionString") == self.version]
        if same:
            state = state_of(same[0])
            if state not in EDITABLE:
                report.skipped.append(f"version {self.version} is {state}, so it cannot be edited; nothing changed")
                return None, released
            report.skipped.append(f"version {self.version} exists ({state})")
            return same[0]["id"], released
        editable = [item for item in versions if state_of(item) in EDITABLE]
        if editable:
            other = editable[0]
            old = other.get("attributes", {}).get("versionString")
            result = self.asc.write(report, f"rename the editable version {old} to {self.version}", "PATCH",
                                    f"/appStoreVersions/{other['id']}", {"data": {
                                        "type": "appStoreVersions", "id": other["id"],
                                        "attributes": {"versionString": self.version}}})
            return (None if result is False else other["id"]), released
        result = self.asc.write(report, f"create version {self.version}", "POST", "/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": self.version},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}, expect=(201,))
        if result is False:
            return None, released
        return (result["data"]["id"] if result else NEW), released

    # Name, subtitle and privacy policy URL (app information)

    def _app_info(self, app_id):
        report = self.report
        wanted = {locale: {FIELDS[name][1]: text for name, text in values.items() if FIELDS[name][0] == "appInfo"}
                  for locale, values in self.metadata.items()}
        wanted = {locale: values for locale, values in wanted.items() if values}
        if not wanted:
            return
        status, infos = self.asc.get_all(f"/apps/{app_id}/appInfos")
        if status != 200:
            report.errors.append(f"could not read the app information (HTTP {status}): {errors_text(infos)}")
            return
        editable = [item for item in infos if state_of(item) in EDITABLE]
        if not editable:
            states = ", ".join(state_of(item) for item in infos) or "none"
            report.skipped.append(f"name/subtitle/privacy URL: no editable app information (states: {states})")
            return
        info_id = editable[0]["id"]
        status, existing = self.asc.get_all(f"/appInfos/{info_id}/appInfoLocalizations?limit=200")
        if status != 200:
            report.errors.append(f"could not read the app information languages (HTTP {status}): "
                                 f"{errors_text(existing)}")
            return
        by_locale = {item["attributes"]["locale"]: item for item in existing}
        for locale, attributes in wanted.items():
            current = by_locale.get(locale)
            if current is None:
                if "name" not in attributes:
                    report.skipped.append(f"{locale}: app information not added (a new language needs name.txt)")
                    continue
                self.asc.write(report, f"{locale}: add app information: {describe(attributes)}", "POST",
                               "/appInfoLocalizations", {"data": {
                                   "type": "appInfoLocalizations", "attributes": {"locale": locale, **attributes},
                                   "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info_id}}}}},
                               expect=(201,))
                continue
            changes = changed_attributes(attributes, current.get("attributes", {}))
            if not changes:
                report.skipped.append(f"{locale}: {', '.join(attributes)} already up to date")
                continue
            self.asc.write(report, f"{locale}: {describe(changes)}", "PATCH",
                           f"/appInfoLocalizations/{current['id']}", {"data": {
                               "type": "appInfoLocalizations", "id": current["id"], "attributes": changes}})

    # Description, keywords, promotional text, what's new and URLs (the version's languages)

    def _version_texts(self, version_id, released):
        """Returns {locale: localization id (or NEW)} for the screenshots."""
        report = self.report
        existing = []
        if version_id != NEW:
            status, existing = self.asc.get_all(f"/appStoreVersions/{version_id}/appStoreVersionLocalizations"
                                                "?limit=200")
            if status != 200:
                report.errors.append(f"could not read the version's languages (HTTP {status}): "
                                     f"{errors_text(existing)}")
                return {}
        by_locale = {item["attributes"]["locale"]: item for item in existing}
        ids = {locale: item["id"] for locale, item in by_locale.items()}
        for locale in sorted(set(by_locale) - set(self.metadata)):
            report.skipped.append(f"{locale}: in App Store Connect but has no texts in appstore/metadata; left as is")
        for locale, values in self.metadata.items():
            attributes = {FIELDS[name][1]: text for name, text in values.items() if FIELDS[name][0] == "version"}
            if "whatsNew" in attributes and not released:
                del attributes["whatsNew"]
                report.skipped.append(f"{locale}: what's new not set: the first version of an app has none")
            if not attributes:
                continue
            current = by_locale.get(locale)
            if current is None:
                what = f"{locale}: add the language: {describe(attributes)}"
                if version_id == NEW:
                    report.done.append("would " + what)
                    ids[locale] = NEW
                    continue
                result = self.asc.write(report, what, "POST", "/appStoreVersionLocalizations", {"data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {"locale": locale, **attributes},
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}},
                    expect=(201,))
                if result:
                    ids[locale] = result["data"]["id"]
                elif result is None:
                    ids[locale] = NEW
                continue
            changes = changed_attributes(attributes, current.get("attributes", {}))
            if not changes:
                report.skipped.append(f"{locale}: {', '.join(attributes)} already up to date")
                continue
            result = self._patch_localization(locale, current["id"], changes)
            if result is False and "whatsNew" in changes:
                # Apple refuses what's new where the version cannot have one; the rest still goes in.
                report.errors.pop()
                rest = {key: value for key, value in changes.items() if key != "whatsNew"}
                report.skipped.append(f"{locale}: what's new refused by App Store Connect, sent the rest")
                if rest:
                    self._patch_localization(locale, current["id"], rest)
        return ids

    def _patch_localization(self, locale, localization_id, changes):
        return self.asc.write(self.report, f"{locale}: {describe(changes)}", "PATCH",
                              f"/appStoreVersionLocalizations/{localization_id}", {"data": {
                                  "type": "appStoreVersionLocalizations", "id": localization_id,
                                  "attributes": changes}})

    # The build

    def _build(self, app_id, version_id):
        report = self.report
        query = urllib.parse.urlencode({"filter[app]": app_id, "filter[preReleaseVersion.version]": self.version,
                                        "filter[processingState]": "VALID", "filter[expired]": "false",
                                        "sort": "-uploadedDate", "limit": 1})
        status, payload = self.asc.get(f"/builds?{query}")
        if status != 200:
            report.errors.append(f"could not read the builds (HTTP {status}): {errors_text(payload)}")
            return
        builds = payload.get("data", [])
        if not builds:
            report.skipped.append(f"build: no processed (VALID) build of version {self.version} yet")
            return
        build = builds[0]
        number = build.get("attributes", {}).get("version")
        if version_id != NEW:
            status, current = self.asc.get(f"/appStoreVersions/{version_id}/build")
            if status == 200 and (current.get("data") or {}).get("id") == build["id"]:
                report.skipped.append(f"build {self.version} ({number}) is already the version's build")
                return
        if version_id == NEW:
            report.done.append(f"would attach build {self.version} ({number})")
            return
        self.asc.write(report, f"attach build {self.version} ({number})", "PATCH",
                       f"/appStoreVersions/{version_id}/relationships/build",
                       {"data": {"type": "builds", "id": build["id"]}})

    # Screenshots

    def _screenshots(self, localizations):
        """Uploads the given screenshots; without any, only reads which slots App Store Connect already has."""
        report = self.report
        given = self.screenshots or {}
        if self.screenshots is None:
            report.skipped.append("screenshots: none given (no screenshots run); only checked what is there")
        present = {}
        for locale in sorted(set(given) | set(localizations)):
            slots = given.get(locale, {})
            localization_id = localizations.get(locale)
            if localization_id is None:
                if slots:
                    report.skipped.append(f"{locale}: screenshots not uploaded: the language is neither in App "
                                          "Store Connect nor in appstore/metadata")
                continue
            existing_sets = {}
            if localization_id != NEW:
                status, sets = self.asc.get_all(f"/appStoreVersionLocalizations/{localization_id}/appScreenshotSets"
                                                "?limit=50")
                if status != 200:
                    report.errors.append(f"{locale}: could not read the screenshot sets (HTTP {status}): "
                                         f"{errors_text(sets)}")
                    continue
                existing_sets = {item["attributes"]["screenshotDisplayType"]: item["id"] for item in sets}
            filled = set(slots)
            for kind, set_id in existing_sets.items():
                if kind not in slots:
                    status, shots = self.asc.get_all(f"/appScreenshotSets/{set_id}/appScreenshots?limit=50")
                    if status == 200 and shots:
                        filled.add(kind)
                        report.skipped.append(f"{locale} {kind}: no new files, kept its {len(shots)} screenshots")
            for kind, files in slots.items():
                self._screenshot_set(locale, localization_id, kind, existing_sets.get(kind), files)
            present[locale] = filled
        for locale in sorted(set(present) | set(self.metadata)):
            for label in missing_slots(present.get(locale, set()), self.ipad):
                report.missing.append(f"{locale}: {label}")

    def _screenshot_set(self, locale, localization_id, kind, set_id, files):
        report = self.report
        label = f"{locale} {kind}"
        names = ", ".join(path.name for path in files)
        if localization_id == NEW:
            report.done.append(f"would upload {len(files)} screenshots to {label}: {names}")
            return
        existing = []
        if set_id:
            status, existing = self.asc.get_all(f"/appScreenshotSets/{set_id}/appScreenshots?limit=50")
            if status != 200:
                report.errors.append(f"{label}: could not read its screenshots (HTTP {status}): "
                                     f"{errors_text(existing)}")
                return
            current = [item.get("attributes", {}).get("sourceFileChecksum") for item in existing]
            states = [((item.get("attributes", {}).get("assetDeliveryState") or {}).get("state")) for item in existing]
            if current == [md5(path) for path in files] and all(state == "COMPLETE" for state in states):
                report.skipped.append(f"{label}: the same {len(files)} screenshots are already there")
                return
        else:
            result = self.asc.write(report, f"{label}: create the screenshot set", "POST", "/appScreenshotSets", {
                "data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": kind},
                         "relationships": {"appStoreVersionLocalization": {"data": {
                             "type": "appStoreVersionLocalizations", "id": localization_id}}}}}, expect=(201,))
            if result is False:
                return
            set_id = result["data"]["id"] if result else None
        for item in existing:
            if self.asc.write(report, f"{label}: delete old screenshot {item.get('attributes', {}).get('fileName')}",
                              "DELETE", f"/appScreenshots/{item['id']}", expect=(204,)) is False:
                return
        if self.asc.dry_run:
            report.done.append(f"would upload {len(files)} screenshots to {label}: {names}")
            return
        uploaded = []
        for path in files:
            screenshot_id = self._upload(label, set_id, path)
            if screenshot_id is None:
                return
            uploaded.append((path, screenshot_id))
        self.asc.write(report, f"{label}: put {len(uploaded)} screenshots in file-name order", "PATCH",
                       f"/appScreenshotSets/{set_id}/relationships/appScreenshots",
                       {"data": [{"type": "appScreenshots", "id": screenshot_id} for _, screenshot_id in uploaded]},
                       expect=(204,))
        self._wait_for_delivery(label, uploaded)

    def _upload(self, label, set_id, path):
        report = self.report
        size = path.stat().st_size
        status, payload = self.asc.call("POST", "/appScreenshots", {"data": {
            "type": "appScreenshots", "attributes": {"fileName": path.name, "fileSize": size},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})
        if status != 201:
            report.errors.append(f"{label}/{path.name}: could not reserve the upload (HTTP {status}): "
                                 f"{errors_text(payload)}")
            return None
        screenshot_id = payload["data"]["id"]
        operations = payload["data"].get("attributes", {}).get("uploadOperations") or []
        if not operations:
            report.errors.append(f"{label}/{path.name}: App Store Connect returned no upload operations")
            return None
        with open(path, "rb") as handle:
            for operation in operations:
                handle.seek(operation["offset"])
                failure = put_chunk(operation, handle.read(operation["length"]))
                if failure:
                    report.errors.append(f"{label}/{path.name}: upload failed: {failure}")
                    return None
        status, payload = self.asc.call("PATCH", f"/appScreenshots/{screenshot_id}", {"data": {
            "type": "appScreenshots", "id": screenshot_id,
            "attributes": {"uploaded": True, "sourceFileChecksum": md5(path)}}})
        if status != 200:
            report.errors.append(f"{label}/{path.name}: could not complete the upload (HTTP {status}): "
                                 f"{errors_text(payload)}")
            return None
        report.done.append(f"{label}: uploaded {path.name} ({size} bytes)")
        return screenshot_id

    def _wait_for_delivery(self, label, uploaded, tries=40, pause=6):
        pending = {screenshot_id: path for path, screenshot_id in uploaded}
        for _ in range(tries):
            for screenshot_id in list(pending):
                status, payload = self.asc.get(f"/appScreenshots/{screenshot_id}")
                if status != 200:
                    continue
                delivery = payload["data"].get("attributes", {}).get("assetDeliveryState") or {}
                if delivery.get("state") == "COMPLETE":
                    del pending[screenshot_id]
                elif delivery.get("state") == "FAILED":
                    path = pending.pop(screenshot_id)
                    details = "; ".join(item.get("description") or item.get("code", "")
                                        for item in delivery.get("errors") or [])
                    self.report.errors.append(f"{label}/{path.name}: App Store Connect rejected it: {details}")
            if not pending:
                return
            time.sleep(pause)
        for path in pending.values():
            self.report.errors.append(f"{label}/{path.name}: still processing after {tries * pause} s; "
                                      "check it in App Store Connect")


# ---- Command line ---------------------------------------------------------------------------------------------------

def requested_apps(value, known, with_texts):
    names = [name for name in re.split(r"[\s,]+", value or "") if name]
    if not names or names == ["all"]:
        return sorted(with_texts), []
    return [name for name in names if name in known], [name for name in names if name not in known]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--apps", default="all", help='schemes, separated by commas or spaces, or "all"')
    parser.add_argument("--dry-run", action="store_true", help="print the changes without making them")
    parser.add_argument("--attach-build", action="store_true", help="attach the newest VALID build of the version")
    parser.add_argument("--screenshots", help="the AppStore-screenshots folder (<Scheme>/<locale>/<device>/*.png)")
    parser.add_argument("--metadata", default=str(METADATA_ROOT), help="the store texts folder")
    parser.add_argument("--check-only", action="store_true", help="only check the texts and screenshots offline")
    args = parser.parse_args(argv)

    bundles = scheme_bundles()
    metadata_root = Path(args.metadata)
    with_texts = [path.name for path in metadata_root.iterdir() if path.is_dir()] if metadata_root.is_dir() else []
    unknown_texts = sorted(set(with_texts) - set(bundles))
    apps, unknown = requested_apps(args.apps, bundles, [name for name in with_texts if name in bundles])
    if unknown or unknown_texts:
        for name in unknown:
            print(f"Unknown app: {name}. Apps: {', '.join(sorted(bundles))}")
        for name in unknown_texts:
            print(f"appstore/metadata/{name}: not a scheme in SCHEME_BUNDLES")
        return 1
    if args.screenshots and not Path(args.screenshots).is_dir():
        print(f"No screenshots folder at {args.screenshots}")
        return 1
    versions = app_versions()
    if not args.check_only:
        for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY"):
            if not os.environ.get(name, "").strip():
                print(f"Missing required secret: {name}")
                return 1

    if args.check_only:
        print("OFFLINE CHECK: App Store Connect is not contacted.")
    elif args.dry_run:
        print("DRY RUN: App Store Connect is only read; every change below is printed, not made.")
    else:
        print("Changing App Store Connect. Nothing is submitted for review.")
    asc = Asc(dry_run=args.dry_run or args.check_only)
    reports = []
    for scheme in apps:
        metadata, problems, notes = read_metadata(metadata_root / scheme)
        screenshots, screenshot_notes = (collect_screenshots(args.screenshots, scheme) if args.screenshots
                                         else (None, []))
        report = Report(scheme)
        report.skipped += notes + screenshot_notes
        version = versions.get(scheme)
        if not metadata:
            report.skipped.append("no store texts in appstore/metadata")
        if problems:
            report.errors += problems + ["texts have problems, so nothing was sent for this app"]
        elif not version:
            report.errors.append("no marketing version found in project.yml")
        elif args.check_only:
            report.done.append(f"version {version} ({bundles[scheme]})")
            report.done += [f"{locale}: {', '.join(sorted(values))}" for locale, values in metadata.items()]
            if screenshots is not None:
                for locale in sorted(set(screenshots) | set(metadata)):
                    slots = screenshots.get(locale, {})
                    report.done += [f"{locale} {kind}: {len(files)} screenshots" for kind, files in slots.items()]
                    report.missing += [f"{locale}: {label}" for label in missing_slots(slots)]
        else:
            filler = AppFiller(asc, scheme, bundles[scheme], version, metadata, screenshots, args.attach_build)
            result = filler.run()
            result.skipped = report.skipped + result.skipped
            result.errors = report.errors + result.errors
            report = result
        reports.append(report)

    for report in reports:
        report.print()
    failed = [report.scheme for report in reports if report.errors]
    print("\nNothing was submitted for review." + (" (dry run: nothing was changed)" if asc.dry_run else ""))
    if failed:
        print("Problems in: " + ", ".join(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
