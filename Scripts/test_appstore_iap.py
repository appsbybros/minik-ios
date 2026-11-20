"""Offline tests of Scripts/appstore-iap.py:  python Scripts/test_appstore_iap.py"""
import copy
import importlib.util
import json
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("appstore_iap", HERE / "appstore-iap.py")
iap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(iap)
CONFIG = iap.load_config("MinikAmudu")


class FakeApi:
    """Answers reads like App Store Connect for an app without the purchase; records every write."""

    def __init__(self, existing=None):
        self.calls, self.existing = [], existing

    def __call__(self, method, path, body):
        self.calls.append((method, path, body))
        if method != "GET":
            if path == "/v2/inAppPurchases":
                return 201, {"data": {"type": "inAppPurchases", "id": "iap1", "attributes": body["data"]["attributes"]}}
            return 201, {"data": {"id": "x", "attributes": {}}}
        if path.startswith("/v1/apps?"):
            return 200, {"data": [{"id": "app1", "attributes": {"bundleId": CONFIG["bundleId"]}}]}
        if "/inAppPurchasesV2" in path:
            return 200, {"data": [self.existing] if self.existing else []}
        if path.startswith("/v1/territories"):
            return 200, {"data": [{"id": "USA"}, {"id": "ISR"}]}
        if "inAppPurchaseLocalizations" in path:
            return 200, {"data": []}
        return 404, {"errors": [{"detail": "not found"}]}


class SettingsFile(unittest.TestCase):
    def test_spud_file_is_valid_and_matches_project(self):
        self.assertEqual(iap.check_config(CONFIG), [])
        self.assertEqual(iap.project_product_id("MinikAmudu"), CONFIG["productId"])
        self.assertTrue(CONFIG["familySharable"])
        self.assertEqual(CONFIG["type"], "NON_CONSUMABLE")
        self.assertEqual(set(CONFIG["localizations"]), {"en-US", "he", "es-ES", "ar-SA", "hi", "nl-NL"})

    def test_too_long_texts_and_a_price_are_refused(self):
        bad = copy.deepcopy(CONFIG)
        bad["localizations"]["he"]["description"] = "א" * 46
        bad["price"] = "2.99"
        problems = " ".join(iap.check_config(bad))
        self.assertIn("he description has 46 characters", problems)
        self.assertIn("price does not belong", problems)


class Guard(unittest.TestCase):
    def test_never_prices_submissions_or_deletions(self):
        for method, path in [("POST", "/v1/inAppPurchasePriceSchedules"), ("GET", "/v2/inAppPurchases/1/pricePoints"),
                             ("POST", "/v1/inAppPurchaseSubmissions"), ("POST", "/v1/reviewSubmissions"),
                             ("DELETE", "/v2/inAppPurchases/1"), ("PATCH", "/v1/apps/1")]:
            with self.assertRaises(iap.Refused, msg=f"{method} {path}"):
                iap.check_request(method, path, {"data": {"attributes": {}}})
        with self.assertRaises(iap.Refused):
            iap.check_request("PATCH", "/v2/inAppPurchases/1", {"data": {"attributes": {"inAppPurchaseType": "CONSUMABLE"}}})
        iap.check_request("GET", "/v2/inAppPurchases/1/iapPriceSchedule")  # reading whether a price exists is fine

    def test_dry_run_sends_no_change(self):
        api = FakeApi()
        asc = iap.Asc(dry_run=True, transport=api)
        iap.fill(asc, CONFIG)
        self.assertTrue(all(method == "GET" for method, _, _ in api.calls))
        self.assertTrue(any("would create the NON_CONSUMABLE purchase" in line for line in asc.done))
        self.assertTrue(any("set the price" in line for line in asc.owner))


class Fill(unittest.TestCase):
    def test_creates_the_purchase_languages_and_availability(self):
        api = FakeApi()
        asc = iap.Asc(dry_run=False, transport=api)
        iap.fill(asc, CONFIG)
        writes = [(m, p, b) for m, p, b in api.calls if m != "GET"]
        create = writes[0]
        self.assertEqual(create[1], "/v2/inAppPurchases")
        attributes = create[2]["data"]["attributes"]
        self.assertEqual(attributes["productId"], "com.appsbybros.minik.spud.full_game")
        self.assertIs(attributes["familySharable"], True)
        self.assertNotIn("price", json.dumps(attributes).replace("<price>", ""))
        locales = [b["data"]["attributes"]["locale"] for m, p, b in writes if p == "/v1/inAppPurchaseLocalizations"]
        self.assertEqual(sorted(locales), sorted(CONFIG["localizations"]))
        availability = [b for m, p, b in writes if p == "/v1/inAppPurchaseAvailabilities"][0]["data"]
        self.assertTrue(availability["attributes"]["availableInNewTerritories"])
        self.assertEqual(len(availability["relationships"]["availableTerritories"]["data"]), 2)
        self.assertEqual(asc.errors, [])
        self.assertTrue(any("set the price" in line for line in asc.owner))

    def test_existing_purchase_of_another_type_is_reported_not_changed(self):
        existing = {"id": "iap9", "attributes": {"productId": CONFIG["productId"], "inAppPurchaseType": "CONSUMABLE",
                                                 "state": "MISSING_METADATA", "name": CONFIG["referenceName"],
                                                 "reviewNote": CONFIG["reviewNote"], "familySharable": True}}
        api = FakeApi(existing)
        asc = iap.Asc(dry_run=False, transport=api)
        iap.fill(asc, CONFIG)
        self.assertTrue(any("cannot be changed" in e for e in asc.errors))
        self.assertFalse(any(p == "/v2/inAppPurchases" for m, p, b in api.calls if m == "POST"))


if __name__ == "__main__":
    unittest.main(verbosity=1)
