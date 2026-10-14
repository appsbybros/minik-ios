#!/usr/bin/env python3
"""Offline parity audit for the shared family module (Family/) against the read-only Android shared
source (default C:/Projects/MinikFamilyServices). It never writes to the Android tree and never
contacts a server.

Checks:
  texts     Family/FamilyText.swift has exactly FamilyText.java's languages and rows (keys and values).
  pairs     Every English/Hebrew pair in Family/*.swift is one the Android family sources use; Android
            pairs iOS does not show are listed (the Google Play button is deliberately absent).
  catalog   Family/minik-family-catalog.json equals android/src/main/assets/minik-family/catalog.json.
  art       Every Android minik-family/art/<name>.png has Family/FamilyArt.xcassets/family-<name>.imageset
            with one JPEG of the same size (and nothing extra); with Pillow, the JPEG matches the PNG's
            pixels closely (mean difference per channel at most 8 of 255;
            quality-90 JPEG noise is up to about 4.5, another picture is far above 8).

Usage:  python Scripts/audit-family.py [--android PATH]
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAMILY = os.path.join(ROOT, "Family")
JAVA = "android/src/main/java/com/appsbybros/family"
ASSETS = "android/src/main/assets/minik-family"
STRING = r'"((?:[^"\\]|\\.)*)"'
HEBREW = re.compile("[\u0590-\u05ff]")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read().replace("\r\n", "\n")


def unescape(value):
    return re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), value).replace('\\"', '"').replace("\\\\", "\\")


def java_text_rows(android):
    text = read(os.path.join(android, JAVA, "FamilyText.java"))
    langs = re.findall(STRING, re.search(r"LANGS=\{(.*?)\}", text).group(1))
    rows = {}
    for key, values in re.findall(r"ROWS\.put\(" + STRING + r",new String\[\]\{(.*?)\}\);", text):
        rows[unescape(key)] = [unescape(v) for v in re.findall(STRING, values)]
    return langs, rows


def swift_text_rows():
    text = read(os.path.join(FAMILY, "FamilyText.swift"))
    langs = re.findall(STRING, re.search(r"static let languages = \[(.*?)\]", text).group(1))
    rows = {}
    for key, values in re.findall(r"^\s+" + STRING + r": \[(.*)\],?$", text, re.M):
        rows[unescape(key)] = [unescape(v) for v in re.findall(STRING, values)]
    return langs, rows


def pairs(text):
    """English/Hebrew string literal pairs: "en", "he" (or "en",he="he" in Swift lets)."""
    found = set()
    for en, he in re.findall(STRING + r"\s*,\s*(?:he\s*=\s*)?" + STRING, text):
        if HEBREW.search(he) and not HEBREW.search(en):
            found.add((unescape(en), unescape(he)))
    return found


def check_texts(android, problems):
    jl, jr = java_text_rows(android)
    sl, sr = swift_text_rows()
    if jl != sl:
        problems.append("texts: languages differ: Android %s, iOS %s" % (jl, sl))
    for key in sorted(set(jr) | set(sr)):
        if key not in sr:
            problems.append("texts: missing row %r" % key)
        elif key not in jr:
            problems.append("texts: extra row %r" % key)
        elif jr[key] != sr[key]:
            problems.append("texts: row %r differs" % key)
    print("texts: %d Android rows, %d iOS rows" % (len(jr), len(sr)))


def check_pairs(android, problems):
    java = set()
    folder = os.path.join(android, JAVA)
    for name in os.listdir(folder):
        if name.endswith(".java"):
            java |= pairs(read(os.path.join(folder, name)))
    swift = set()
    for name in os.listdir(FAMILY):
        if name.endswith(".swift"):
            swift |= pairs(read(os.path.join(FAMILY, name)))
    for en, he in sorted(swift - java):
        problems.append("pairs: iOS pair not in the Android family sources: %r / %r" % (en, he))
    unused = sorted(java - swift)
    print("pairs: %d iOS pairs, all from Android; Android pairs not shown on iOS: %s"
          % (len(swift), ", ".join(repr(en) for en, _ in unused) or "none"))


def check_catalog(android, problems):
    ios = read(os.path.join(FAMILY, "minik-family-catalog.json"))
    original = read(os.path.join(android, ASSETS, "catalog.json"))
    if ios != original:
        same = json.loads(ios) == json.loads(original)
        problems.append("catalog: differs from Android's asset copy%s" % (" (same JSON, different bytes)" if same else ""))
    apps = sorted(json.loads(original)["apps"])
    print("catalog: %d entries (%s)" % (len(apps), ", ".join(apps)))


def check_art(android, problems):
    try:
        from PIL import Image, ImageChops, ImageStat
    except ImportError:
        Image = None
        print("art: Pillow is missing; pixel comparison skipped")
    art = os.path.join(android, ASSETS, "art")
    catalog = os.path.join(FAMILY, "FamilyArt.xcassets")
    names = sorted(n[:-4] for n in os.listdir(art) if n.endswith(".png"))
    sets = sorted(n[len("family-"):-len(".imageset")] for n in os.listdir(catalog) if n.endswith(".imageset"))
    for extra in sorted(set(sets) - set(names)):
        problems.append("art: extra image set family-%s" % extra)
    worst = 0.0
    for name in names:
        folder = os.path.join(catalog, "family-%s.imageset" % name)
        if not os.path.isdir(folder):
            problems.append("art: missing image set family-%s" % name)
            continue
        contents = json.loads(read(os.path.join(folder, "Contents.json")))
        files = [i.get("filename") for i in contents.get("images", []) if i.get("filename")]
        if files != ["family-%s.jpg" % name]:
            problems.append("art: family-%s lists %s" % (name, files))
            continue
        if Image is None:
            continue
        png = Image.open(os.path.join(art, name + ".png")).convert("RGB")
        jpg = Image.open(os.path.join(folder, files[0])).convert("RGB")
        if png.size != jpg.size:
            problems.append("art: family-%s is %s, Android %s" % (name, jpg.size, png.size))
            continue
        difference = max(ImageStat.Stat(ImageChops.difference(png, jpg)).mean)
        worst = max(worst, difference)
        if difference > 8:
            problems.append("art: family-%s differs from Android (mean %.2f)" % (name, difference))
    print("art: %d images%s" % (len(names), "" if Image is None else ", largest mean difference %.2f of 255" % worst))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--android", default="C:/Projects/MinikFamilyServices")
    args = parser.parse_args()
    problems = []
    check_texts(args.android, problems)
    check_pairs(args.android, problems)
    check_catalog(args.android, problems)
    check_art(args.android, problems)
    for problem in problems:
        print("FAIL " + problem)
    print("audit-family: %s" % ("PASS" if not problems else "%d problem(s)" % len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
