"""Registers the MINIK App IDs in the Apple Developer account through the
App Store Connect API and reports which App Store Connect app records exist.
--check <schemes> is the TestFlight pre-flight; --upload <ipa> sends a build;
--next-build <schemes> prints a build number above every build already uploaded.

Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY (the .p8 text) in the
environment and the PyJWT package with cryptography. Prints no secret values.
"""
import json
import os
import plistlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
APPS = [
    ("com.appsbybros.minik.plus", "Minik Plus", True),
    ("com.appsbybros.minik.plus.english", "Minik Plus English Only", True),
    ("com.appsbybros.minik.math", "Minik Math", False),
    ("com.appsbybros.minik.math.plus", "Minik Math Plus", False),
    ("com.appsbybros.minik.pingpong", "Minik Ping Pong", False),
    ("com.appsbybros.minik.bouncelearn", "Minik Bounce", False),
    ("com.appsbybros.minik.crosspong", "Multi Ping Pong", False),
    ("com.appsbybros.minik.spud", "Minik Spud", False),
    ("com.appsbybros.minik.splash", "Minik Splash", False),
]
# The App Store Connect API has no App Attest capability type: it can neither read
# nor set it, so it is ticked by hand on the App ID.
APP_ATTEST_NOTE = ("App Attest must be ticked under Certificates, Identifiers & Profiles > "
                   "Identifiers (the API cannot check it); otherwise the export fails.")


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        os.environ["ASC_PRIVATE_KEY"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, body=None):
    # Busy or failing Apple servers (429/5xx) get up to four more tries.
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
    return "; ".join(item.get("detail") or item.get("title", "") for item in payload.get("errors", []))


def main():
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY"):
        if not os.environ.get(name, "").strip():
            print(f"Missing required secret: {name}")
            return 1

    failures = 0
    missing_records = []
    for identifier, name, needs_app_attest in APPS:
        query = urllib.parse.urlencode({"filter[identifier]": identifier, "limit": 200})
        status, payload = call("GET", f"/bundleIds?{query}")
        if status != 200:
            print(f"{identifier}: could not list App IDs (HTTP {status}): {errors_text(payload)}")
            failures += 1
            continue
        existing = [item for item in payload.get("data", []) if item["attributes"]["identifier"] == identifier]
        if existing:
            bundle_id = existing[0]["id"]
            print(f"{identifier}: App ID already registered")
        else:
            status, payload = call("POST", "/bundleIds", {
                "data": {
                    "type": "bundleIds",
                    "attributes": {"identifier": identifier, "name": name, "platform": "IOS"},
                }
            })
            if status != 201:
                print(f"{identifier}: registration failed (HTTP {status}): {errors_text(payload)}")
                failures += 1
                continue
            bundle_id = payload["data"]["id"]
            print(f"{identifier}: App ID registered")

        if needs_app_attest:
            print(f"{identifier}: {APP_ATTEST_NOTE}")

        query = urllib.parse.urlencode({"filter[bundleId]": identifier})
        status, payload = call("GET", f"/apps?{query}")
        if status == 200 and payload.get("data"):
            print(f"{identifier}: App Store Connect app record exists")
        elif status == 200:
            missing_records.append(f"{name} ({identifier})")
        else:
            print(f"{identifier}: could not check the app record (HTTP {status}): {errors_text(payload)}")

    if missing_records:
        print("Create these app records in App Store Connect (My Apps > + > New App):")
        for record in missing_records:
            print(f"  - {record}")
    return 1 if failures else 0


SCHEME_BUNDLES = {
    "MinikPlus": "com.appsbybros.minik.plus",
    "MinikPlusEnglish": "com.appsbybros.minik.plus.english",
    # The small Minik Math (Android's web app); Minik Math Plus is the original, larger iOS app.
    "MinikMath": "com.appsbybros.minik.math",
    "MinikMathPlus": "com.appsbybros.minik.math.plus",
    "MinikPingPong": "com.appsbybros.minik.pingpong",
    "MinikRetroPingPong": "com.appsbybros.minik.bouncelearn",
    "MinikMultiPingPong": "com.appsbybros.minik.crosspong",
    "MinikAmudu": "com.appsbybros.minik.spud",
    "MinikSplash": "com.appsbybros.minik.splash",
}


def find_app(identifier):
    """Returns (HTTP status, App Store Connect app id or None) for an exact bundle ID match;
    the filter also returns longer IDs such as minik.plus.english for minik.plus."""
    query = urllib.parse.urlencode({"filter[bundleId]": identifier})
    status, payload = call("GET", f"/apps?{query}")
    if status != 200:
        return status, payload
    ids = [item["id"] for item in payload.get("data", []) if item.get("attributes", {}).get("bundleId") == identifier]
    return status, (ids[0] if ids else None)


def store_versions(app_id):
    """The app's iOS App Store versions as "1.7.9 READY_FOR_SALE" texts, for the pre-flight report."""
    query = urllib.parse.urlencode({"filter[platform]": "IOS", "limit": 10})
    status, payload = call("GET", f"/apps/{app_id}/appStoreVersions?{query}")
    if status != 200:
        return [f"(could not read versions: HTTP {status})"]
    texts = []
    for item in payload.get("data", []):
        attributes = item.get("attributes", {})
        state = attributes.get("appVersionState") or attributes.get("appStoreState") or "?"
        texts.append(f"{attributes.get('versionString')} {state}")
    return texts


def highest_build(app_id):
    """The highest numeric build number App Store Connect has for the app (0 if none), or None if unreadable."""
    query = urllib.parse.urlencode({"filter[app]": app_id, "sort": "-uploadedDate", "limit": 200,
                                    "fields[builds]": "version"})
    status, payload = call("GET", f"/builds?{query}")
    if status != 200:
        return None
    numbers = [int(item["attributes"]["version"]) for item in payload.get("data", [])
               if str(item.get("attributes", {}).get("version", "")).isdigit()]
    return max(numbers, default=0)


def next_build(schemes):
    """Prints one build number above every build App Store Connect already has for these apps.
    A repository that starts counting runs again (a new copy) cannot reuse a number this way.
    Only the number goes to stdout; notes go to stderr."""
    highest = 0
    for scheme in schemes:
        identifier = SCHEME_BUNDLES.get(scheme)
        status, app_id = find_app(identifier) if identifier else (0, None)
        if status != 200 or not app_id:
            print(f"{scheme}: no app record, so no earlier builds", file=sys.stderr)
            continue
        number = highest_build(app_id)
        if number is None:
            print(f"{scheme}: could not read earlier builds", file=sys.stderr)
            continue
        print(f"{scheme}: highest uploaded build {number}", file=sys.stderr)
        highest = max(highest, number)
    print(highest + 1)
    return 0


def check_app_id(identifier, team_id, needs_app_attest, problems):
    """The App ID must exist under the team that APPLE_TEAM_ID names."""
    query = urllib.parse.urlencode({"filter[identifier]": identifier})
    status, payload = call("GET", f"/bundleIds?{query}")
    matches = [item for item in payload.get("data", []) if item["attributes"]["identifier"] == identifier] if status == 200 else []
    if not matches:
        problems.append(f"{identifier}: App ID not found (HTTP {status}). Run the App Store Connect setup workflow.")
        return
    seed_id = matches[0]["attributes"].get("seedId")
    if seed_id and team_id and seed_id != team_id:
        problems.append(f"{identifier}: the App ID belongs to team {seed_id}, but the APPLE_TEAM_ID secret is "
                        f"different. Set APPLE_TEAM_ID to {seed_id}.")
        return
    print(f"{identifier}: App ID registered under the APPLE_TEAM_ID team."
          + (f" {APP_ATTEST_NOTE}" if needs_app_attest else ""))


def check(schemes):
    """Fast pre-flight for the TestFlight upload; uses no macOS minutes."""
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY"):
        if not os.environ.get(name, "").strip():
            print(f"Missing required secret: {name}")
            return 1
    team_id = "".join(os.environ.get("APPLE_TEAM_ID", "").split())
    problems = []
    status, payload = call("GET", "/apps?limit=1")
    if status != 200:
        print(f"The App Store Connect API key was not accepted (HTTP {status}): {errors_text(payload)}")
        print("Check that ASC_KEY_ID, ASC_ISSUER_ID and the full ASC_PRIVATE_KEY text belong to the same Team key.")
        return 1
    print("API key accepted.")
    status, payload = call("GET", "/certificates?limit=1")
    if status != 200:
        problems.append(f"The key cannot read certificates (HTTP {status}): {errors_text(payload)}. "
                        "Cloud signing needs a Team key with the Admin role.")
    else:
        print("Key can read certificates and profiles.")
    # Only Admin keys may read Users and Access; Xcode's cloud signing for the
    # App Store also needs the Admin role.
    status, payload = call("GET", "/users?limit=1")
    if status == 200:
        print("Key has the Admin role (needed for cloud signing).")
    elif status == 403:
        problems.append("The key does not have the Admin role, which Xcode's cloud signing needs. In App Store "
                        "Connect > Users and Access > Integrations > Team Keys, create a key with Admin access and "
                        "update the ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY secrets.")
    else:
        print(f"Could not confirm the key's role (HTTP {status}): {errors_text(payload)}")
    for scheme in schemes:
        identifier = SCHEME_BUNDLES.get(scheme)
        if identifier is None:
            problems.append(f"Unknown scheme: {scheme}")
            continue
        status, app_id = find_app(identifier)
        if status == 200 and app_id:
            print(f"{scheme}: App Store Connect record exists ({identifier}).")
            # An upload must carry a higher version than the last approved one (ITMS-90062).
            print(f"{scheme}: App Store versions: " + (", ".join(store_versions(app_id)) or "none yet"))
            check_app_id(identifier, team_id, scheme in ("MinikPlus", "MinikPlusEnglish"), problems)
        elif status == 200:
            problems.append(f"{scheme}: create the App Store Connect app record for {identifier}.")
        else:
            problems.append(f"{scheme}: could not check the app record (HTTP {status}): {errors_text(app_id)}")
    for problem in problems:
        print("PROBLEM: " + problem)
    return 1 if problems else 0


def put_chunk(operation, data):
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


def upload(ipa_path):
    """Uploads an exported .ipa through the App Store Connect build upload API, the
    path that needs no Xcode account and cannot pick a look-alike bundle ID."""
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY"):
        if not os.environ.get(name, "").strip():
            print(f"Missing required secret: {name}")
            return 1
    with zipfile.ZipFile(ipa_path) as archive:
        names = [item for item in archive.namelist() if re.fullmatch(r"Payload/[^/]+[.]app/Info[.]plist", item)]
        if not names:
            print(f"{ipa_path}: no Payload/*.app/Info.plist inside the .ipa")
            return 1
        info = plistlib.loads(archive.read(names[0]))
    bundle_id = info["CFBundleIdentifier"]
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    print(f"Uploading {bundle_id} {version} ({build}) from {os.path.basename(ipa_path)}")

    status, app_id = find_app(bundle_id)
    if status != 200 or not app_id:
        print(f"No App Store Connect app record for {bundle_id} (HTTP {status}).")
        return 1

    status, payload = call("POST", "/buildUploads", {
        "data": {
            "type": "buildUploads",
            "attributes": {"platform": "IOS", "cfBundleShortVersionString": version, "cfBundleVersion": build},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    })
    if status != 201:
        print(f"Could not start the build upload (HTTP {status}): {errors_text(payload)}")
        return 1
    upload_id = payload["data"]["id"]

    file_size = os.path.getsize(ipa_path)
    status, payload = call("POST", "/buildUploadFiles", {
        "data": {
            "type": "buildUploadFiles",
            "attributes": {"fileName": os.path.basename(ipa_path), "fileSize": file_size,
                           "assetType": "ASSET", "uti": "com.apple.ipa"},
            "relationships": {"buildUpload": {"data": {"type": "buildUploads", "id": upload_id}}},
        }
    })
    if status != 201:
        print(f"Could not register the .ipa file (HTTP {status}): {errors_text(payload)}")
        return 1
    file_id = payload["data"]["id"]
    operations = payload["data"].get("attributes", {}).get("uploadOperations") or []
    if not operations:
        print("App Store Connect returned no upload operations.")
        return 1

    with open(ipa_path, "rb") as handle:
        for index, operation in enumerate(operations, 1):
            handle.seek(operation["offset"])
            failure = put_chunk(operation, handle.read(operation["length"]))
            if failure:
                print(f"Part {index}/{len(operations)} failed: {failure}")
                return 1
    print(f"Sent {file_size} bytes in {len(operations)} parts.")

    status, payload = call("PATCH", f"/buildUploadFiles/{file_id}", {
        "data": {"type": "buildUploadFiles", "id": file_id, "attributes": {"uploaded": True}}
    })
    if status != 200:
        print(f"Could not complete the upload (HTTP {status}): {errors_text(payload)}")
        return 1

    # Apple checks the package within minutes; a rejection shows here instead of only by email.
    state = {}
    for _ in range(12):
        time.sleep(15)
        status, payload = call("GET", f"/buildUploads/{upload_id}")
        if status != 200:
            continue
        state = payload["data"].get("attributes", {}).get("state") or {}
        value = state.get("state") if isinstance(state, dict) else state
        if value == "FAILED":
            print("App Store Connect rejected the build:")
            print(json.dumps(state, indent=2))
            return 1
        if value == "COMPLETE":
            break
    print("App Store Connect state: " + json.dumps(state))
    print(f"Uploaded {bundle_id} build {build}. TestFlight shows it after Apple's processing.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--check":
        sys.exit(check(sys.argv[2:]))
    if len(sys.argv) > 1 and sys.argv[1] == "--next-build":
        sys.exit(next_build(sys.argv[2:]))
    if len(sys.argv) == 3 and sys.argv[1] == "--upload":
        sys.exit(upload(sys.argv[2]))
    sys.exit(main())
