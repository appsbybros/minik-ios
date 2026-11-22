"""Sends a Minik app's App Store version to App Review, or (--check) only reports whether it is ready.

    python3 Scripts/appstore-submit.py --apps MinikPlus --check
    python3 Scripts/appstore-submit.py --apps MinikAmudu --submit

For each app (Xcode scheme) it
- finds the App Store Connect app (SCHEME_BUNDLES) and the App Store version of the app's version in project.yml;
- lists the version's state, its build, the newest processed builds of that version, the in-app purchases and the open
  review submissions;
- with --submit (only when the owner asked for it): attaches the newest processed build of the version when another
  or no build is attached, submits the in-app purchases named by --iaps that are ready to submit (first purchases go
  with the version), creates or reuses the app's review submission, adds the version and submits it. App Store
  Connect's own answer is printed in full, so anything it still needs (age rating, App Privacy, screenshots...) is
  named;
- with --replace-build as well: a version already waiting for review with an older build is withdrawn from review
  (its review submission cancelled), then sent again with the newest build and the purchases that were waiting
  with it. The version loses its place in the review queue.

It never releases a version (no release requests) and never changes prices, texts or screenshots.
Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY (the .p8 text) and PyJWT with cryptography. Prints no secrets.
"""
import argparse
import importlib.util
import json
import sys
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("appstore_metadata", ROOT / "Scripts" / "appstore-metadata.py")
meta = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(meta)

EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
IN_REVIEW = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PROCESSING_FOR_APP_STORE",
             "PENDING_APPLE_RELEASE", "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "ACCEPTED"}


def call(method, path, body=None):
    if "releaseRequest" in path or "phasedRelease" in path:
        raise SystemExit("refused: this script never releases a version")
    return meta.http_call(method, path, body)


def get(path):
    status, payload = call("GET", path)
    if status != 200:
        raise RuntimeError(f"GET {path}: HTTP {status}: {meta.errors_text(payload)}")
    return payload


def write(method, path, body):
    status, payload = call(method, path, body)
    ok = status in (200, 201, 204)
    print(f"    {method} {path.split('?')[0]}: HTTP {status}" + ("" if ok else f" - {meta.errors_text(payload)}"))
    if not ok:
        for error in (payload or {}).get("errors", []):
            print("      " + json.dumps({k: error.get(k) for k in ("code", "title", "detail", "source", "meta")}, ensure_ascii=False))
    return ok, payload


def find_app(bundle_id):
    payload = get("/apps?" + urllib.parse.urlencode({"filter[bundleId]": bundle_id}))
    for app in payload.get("data", []):
        if app["attributes"].get("bundleId") == bundle_id:
            return app
    return None


def wait_for_state(version_id, wanted, tries=40):
    import time
    for _ in range(tries):
        state = get(f"/appStoreVersions/{version_id}")["data"]["attributes"].get("appStoreState")
        if state in wanted:
            return state
        time.sleep(6)
    return state


def run(scheme, version, submit, iap_ids=(), replace_build=False):
    bundles = meta.scheme_bundles()
    bundle_id = bundles.get(scheme)
    print(f"== {scheme} ({bundle_id}), version {version}")
    app = find_app(bundle_id)
    if not app:
        print("   no App Store Connect app with this bundle ID")
        return False
    app_id = app["id"]
    versions = get(f"/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20").get("data", [])
    for v in versions:
        print(f"   version {v['attributes']['versionString']}: {v['attributes'].get('appStoreState')}")
    target = next((v for v in versions if v["attributes"]["versionString"] == version), None)
    if not target:
        print(f"   no App Store version {version}: run the App Store metadata workflow first (it creates it)")
        return False
    state = target["attributes"].get("appStoreState")
    version_id = target["id"]

    builds = get("/builds?" + urllib.parse.urlencode({"filter[app]": app_id, "filter[preReleaseVersion.version]": version,
                                                       "sort": "-uploadedDate", "limit": "5"})).get("data", [])
    for b in builds:
        a = b["attributes"]
        print(f"   build {a.get('version')}: {a.get('processingState')}, uploaded {a.get('uploadedDate')}, "
              f"expired {a.get('expired')}, encryption {a.get('usesNonExemptEncryption')}")
    attached = get(f"/appStoreVersions/{version_id}/build").get("data")
    print(f"   attached build: {attached['attributes'].get('version') if attached else 'none'}")

    iaps = get(f"/apps/{app_id}/inAppPurchasesV2?limit=50").get("data", [])
    for p in iaps:
        print(f"   in-app purchase {p['attributes'].get('productId')}: {p['attributes'].get('state')}")
    submissions = get(f"/reviewSubmissions?filter[app]={app_id}&filter[platform]=IOS&limit=20").get("data", [])
    for s in submissions:
        print(f"   review submission {s['id']}: {s['attributes'].get('state')}")

    newest = next((b for b in builds if b["attributes"].get("processingState") == "VALID" and not b["attributes"].get("expired")), None)
    waiting_iaps = [p for p in iaps if p["attributes"].get("state") == "WAITING_FOR_REVIEW"]
    if submit and replace_build and state == "WAITING_FOR_REVIEW" and newest and (not attached or attached["id"] != newest["id"]):
        open_submission = next((s for s in submissions if s["attributes"].get("state") == "WAITING_FOR_REVIEW"), None)
        if not open_submission:
            print("   no cancellable review submission found")
            return False
        print(f"   withdrawing version {version} (build {attached['attributes'].get('version') if attached else '-'}) "
              f"to send build {newest['attributes'].get('version')}")
        ok, _ = write("PATCH", f"/reviewSubmissions/{open_submission['id']}",
                      {"data": {"type": "reviewSubmissions", "id": open_submission["id"], "attributes": {"canceled": True}}})
        if not ok:
            return False
        state = wait_for_state(version_id, EDITABLE)
        print(f"   version {version} is now {state}")
        iap_ids = set(iap_ids) | {p["attributes"].get("productId") for p in waiting_iaps}
        iaps = get(f"/apps/{app_id}/inAppPurchasesV2?limit=50").get("data", [])
        for p in iaps:
            print(f"   in-app purchase {p['attributes'].get('productId')}: {p['attributes'].get('state')}")
        submissions = get(f"/reviewSubmissions?filter[app]={app_id}&filter[platform]=IOS&limit=20").get("data", [])
    if state in IN_REVIEW:
        print(f"   version {version} is already {state}: nothing to submit")
        return True
    if not submit:
        return True
    if state not in EDITABLE:
        print(f"   version {version} is {state}: it cannot be submitted")
        return False

    if not newest:
        print("   no processed build of this version yet: try again when TestFlight has processed the upload")
        return False
    if newest["attributes"].get("usesNonExemptEncryption") is None:
        # The apps declare ITSAppUsesNonExemptEncryption = false; set it on the build if App Store Connect has none.
        write("PATCH", f"/builds/{newest['id']}", {"data": {"type": "builds", "id": newest["id"],
                                                             "attributes": {"usesNonExemptEncryption": False}}})
    if not attached or attached["id"] != newest["id"]:
        ok, _ = write("PATCH", f"/appStoreVersions/{version_id}/relationships/build",
                      {"data": {"type": "builds", "id": newest["id"]}})
        if not ok:
            return False

    for p in iaps:
        if p["attributes"].get("state") == "READY_TO_SUBMIT" and p["attributes"].get("productId") in iap_ids:
            write("POST", "/inAppPurchaseSubmissions",
                  {"data": {"type": "inAppPurchaseSubmissions",
                            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": p["id"]}}}}})

    open_states = {"READY_FOR_REVIEW", "UNRESOLVED_ISSUES"}
    submission = next((s for s in submissions if s["attributes"].get("state") in open_states), None)
    if submission is None:
        ok, payload = write("POST", "/reviewSubmissions",
                            {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                                      "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        if not ok:
            return False
        submission = payload["data"]
    submission_id = submission["id"]
    items = get(f"/reviewSubmissions/{submission_id}/items?limit=50").get("data", [])
    has_version = False
    for item in items:
        rel = (item.get("relationships") or {}).get("appStoreVersion", {}).get("data")
        if rel and rel.get("id") == version_id:
            has_version = True
    if not has_version:
        ok, _ = write("POST", "/reviewSubmissionItems",
                      {"data": {"type": "reviewSubmissionItems", "relationships": {
                          "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                          "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
        if not ok:
            return False
    ok, payload = write("PATCH", f"/reviewSubmissions/{submission_id}",
                        {"data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}})
    if ok:
        print(f"   SUBMITTED: {scheme} {version} is now {payload['data']['attributes'].get('state')}")
    return ok


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apps", required=True, help="Schemes separated by commas")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="Only report (reads App Store Connect)")
    mode.add_argument("--submit", action="store_true", help="Attach the newest build and send the version to App Review")
    parser.add_argument("--iaps", default="", help="Product IDs of in-app purchases to submit with the version, commas")
    parser.add_argument("--replace-build", action="store_true",
                        help="Withdraw a version waiting for review with an older build and send the newest build")
    args = parser.parse_args()
    versions = meta.app_versions()
    ok = True
    for scheme in [s.strip() for s in args.apps.split(",") if s.strip()]:
        if scheme not in versions:
            print(f"== {scheme}: not in project.yml")
            ok = False
            continue
        try:
            iap_ids = {i.strip() for i in args.iaps.split(",") if i.strip()}
            ok = run(scheme, versions[scheme], args.submit, iap_ids, args.replace_build) and ok
        except RuntimeError as error:
            print(f"   {error}")
            ok = False
    print("Nothing was released; App Review decides, and the owner releases (or automatic release applies).")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
