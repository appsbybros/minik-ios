"""Creates and fills in an app's in-app purchase in App Store Connect from appstore/iap/<Scheme>.json:
the product (type, reference name, Family Sharing, review note), its store name and description per language,
its availability (every territory, and new ones) and, when the file exists, its App Review screenshot
(appstore/iap/<Scheme>-review.png).

    python3 Scripts/appstore-iap.py --app MinikAmudu --dry-run
    python3 Scripts/appstore-iap.py --app MinikAmudu
    python3 Scripts/appstore-iap.py --check-only --app MinikAmudu     (offline: checks the file, needs no key)

It never sets or changes a PRICE (the owner sets it in App Store Connect), never deletes a purchase and never
submits anything: call() refuses every price, submission, review and release endpoint. The owner attaches the
purchase to the app version and presses "Add for Review" in App Store Connect.

--dry-run reads App Store Connect and prints every change without making one.
Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY (the .p8 text) in the environment and PyJWT with
cryptography. Prints no secret values.
"""
import argparse
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
HOST = "https://api.appstoreconnect.apple.com"
IAP_ROOT = ROOT / "appstore" / "iap"
TYPES = {"CONSUMABLE", "NON_CONSUMABLE", "NON_RENEWING_SUBSCRIPTION"}
# App Store Connect's limits for an in-app purchase.
LIMITS = {"referenceName": 64, "name": 30, "description": 45, "reviewNote": 4000}


# ---- The settings file --------------------------------------------------------------------------------------------

def load_config(scheme, root=IAP_ROOT):
    path = root / f"{scheme}.json"
    if not path.exists():
        raise SystemExit(f"{path} does not exist")
    return json.loads(path.read_text(encoding="utf-8"))


def check_config(config):
    """Problems in the settings file, as sentences (empty when it is fine)."""
    problems = []
    for key in ("bundleId", "productId", "referenceName", "type", "reviewNote", "localizations"):
        if not config.get(key):
            problems.append(f"{key} is missing")
    if config.get("type") and config["type"] not in TYPES:
        problems.append(f"type {config['type']} is not one of {', '.join(sorted(TYPES))}")
    if "price" in json.dumps(config.get("localizations", {})).lower() or "price" in config:
        problems.append("a price does not belong in this file: the owner sets it in App Store Connect")
    product = config.get("productId", "")
    if product and not re.fullmatch(r"[A-Za-z0-9._]+", product):
        problems.append(f"productId {product} may only use letters, digits, dots and underscores")
    for key in ("referenceName", "reviewNote"):
        if len(config.get(key) or "") > LIMITS[key]:
            problems.append(f"{key} has {len(config[key])} characters, more than {LIMITS[key]}")
    locales = config.get("localizations") or {}
    if "en-US" not in locales:
        problems.append("localizations need en-US")
    for locale, texts in locales.items():
        for key in ("name", "description"):
            value = (texts or {}).get(key) or ""
            if not value.strip():
                problems.append(f"{locale} {key} is empty")
            elif len(value) > LIMITS[key]:
                problems.append(f"{locale} {key} has {len(value)} characters, more than {LIMITS[key]}")
    return problems


def project_product_id(scheme, project=ROOT / "project.yml"):
    """SPUD_FULL_GAME_PRODUCT_IDENTIFIER-style setting of the scheme's target in project.yml, if any."""
    text = project.read_text(encoding="utf-8")
    start = re.search(rf"^  {re.escape(scheme)}:\s*$", text, re.M)
    if not start:
        return None
    following = re.search(r"^  \S", text[start.end():], re.M)
    block = text[start.end(): start.end() + following.start()] if following else text[start.end():]
    match = re.search(r"_PRODUCT_IDENTIFIER:\s*\"?([A-Za-z0-9._]+)\"?", block)
    return match.group(1) if match else None


# ---- The App Store Connect API, with the guard ------------------------------------------------------------------

class Refused(Exception):
    """A request this script must never send."""


# Never: prices, submissions, reviews, releases, deletions (also not for reading, except reading the price schedule).
FORBIDDEN_PATH = re.compile(r"submi|releaseRequest|phasedRelease|reviewDetail|customerReview|pricePoint|priceSchedule"
                            r"|inAppPurchasePrice", re.I)
READABLE_PRICE = re.compile(r"/v2/inAppPurchases/[\w-]+/iapPriceSchedule")
ALLOWED_WRITES = [
    ("POST", r"/v2/inAppPurchases", {"name", "productId", "inAppPurchaseType", "reviewNote", "familySharable"}),
    ("PATCH", r"/v2/inAppPurchases/[\w-]+", {"name", "reviewNote", "familySharable"}),
    ("POST", r"/v1/inAppPurchaseLocalizations", {"locale", "name", "description"}),
    ("PATCH", r"/v1/inAppPurchaseLocalizations/[\w-]+", {"name", "description"}),
    ("POST", r"/v1/inAppPurchaseAvailabilities", {"availableInNewTerritories"}),
    ("POST", r"/v1/inAppPurchaseAppStoreReviewScreenshots", {"fileName", "fileSize"}),
    ("PATCH", r"/v1/inAppPurchaseAppStoreReviewScreenshots/[\w-]+", {"uploaded", "sourceFileChecksum"}),
]


def check_request(method, path, body=None):
    method = method.upper()
    bare = path.split("?", 1)[0]
    if not re.match(r"^/v[12]/", bare) or "//" in bare or ".." in bare or "://" in path:
        raise Refused(f"{method} {path}: not a plain App Store Connect API path")
    if FORBIDDEN_PATH.search(bare) and not (method == "GET" and READABLE_PRICE.fullmatch(bare)):
        raise Refused(f"{method} {path}: this script never touches prices, submissions or releases")
    if body is not None and re.search(r'"(submitted|submit|price|manualPrices)"\s*:', json.dumps(body), re.I):
        raise Refused(f"{method} {path}: the body asks for a price or a submission")
    if method == "GET":
        return
    for allowed_method, pattern, attributes in ALLOWED_WRITES:
        if method == allowed_method and re.fullmatch(pattern, bare):
            data = (body or {}).get("data")
            sent = set(data.get("attributes", {})) if isinstance(data, dict) else set()
            extra = sent - attributes
            if extra:
                raise Refused(f"{method} {path}: may not set {', '.join(sorted(extra))}")
            return
    raise Refused(f"{method} {path}: not one of the in-app purchase edits this script may make")


def token():
    import jwt  # PyJWT; imported here so the offline check and the tests need no packages.
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
                      os.environ["ASC_PRIVATE_KEY"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def http_call(method, path, body=None):
    for attempt in range(5):
        request = urllib.request.Request(HOST + path, method=method,
                                         data=None if body is None else json.dumps(body).encode("utf-8"),
                                         headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
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
    def __init__(self, dry_run, transport=None):
        self.dry_run = dry_run
        self.transport = transport or http_call
        self.done, self.skipped, self.errors, self.owner = [], [], [], []

    def get(self, path):
        check_request("GET", path)
        return self.transport("GET", path, None)

    def get_all(self, path):
        items = []
        while path:
            status, payload = self.get(path)
            if status != 200:
                return status, payload
            items += payload.get("data", [])
            link = (payload.get("links") or {}).get("next")
            if link and not link.startswith(HOST + "/"):
                raise Refused(f"next link outside the API: {link}")
            path = link[len(HOST):] if link else None
        return 200, items

    def write(self, what, method, path, body=None):
        check_request(method, path, body)
        if self.dry_run:
            self.done.append("would " + what)
            return None
        status, payload = self.transport(method.upper(), path, body)
        if status not in (200, 201, 204):
            self.errors.append(f"{what}: HTTP {status}: {errors_text(payload)}")
            return False
        self.done.append(what)
        return payload or {}


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


def png_size(path):
    with open(path, "rb") as handle:
        head = handle.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


# ---- Filling in the purchase ---------------------------------------------------------------------------------------

def q(value):
    return urllib.parse.quote(value, safe="")


def fill(asc, config, screenshot=None):
    status, payload = asc.get(f"/v1/apps?filter[bundleId]={q(config['bundleId'])}&fields[apps]=bundleId,name")
    apps = [a for a in payload.get("data", []) if a["attributes"].get("bundleId") == config["bundleId"]] if status == 200 else []
    if not apps:
        asc.errors.append(f"no App Store Connect app with bundle ID {config['bundleId']} (HTTP {status}: {errors_text(payload) if status != 200 else 'none'})")
        return
    app_id = apps[0]["id"]
    print(f"App {app_id} ({config['bundleId']}), purchase {config['productId']}")

    status, items = asc.get_all(f"/v1/apps/{app_id}/inAppPurchasesV2?filter[productId]={q(config['productId'])}&limit=200")
    if status != 200:
        asc.errors.append(f"could not list the app's in-app purchases: HTTP {status}: {errors_text(items)}")
        return
    found = [i for i in items if i["attributes"].get("productId") == config["productId"]]
    wanted = {"name": config["referenceName"], "reviewNote": config["reviewNote"],
              "familySharable": bool(config.get("familySharable"))}
    if not found:
        created = asc.write(f"create the {config['type']} purchase {config['productId']} ({config['referenceName']}, "
                            f"Family Sharing {'on' if wanted['familySharable'] else 'off'}, review note)",
                            "POST", "/v2/inAppPurchases",
                            {"data": {"type": "inAppPurchases",
                                      "attributes": {"productId": config["productId"], "inAppPurchaseType": config["type"], **wanted},
                                      "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        if not created:
            if created is None:  # dry run: nothing more can be read
                for locale, texts in config["localizations"].items():
                    asc.done.append(f"would {locale}: add name = {texts['name']}; description = {texts['description']}")
                asc.done.append("would make it available in every territory, and in new ones")
                if screenshot:
                    asc.done.append(f"would upload the App Review screenshot {screenshot.name}")
                asc.owner.append("set the price (the purchase does not exist yet)")
            return
        iap = created["data"]
    else:
        iap = found[0]
        attributes = iap["attributes"]
        print(f"Exists: {iap['id']}, state {attributes.get('state')}, type {attributes.get('inAppPurchaseType')}")
        if attributes.get("inAppPurchaseType") != config["type"]:
            asc.errors.append(f"it is {attributes.get('inAppPurchaseType')}, not {config['type']}; the type cannot be changed")
        if attributes.get("familySharable") and not wanted["familySharable"]:
            asc.errors.append("Family Sharing is on and can no longer be turned off")
        change = {k: v for k, v in wanted.items() if attributes.get(k) != v}
        if change.get("familySharable") is False:
            change.pop("familySharable")
        if change:
            asc.write("update " + ", ".join(sorted(change)), "PATCH", f"/v2/inAppPurchases/{iap['id']}",
                      {"data": {"type": "inAppPurchases", "id": iap["id"], "attributes": change}})
        else:
            asc.skipped.append("reference name, Family Sharing and review note already up to date")
    iap_id = iap["id"]

    # Store name and description per language.
    status, current = asc.get_all(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations?limit=50")
    current = {c["attributes"]["locale"]: c for c in current} if status == 200 else {}
    if status != 200:
        asc.errors.append(f"could not read the localizations: HTTP {status}")
    for locale, texts in config["localizations"].items():
        texts = {"name": texts["name"], "description": texts["description"]}
        if locale in current:
            have = current[locale]["attributes"]
            change = {k: v for k, v in texts.items() if (have.get(k) or "") != v}
            if change:
                asc.write(f"{locale}: " + "; ".join(f"{k} = {v}" for k, v in change.items()), "PATCH",
                          f"/v1/inAppPurchaseLocalizations/{current[locale]['id']}",
                          {"data": {"type": "inAppPurchaseLocalizations", "id": current[locale]["id"], "attributes": change}})
            else:
                asc.skipped.append(f"{locale}: name and description already up to date")
        else:
            asc.write(f"{locale}: add name = {texts['name']}; description = {texts['description']}", "POST",
                      "/v1/inAppPurchaseLocalizations",
                      {"data": {"type": "inAppPurchaseLocalizations", "attributes": {"locale": locale, **texts},
                                "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}})

    # Availability: every territory, and new territories.
    status, availability = asc.get(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseAvailability")
    if status == 200 and availability.get("data"):
        asc.skipped.append("availability already set (change it in App Store Connect if needed)")
    else:
        status, territories = asc.get_all("/v1/territories?limit=200")
        if status != 200:
            asc.errors.append(f"could not list the territories: HTTP {status}")
        else:
            asc.write(f"make it available in all {len(territories)} territories, and in new ones", "POST",
                      "/v1/inAppPurchaseAvailabilities",
                      {"data": {"type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
                                "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                                                  "availableTerritories": {"data": [{"type": "territories", "id": t["id"]}
                                                                                    for t in territories]}}}})

    # The App Review screenshot.
    status, shot = asc.get(f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot")
    has_shot = status == 200 and shot.get("data")
    if screenshot:
        digest = hashlib.md5(screenshot.read_bytes()).hexdigest()
        if has_shot and shot["data"]["attributes"].get("sourceFileChecksum") == digest:
            asc.skipped.append("App Review screenshot already uploaded")
        elif has_shot:
            asc.owner.append("a different App Review screenshot is already there; replace it by hand if needed")
        else:
            upload_screenshot(asc, iap_id, screenshot, digest)
    elif not has_shot:
        asc.owner.append("add the App Review screenshot (the unlock screen) on the purchase's page")

    # The price is the owner's: only report it.
    status, schedule = asc.get(f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule")
    if status != 200 or not schedule.get("data"):
        asc.owner.append("set the price on the purchase's page (Price Schedule)")
    else:
        asc.skipped.append("a price is set (not changed by this script)")
    asc.owner.append("on version 1.0's page, under In-App Purchases, select this purchase so it is reviewed with the app")


def upload_screenshot(asc, iap_id, path, digest):
    size = path.stat().st_size
    created = asc.write(f"upload the App Review screenshot {path.name} ({png_size(path)})", "POST",
                        "/v1/inAppPurchaseAppStoreReviewScreenshots",
                        {"data": {"type": "inAppPurchaseAppStoreReviewScreenshots",
                                  "attributes": {"fileName": path.name, "fileSize": size},
                                  "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}})
    if not created:
        return
    data = created["data"]
    raw = path.read_bytes()
    for operation in data["attributes"].get("uploadOperations") or []:
        problem = put_chunk(operation, raw[operation["offset"]: operation["offset"] + operation["length"]])
        if problem:
            asc.errors.append(f"screenshot upload: {problem}")
            return
    asc.write("commit the App Review screenshot", "PATCH", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{data['id']}",
              {"data": {"type": "inAppPurchaseAppStoreReviewScreenshots", "id": data["id"],
                        "attributes": {"uploaded": True, "sourceFileChecksum": digest}}})


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--app", required=True, help="Xcode scheme, e.g. MinikAmudu")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args(argv)
    config = load_config(args.app)
    problems = check_config(config)
    in_project = project_product_id(args.app)
    if in_project and in_project != config.get("productId"):
        problems.append(f"productId {config.get('productId')} differs from project.yml ({in_project})")
    if problems:
        print("The settings file has problems:\n  - " + "\n  - ".join(problems))
        return 1
    print(f"{IAP_ROOT.name}/{args.app}.json is fine: {config['productId']}, {len(config['localizations'])} languages"
          + (f", matches project.yml" if in_project else ""))
    if args.check_only:
        return 0
    screenshot = IAP_ROOT / f"{args.app}-review.png"
    asc = Asc(args.dry_run)
    if args.dry_run:
        print("DRY RUN: App Store Connect is only read; every change below is printed, not made.")
    try:
        fill(asc, config, screenshot if screenshot.exists() else None)
    except Refused as error:
        asc.errors.append(f"refused: {error}")
    for title, items in (("Set", asc.done), ("Skipped", asc.skipped), ("For the owner in App Store Connect", asc.owner),
                         ("ERRORS", asc.errors)):
        if items:
            print(f"\n{title}:")
            for item in items:
                print(f"  - {item}")
    print("\nNo price was set and nothing was submitted for review." + (" (dry run: nothing was changed)" if args.dry_run else ""))
    return 1 if asc.errors else 0


if __name__ == "__main__":
    sys.exit(main())
