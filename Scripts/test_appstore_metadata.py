"""Offline tests of Scripts/appstore-metadata.py (no network, no packages):

    python -m unittest discover -s Scripts -p "test_appstore_metadata.py" -v
"""
import importlib.util
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("appstore_metadata", HERE / "appstore-metadata.py")
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


def png(path, width, height):
    """A minimal PNG whose header gives this size (only the header is read)."""
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    chunk = b"IHDR" + ihdr
    data = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", len(ihdr)) + chunk + struct.pack(">I", zlib.crc32(chunk))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data + b"\x00" * 16)


def jpeg(path, width, height):
    app0 = b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
    sof0 = b"\xff\xc0" + struct.pack(">HBHHB", 11, 8, height, width, 1) + b"\x01\x11\x00"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\xff\xd8" + app0 + sof0 + b"\xff\xd9")


class DisplayTypes(unittest.TestCase):
    def test_artifact_folders(self):
        self.assertEqual(m.display_type("iphone-6.9"), "APP_IPHONE_67")
        self.assertEqual(m.display_type("ipad-13"), "APP_IPAD_PRO_3GEN_129")
        self.assertEqual(m.display_type("iphone-6.5"), "APP_IPHONE_65")
        self.assertEqual(m.display_type("APP_IPHONE_65"), "APP_IPHONE_65")
        self.assertIsNone(m.display_type("android-phone"))

    def test_screenshots_config_folders_are_known(self):
        import json
        config = json.loads((m.ROOT / "appstore" / "screenshots.json").read_text(encoding="utf-8"))
        for device in config["devices"].values():
            kind = m.display_type(device["folder"])
            self.assertIsNotNone(kind, device["folder"])
            self.assertTrue(m.size_fits(kind, tuple(device["portrait"])))
            self.assertTrue(m.size_fits(kind, tuple(device["landscape"])))
        for language in config["locales"].values():
            self.assertIn(language["appStore"], m.STORE_LOCALES)

    def test_image_sizes(self):
        with tempfile.TemporaryDirectory() as temp:
            png(Path(temp) / "a.png", 1320, 2868)
            jpeg(Path(temp) / "b.jpg", 2752, 2064)
            (Path(temp) / "c.png").write_bytes(b"not an image")
            self.assertEqual(m.image_size(Path(temp) / "a.png"), (1320, 2868))
            self.assertEqual(m.image_size(Path(temp) / "b.jpg"), (2752, 2064))
            self.assertIsNone(m.image_size(Path(temp) / "c.png"))

    def test_collect(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ("02-learn.png", "01-home.png"):
                png(root / "MinikPlus/en-US/iphone-6.9" / name, 1320, 2868)
            png(root / "MinikPlus/en-US/iphone-6.9/03-wide.png", 2868, 1320)
            png(root / "MinikPlus/en-US/iphone-6.9/04-wrong.png", 1242, 2688)
            (root / "MinikPlus/en-US/iphone-6.9/notes.txt").write_text("x")
            jpeg(root / "MinikPlus/he/ipad-13/01-home.jpg", 2064, 2752)
            png(root / "MinikPlus/he/watch/01.png", 410, 502)
            png(root / "MinikPlus/xx/iphone-6.9/01.png", 1320, 2868)
            for index in range(12):
                png(root / f"MinikMath/en-US/ipad-13/{index:02d}-scene.png", 2752, 2064)
            found, notes = m.collect_screenshots(root, "MinikPlus")
            self.assertEqual([p.name for p in found["en-US"]["APP_IPHONE_67"]],
                             ["01-home.png", "02-learn.png", "03-wide.png"])
            self.assertEqual([p.name for p in found["he"]["APP_IPAD_PRO_3GEN_129"]], ["01-home.jpg"])
            self.assertNotIn("xx", found)
            joined = "\n".join(notes)
            self.assertIn("04-wrong.png: 1242x2688 does not fit APP_IPHONE_67", joined)
            self.assertIn("notes.txt: not a PNG or JPEG", joined)
            self.assertIn("watch: unknown device folder", joined)
            self.assertIn("xx: not an App Store Connect language code", joined)
            found, notes = m.collect_screenshots(root, "MinikMath")
            self.assertEqual(len(found["en-US"]["APP_IPAD_PRO_3GEN_129"]), 10)
            self.assertIn("12 screenshots", "\n".join(notes))
            self.assertEqual(m.collect_screenshots(root, "MinikMaze"), ({}, []))

    def test_missing_slots(self):
        self.assertEqual(m.missing_slots({"APP_IPHONE_67", "APP_IPAD_PRO_3GEN_129"}), [])
        self.assertEqual(m.missing_slots({"APP_IPHONE_65"}), ['iPad 13"'])
        self.assertEqual(m.missing_slots(set()), ['iPhone 6.9" or 6.5"', 'iPad 13"'])
        self.assertEqual(m.missing_slots(set(), ipad=False), ['iPhone 6.9" or 6.5"'])


class Metadata(unittest.TestCase):
    def write(self, root, relative, text, raw=None):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw if raw is not None else text.encode("utf-8"))

    def test_reads_and_normalizes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.write(root, "en-US/description.txt", None, raw=b"\xef\xbb\xbfLine one  \r\n\r\nLine two\r\n")
            self.write(root, "en-US/name.txt", "Minik Plus\n")
            self.write(root, "en-US/subtitle.txt", "   \n")
            self.write(root, "en-US/notes.md", "x")
            self.write(root, "he/keywords.txt", "א,ב")
            locales, problems, notes = m.read_metadata(root)
            self.assertEqual(problems, [])
            self.assertEqual(locales["en-US"], {"description.txt": "Line one\n\nLine two", "name.txt": "Minik Plus"})
            self.assertEqual(locales["he"], {"keywords.txt": "א,ב"})
            self.assertEqual(notes, ["en-US/notes.md: not a known field file, ignored"])

    def test_limits(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.write(root, "he/keywords.txt", ",".join(["מילה"] * 13))           # 64 characters, 116 bytes
            self.write(root, "en-US/keywords.txt", ",".join(["word"] * 20))         # exactly 99 bytes
            self.write(root, "en-US/name.txt", "N" * 31)
            self.write(root, "en-US/subtitle.txt", "S" * 30)
            self.write(root, "en-US/promotional_text.txt", "P" * 171)
            self.write(root, "en-US/description.txt", "D" * 4001)
            self.write(root, "en-US/support_url.txt", "miniklearn.com/contact")
            self.write(root, "xx-YY/name.txt", "Name")
            locales, problems, _ = m.read_metadata(root)
            text = "\n".join(problems)
            self.assertIn("he/keywords.txt: 116 bytes, over App Store Connect's limit of 100", text)
            self.assertNotIn("en-US/keywords.txt", text)
            self.assertNotIn("subtitle", text)
            self.assertIn("en-US/name.txt: 31 characters", text)
            self.assertIn("en-US/promotional_text.txt: 171 characters", text)
            self.assertIn("en-US/description.txt: 4001 characters", text)
            self.assertIn("en-US/support_url.txt: not a web address", text)
            self.assertIn("xx-YY: not an App Store Connect language code", text)
            # Hebrew counts characters for the description, not bytes: 3000 letters is 6000 bytes and fine.
            self.assertEqual(m.check_field("description.txt", "א" * 3000), [])
            self.assertTrue(m.check_field("keywords.txt", "a,,b"))
            self.assertTrue(m.check_field("name.txt", "two\nlines"))

    def test_repository_texts_pass(self):
        bundles = m.scheme_bundles()
        folders = [path for path in m.METADATA_ROOT.iterdir() if path.is_dir()]
        self.assertIn("MinikPlus", [path.name for path in folders])
        self.assertIn("MinikMathPlus", [path.name for path in folders])
        for folder in folders:
            self.assertIn(folder.name, bundles)
            locales, problems, notes = m.read_metadata(folder)
            self.assertEqual(problems, [], folder.name)
            self.assertEqual(notes, [], folder.name)
            self.assertIn("en-US", locales, folder.name)

    def test_versions(self):
        versions = m.app_versions()
        self.assertEqual(versions["MinikPlus"], "1.7.9")
        self.assertEqual(versions["MinikMathPlus"], "1.7.9")
        self.assertEqual(versions["MinikAmudu"], "1.0")
        self.assertRegex(versions["MinikMaze"], r"^\d+\.\d+(\.\d+)?$")
        project = ('settings:\n  base:\n    MINIK_MARKETING_VERSION: "2.0"\ntargetTemplates:\n  T:\n    settings:\n'
                   '      base:\n        MINIK_MARKETING_VERSION: "3.0"\ntargets:\n  A:\n    type: application\n'
                   '  B:\n    settings:\n      base:\n        MINIK_MARKETING_VERSION: "1.0"\n'
                   '  C:\n    templates: [T]\nschemes:\n  A:\n    build: {}\n')
        self.assertEqual(m.project_settings(project, "MINIK_MARKETING_VERSION"), {"A": "2.0", "B": "1.0", "C": "3.0"})

    def test_requested_apps(self):
        known = {"MinikPlus": "a", "MinikMathPlus": "b", "MinikMath": "c"}
        self.assertEqual(m.requested_apps("all", known, ["MinikPlus", "MinikMathPlus"]),
                         (["MinikMathPlus", "MinikPlus"], []))
        self.assertEqual(m.requested_apps("MinikPlus, MinikMath Nope", known, []), (["MinikPlus", "MinikMath"], ["Nope"]))


class SubmitGuard(unittest.TestCase):
    def test_refuses_review_and_release(self):
        refused = [
            ("POST", "/reviewSubmissions", {"data": {"type": "reviewSubmissions"}}),
            ("PATCH", "/reviewSubmissions/abc", {"data": {"attributes": {"submitted": True}}}),
            ("POST", "/reviewSubmissionItems", {"data": {}}),
            ("GET", "/reviewSubmissions?filter[app]=1", None),
            ("GET", "/apps/1/reviewSubmissions", None),
            ("POST", "/appStoreVersionSubmissions", {"data": {}}),
            ("DELETE", "/appStoreVersionSubmissions/1", None),
            ("POST", "/betaAppReviewSubmissions", {"data": {}}),
            ("POST", "/appStoreVersionReleaseRequests", {"data": {}}),
            ("POST", "/appStoreVersionPhasedReleases", {"data": {}}),
            ("PATCH", "/appStoreVersions/1", {"data": {"attributes": {"releaseType": "AFTER_APPROVAL"}}}),
            ("PATCH", "/appStoreVersions/1", {"data": {"attributes": {"versionString": "1.0", "submitted": True}}}),
            ("DELETE", "/apps/1", None),
            ("DELETE", "/appStoreVersions/1", None),
            ("POST", "/builds", {"data": {}}),
            ("GET", "https://example.com/v1/apps", None),
            ("GET", "/apps/../reviewSubmissions", None),
        ]
        for method, path, body in refused:
            with self.subTest(method=method, path=path):
                with self.assertRaises(m.Refused):
                    m.check_request(method, path, body)

    def test_allows_store_page_edits(self):
        allowed = [
            ("GET", "/apps?filter%5BbundleId%5D=com.appsbybros.minik.plus", None),
            ("POST", "/appStoreVersions", {"data": {"attributes": {"platform": "IOS", "versionString": "1.7.9"}}}),
            ("PATCH", "/appStoreVersions/1", {"data": {"attributes": {"versionString": "1.7.9"}}}),
            ("PATCH", "/appStoreVersions/1/relationships/build", {"data": {"type": "builds", "id": "2"}}),
            ("POST", "/appStoreVersionLocalizations", {"data": {"attributes": {"locale": "he", "keywords": "a"}}}),
            ("PATCH", "/appStoreVersionLocalizations/1", {"data": {"attributes": {"description": "submit it"}}}),
            ("PATCH", "/appInfoLocalizations/1", {"data": {"attributes": {"name": "Minik", "subtitle": "x"}}}),
            ("POST", "/appScreenshotSets", {"data": {"attributes": {"screenshotDisplayType": "APP_IPHONE_67"}}}),
            ("POST", "/appScreenshots", {"data": {"attributes": {"fileName": "01.png", "fileSize": 3}}}),
            ("PATCH", "/appScreenshots/1", {"data": {"attributes": {"uploaded": True, "sourceFileChecksum": "0"}}}),
            ("DELETE", "/appScreenshots/1", None),
            ("PATCH", "/appScreenshotSets/1/relationships/appScreenshots", {"data": [{"type": "appScreenshots"}]}),
        ]
        for method, path, body in allowed:
            with self.subTest(method=method, path=path):
                m.check_request(method, path, body)

    def test_dry_run_sends_no_write(self):
        asc = m.Asc(dry_run=True, transport=lambda *a: self.fail("transport must not be reached"))
        with self.assertRaises(m.Refused):
            asc.call("PATCH", "/appStoreVersionLocalizations/1", {"data": {"attributes": {"keywords": "a"}}})
        report = m.Report("X")
        self.assertIsNone(asc.write(report, "set keywords", "PATCH", "/appStoreVersionLocalizations/1",
                                    {"data": {"attributes": {"keywords": "a"}}}))
        self.assertEqual(report.done, ["would set keywords"])


class FakeConnect:
    """A small in-memory App Store Connect: a new app record with its default editable 1.0 version."""

    def __init__(self, released=False):
        self.calls = []
        self.versions = [{"id": "v1", "attributes": {"versionString": "1.0", "appVersionState": "PREPARE_FOR_SUBMISSION"}}]
        if released:
            self.versions.append({"id": "v0", "attributes": {"versionString": "0.9", "appVersionState": "READY_FOR_SALE"}})
        self.localizations = [{"id": "l-en", "attributes": {"locale": "en-US", "description": "old",
                                                            "keywords": "kids", "whatsNew": None}}]

    def __call__(self, method, path, body=None):
        m.check_request(method, path, body)
        self.calls.append((method, path, body))
        bare = path.split("?")[0]
        if method == "GET":
            if bare == "/apps":
                return 200, {"data": [{"id": "app1", "attributes": {"bundleId": "com.appsbybros.minik.plus",
                                                                   "primaryLocale": "en-US"}}]}
            if bare == "/apps/app1/appStoreVersions":
                return 200, {"data": self.versions}
            if bare == "/apps/app1/appInfos":
                return 200, {"data": [{"id": "i1", "attributes": {"state": "PREPARE_FOR_SUBMISSION"}}]}
            if bare == "/appInfos/i1/appInfoLocalizations":
                return 200, {"data": [{"id": "il-en", "attributes": {"locale": "en-US", "name": "Minik Plus"}}]}
            if bare == "/appStoreVersions/v1/appStoreVersionLocalizations":
                return 200, {"data": self.localizations}
            if bare == "/builds":
                return 200, {"data": [{"id": "b7", "attributes": {"version": "1207"}}]}
            if bare == "/appStoreVersions/v1/build":
                return 200, {"data": None}
            if bare.endswith("/appScreenshotSets"):
                return 200, {"data": [{"id": "s67", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"}}]}
            if bare == "/appScreenshotSets/s67/appScreenshots":
                return 200, {"data": [{"id": "old1", "attributes": {"fileName": "old.png", "sourceFileChecksum": "x"}}]}
            if bare.startswith("/appScreenshots/"):
                return 200, {"data": {"attributes": {"assetDeliveryState": {"state": "COMPLETE"}}}}
            return 200, {"data": []}
        if method == "POST":
            kind = bare.strip("/")
            attributes = {"uploadOperations": []} if kind == "appScreenshots" else {}
            return 201, {"data": {"id": "new-" + kind, "attributes": attributes}}
        if method == "PATCH" and bare.startswith("/appStoreVersionLocalizations/") and \
                "whatsNew" in body["data"]["attributes"]:
            return 409, {"errors": [{"detail": "whatsNew cannot be edited"}]}
        return (204 if method == "DELETE" or "relationships" in bare else 200), {}


class Filling(unittest.TestCase):
    METADATA = {
        "en-US": {"description.txt": "New text", "keywords.txt": "kids", "whats_new.txt": "Fixes",
                  "name.txt": "Minik Plus", "subtitle.txt": "Words"},
        "he": {"description.txt": "טקסט", "name.txt": "מיניק"},
    }

    def fill(self, dry_run, released=False, screenshots=None, attach=True):
        connect = FakeConnect(released)
        filler = m.AppFiller(m.Asc(dry_run, transport=connect), "MinikPlus", "com.appsbybros.minik.plus", "1.7.9",
                             self.METADATA, screenshots, attach)
        return connect, filler.run()

    def writes(self, connect):
        return [(method, path) for method, path, _ in connect.calls if method != "GET"]

    def test_dry_run_only_reads(self):
        connect, report = self.fill(dry_run=True)
        self.assertEqual(self.writes(connect), [])
        self.assertEqual(report.errors, [])
        done = "\n".join(report.done)
        self.assertIn("would rename the editable version 1.0 to 1.7.9", done)
        self.assertIn("would he: add app information", done)
        self.assertIn("would en-US: subtitle = Words", done)
        self.assertIn("would en-US: description = New text", done)
        self.assertIn("would he: add the language", done)
        self.assertIn("would attach build 1.7.9 (1207)", done)
        self.assertIn("what's new not set: the first version", "\n".join(report.skipped))
        self.assertIn("en-US: iPad 13\"", report.missing[0] + report.missing[1])

    def test_real_run_makes_only_store_page_edits(self):
        connect, report = self.fill(dry_run=False)
        self.assertEqual(report.errors, [])
        self.assertEqual(self.writes(connect), [
            ("PATCH", "/appStoreVersions/v1"),
            ("PATCH", "/appInfoLocalizations/il-en"),
            ("POST", "/appInfoLocalizations"),
            ("PATCH", "/appStoreVersionLocalizations/l-en"),
            ("POST", "/appStoreVersionLocalizations"),
            ("PATCH", "/appStoreVersions/v1/relationships/build"),
        ])
        for _, path, body in connect.calls:
            self.assertNotRegex(path, "(?i)submi")
            if body:
                self.assertNotIn("whatsNew", str(body))

    def test_whats_new_retry_after_refusal(self):
        connect, report = self.fill(dry_run=False, released=True, attach=False)
        patches = [body["data"]["attributes"] for method, path, body in connect.calls
                   if method == "PATCH" and path == "/appStoreVersionLocalizations/l-en"]
        self.assertEqual(patches, [{"description": "New text", "whatsNew": "Fixes"}, {"description": "New text"}])
        self.assertEqual(report.errors, [])
        self.assertIn("what's new refused", "\n".join(report.skipped))

    def test_screenshots_dry_run(self):
        with tempfile.TemporaryDirectory() as temp:
            png(Path(temp) / "MinikPlus/en-US/iphone-6.9/01-home.png", 1320, 2868)
            png(Path(temp) / "MinikPlus/en-US/ipad-13/01-home.png", 2064, 2752)
            png(Path(temp) / "MinikPlus/ar-SA/ipad-13/01-home.png", 2064, 2752)
            shots, _ = m.collect_screenshots(temp, "MinikPlus")
            connect, report = self.fill(dry_run=True, screenshots=shots, attach=False)
        self.assertEqual(self.writes(connect), [])
        done = "\n".join(report.done)
        self.assertIn("would en-US APP_IPHONE_67: delete old screenshot old.png", done)
        self.assertIn("would upload 1 screenshots to en-US APP_IPHONE_67: 01-home.png", done)
        self.assertIn("would en-US APP_IPAD_PRO_3GEN_129: create the screenshot set", done)
        self.assertIn("ar-SA: screenshots not uploaded", "\n".join(report.skipped))
        self.assertNotIn("en-US: iPad 13\"", report.missing)


class CommandLine(unittest.TestCase):
    def test_main_dry_run_with_fake_connect(self):
        import contextlib
        import io
        import os
        connect = FakeConnect()
        saved = m.http_call, dict(os.environ)
        m.http_call = connect
        os.environ.update({"ASC_KEY_ID": "test", "ASC_ISSUER_ID": "test", "ASC_PRIVATE_KEY": "test"})
        output = io.StringIO()
        try:
            with contextlib.redirect_stdout(output):
                code = m.main(["--apps", "MinikPlus", "--dry-run", "--attach-build"])
        finally:
            m.http_call = saved[0]
            os.environ.clear()
            os.environ.update(saved[1])
        text = output.getvalue()
        self.assertEqual(code, 0, text)
        self.assertEqual([call for call in connect.calls if call[0] != "GET"], [])
        self.assertIn("DRY RUN", text)
        self.assertIn("would rename the editable version 1.0 to 1.7.9", text)
        self.assertIn("Nothing was submitted for review.", text)

    def test_unknown_app(self):
        import contextlib
        import io
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.main(["--apps", "NoSuchApp", "--check-only"]), 1)


if __name__ == "__main__":
    unittest.main()
