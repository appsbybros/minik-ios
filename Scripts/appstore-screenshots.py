"""App Store screenshots: frames raw Simulator captures with a branded background
and caption at Apple's exact sizes, and checks every output against App Store
Connect's rules.

  python Scripts/appstore-screenshots.py plan [--products "A B" | all] [--languages "en he" | all]
      The capture jobs for GitHub Actions: JSON {"include": [{"group", "products"}]}.
      Apps whose scene hooks are still missing ("hooks": "pending") are skipped.
  python Scripts/appstore-screenshots.py scenes <App>
      Lines "id|scene|wait|iphone orientation|ipad orientation" for the capture workflow.
  python Scripts/appstore-screenshots.py languages <App> [--only "en he" | all]
      Lines "language|AppleLocale" for the capture workflow.
  python Scripts/appstore-screenshots.py compose --raw <dir> --out <dir> [--apps A B] [--languages en he]
      Reads <raw>/<App>/<lang>/<iphone|ipad>/<id>.png and writes, ready for upload,
      <out>/<App>/<App Store locale>/<iphone-6.9|ipad-13>/NN-id.png, plus index.html.
      Then validates the output (below) and fails if anything breaks the rules.
      Needs Pillow and Chrome or Edge (set CHROME to choose a browser).
  python Scripts/appstore-screenshots.py validate --out <dir> [--apps A B] [--languages en he]
      App Store Connect's rules: the exact pixel size of the device slot, PNG or
      JPEG, RGB without alpha, sRGB, 1-10 screenshots per slot and language, and
      each file well under 10 MB. Exits 1 and lists every problem.
  python Scripts/appstore-screenshots.py check
      Checks appstore/screenshots.json itself (captions for every language, ids, groups).

Captions, scenes, languages and palettes live in appstore/screenshots.json.
"""
import argparse
import html
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / "appstore/screenshots.json").read_text(encoding="utf-8"))
FONT = ROOT / "appstore/fonts/Heebo-Variable.ttf"
RTL = {"he", "ar"}
# App Store Connect accepts files up to 10 MB; staying well under leaves a safe margin.
MAX_BYTES = 8 * 1024 * 1024
# A frame larger than this as PNG is written as a high-quality JPEG instead.
PNG_BUDGET = 7 * 1024 * 1024
NAME = re.compile(r"^\d\d-[a-z0-9-]+\.(png|jpg)$")


def orientation(app, scene, device):
    for source in (scene, app):
        value = source.get("orientation")
        if isinstance(value, dict) and device in value:
            return value[device]
        if isinstance(value, str):
            return value
    return "portrait"


def locale(language):
    return CONFIG["locales"][language]


def requested_languages(app, only):
    languages = app["languages"]
    if not only or only == ["all"]:
        return languages
    return [language for language in languages if language in only]


def slot(device):
    return CONFIG["devices"][device]["folder"]


def check_config():
    """Problems in appstore/screenshots.json itself."""
    problems = []
    apps = CONFIG["apps"]
    for name in CONFIG["defaultProducts"]:
        if name not in apps:
            problems.append(f"defaultProducts: unknown app {name}")
    grouped = [name for members in CONFIG["groups"].values() for name in members]
    for name in apps:
        if grouped.count(name) != 1:
            problems.append(f"groups: {name} must be in exactly one group")
    for name, app in apps.items():
        if app["palette"] not in CONFIG["palettes"]:
            problems.append(f"{name}: unknown palette {app['palette']}")
        if not 1 <= len(app["scenes"]) <= 10:
            problems.append(f"{name}: {len(app['scenes'])} scenes (App Store Connect takes 1-10)")
        ids = [scene["id"] for scene in app["scenes"]]
        if len(set(ids)) != len(ids):
            problems.append(f"{name}: duplicate scene ids")
        for language in app["languages"]:
            if language not in CONFIG["locales"]:
                problems.append(f"{name}: language {language} has no entry in 'locales'")
        for scene in app["scenes"]:
            if not NAME.match(scene["id"] + ".png"):
                problems.append(f"{name}/{scene['id']}: the id must look like NN-name")
            for device in CONFIG["devices"]:
                if orientation(app, scene, device) not in ("portrait", "landscape"):
                    problems.append(f"{name}/{scene['id']}: unknown orientation on {device}")
            for language in app["languages"]:
                caption = scene["caption"].get(language)
                if not (isinstance(caption, list) and len(caption) == 3 and all(isinstance(t, str) and t.strip() for t in caption)):
                    problems.append(f"{name}/{scene['id']}: no [eyebrow, title, subtitle] caption in '{language}'")
                    continue
                text = " ".join(caption).lower()
                if "for kids" in text or "for children" in text:
                    problems.append(f"{name}/{scene['id']}/{language}: Apple reserves 'for kids' / 'for children'")
            for language in scene["caption"]:
                if language not in app["languages"]:
                    problems.append(f"{name}/{scene['id']}: caption in '{language}', which the app does not list")
    return problems


def report(problems, what):
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        print(f"{what}: FAILED, {len(problems)} problems")
    return problems


def print_scenes(app_name):
    app = CONFIG["apps"][app_name]
    for scene in app["scenes"]:
        print("|".join([scene["id"], scene["scene"], str(scene.get("wait", 6)),
                        orientation(app, scene, "iphone"), orientation(app, scene, "ipad")]))
    return 0


def print_languages(app_name, only):
    for language in requested_languages(CONFIG["apps"][app_name], only):
        print(f"{language}|{locale(language)['appleLocale']}")
    return 0


def plan(products, languages):
    """The capture jobs: one macOS job per product group, so each stays well inside the runner's time limit."""
    if report(check_config(), "appstore/screenshots.json"):
        return 1
    apps = CONFIG["apps"]
    if not products or products == ["all"]:
        products = CONFIG["defaultProducts"]
    unknown = [name for name in products if name not in apps]
    if unknown:
        sys.exit(f"Unknown apps: {' '.join(unknown)} (known: {' '.join(apps)})")
    chosen = []
    for name in products:
        if apps[name].get("hooks") == "pending":
            print(f"::warning::{name} skipped: its scene hooks are not in the app yet "
                  f"(appstore/screenshots.json 'hooks': 'pending').", file=sys.stderr)
        elif name not in chosen:
            chosen.append(name)
    if languages and languages != ["all"]:
        unknown = [language for language in languages if language not in CONFIG["locales"]]
        if unknown:
            sys.exit(f"Unknown languages: {' '.join(unknown)} (known: {' '.join(CONFIG['locales'])})")
        for name in [name for name in chosen if not requested_languages(apps[name], languages)]:
            print(f"::warning::{name} skipped: it ships none of the languages '{' '.join(languages)}'.", file=sys.stderr)
            chosen.remove(name)
    include = []
    for group, members in CONFIG["groups"].items():
        selected = [name for name in members if name in chosen]
        if selected:
            # A group of web apps (Bounce) is drawn in WebKit, not the Simulator.
            web = all("web" in apps[name] for name in selected)
            include.append({"group": group, "products": " ".join(selected), "web": web})
    if not include:
        sys.exit("Nothing to capture.")
    print(json.dumps({"include": include}))
    return 0


def find_browser():
    candidates = [os.environ.get("CHROME", ""),
                  "C:/Program Files/Google/Chrome/Application/chrome.exe",
                  "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
                  "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
                  "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
                  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]
    candidates += [shutil.which(name) or "" for name in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser")]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return candidate
    sys.exit("No Chrome or Edge found; set CHROME to the browser executable.")


def page(width, height, landscape, language, palette, caption, image_uri):
    base = min(width, height)
    rtl = language in RTL
    eyebrow, title, subtitle = (caption + ["", "", ""])[:3]
    pad = round(base * 0.075)
    align = ("right" if rtl else "left") if landscape else "center"
    blobs = "".join(
        f'<div class="blob" style="width:{round(base * size)}px;height:{round(base * size)}px;'
        f'{side}:{round(base * dx)}px;top:{round(height * dy)}px"></div>'
        for size, side, dx, dy in ((0.9, "right", -0.35, 0.55), (0.7, "left", -0.3, 0.78), (0.5, "left", -0.2, -0.08)))
    # Heebo covers Latin and Hebrew; Arabic and Devanagari come from Noto (Linux) or Windows' own fonts.
    fonts = ("Heebo,'Noto Sans Arabic','Noto Naskh Arabic','Noto Sans Devanagari','Nirmala UI',"
             "'Segoe UI','Noto Sans',Arial,sans-serif")
    return f"""<!doctype html><html lang="{language}" dir="{'rtl' if rtl else 'ltr'}"><meta charset="utf-8">
<style>
@font-face{{font-family:Heebo;src:url('{FONT.as_uri()}') format('truetype');font-weight:100 900}}
*{{box-sizing:border-box;margin:0}}
html,body{{width:{width}px;height:{height}px;overflow:hidden}}
body{{font-family:{fonts};position:relative;color:{palette['text']};
  background:linear-gradient(165deg,{palette['top']} 0%,{palette['bottom']} 100%);
  display:grid;grid-template-rows:auto 1fr;padding:{round(base * 0.06)}px {pad}px {round(base * 0.04)}px}}
.blob{{position:absolute;border-radius:50%;background:rgba(255,255,255,.09)}}
.copy{{position:relative;text-align:{align}}}
.eyebrow{{color:{palette['eyebrow']};font-weight:800;letter-spacing:.03em;font-size:{round(base * 0.034)}px;line-height:1.2}}
h1{{color:{palette['title']};font-weight:800;font-size:{round(base * 0.078)}px;line-height:1.08;margin-top:{round(base * 0.014)}px}}
p{{font-size:{round(base * 0.04)}px;line-height:1.3;margin-top:{round(base * 0.016)}px}}
.shot{{position:relative;min-height:0;display:flex;align-items:center;justify-content:center;padding-top:{round(base * 0.045)}px}}
.shot img{{max-width:100%;max-height:100%;display:block;border:{max(4, round(base * 0.007))}px solid rgba(255,255,255,.96);
  border-radius:{round(base * 0.035)}px;box-shadow:0 {round(base * 0.012)}px {round(base * 0.04)}px rgba(10,10,40,.38)}}
</style>
<body>{blobs}
<div class="copy"><div class="eyebrow">{html.escape(eyebrow)}</div><h1>{html.escape(title)}</h1><p>{html.escape(subtitle)}</p></div>
<div class="shot"><img src="{image_uri}"></div>
</body></html>"""


def srgb_profile():
    try:
        from PIL import ImageCms
        return ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    except Exception:  # Pillow without LittleCMS: an untagged RGB file is read as sRGB.
        return None


def save_opaque(image, output):
    """Writes an RGB file with no alpha channel, tagged sRGB: PNG, or JPEG when the PNG would be too large."""
    from PIL import Image
    if image.mode in ("RGBA", "LA", "P", "PA") or "transparency" in image.info:
        rgba = image.convert("RGBA")
        flat = Image.new("RGB", rgba.size, (255, 255, 255))
        flat.paste(rgba, mask=rgba.getchannel("A"))
        image = flat
    else:
        image = image.convert("RGB")
    profile = srgb_profile()
    extra = {"icc_profile": profile} if profile else {}
    buffer = io.BytesIO()
    image.save(buffer, "PNG", optimize=True, **extra)
    output.parent.mkdir(parents=True, exist_ok=True)
    if buffer.tell() <= PNG_BUDGET:
        output.write_bytes(buffer.getvalue())
        return output
    jpeg = output.with_suffix(".jpg")
    for quality in (92, 85, 75):
        image.save(jpeg, "JPEG", quality=quality, subsampling=0 if quality > 80 else 2, **extra)
        if jpeg.stat().st_size < MAX_BYTES:
            break
    return jpeg


def render(browser, html_text, width, height, output, workdir):
    from PIL import Image
    source = workdir / (output.stem + ".html")
    source.write_text(html_text, encoding="utf-8")
    shot = workdir / (output.stem + "-render.png")
    if shot.exists():
        shot.unlink()
    command = [browser, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
               "--force-color-profile=srgb", "--allow-file-access-from-files", "--virtual-time-budget=3000",
               "--no-first-run", "--no-default-browser-check", f"--user-data-dir={workdir / 'browser'}",
               f"--window-size={width},{height}", f"--screenshot={shot}", source.as_uri()]
    if sys.platform.startswith("linux"):
        command.insert(1, "--no-sandbox")
    subprocess.run(command, check=True, capture_output=True, timeout=120)
    with Image.open(shot) as image:
        if image.size != (width, height):
            raise SystemExit(f"{output}: the browser rendered {image.size}, expected {(width, height)}")
        return save_opaque(image, output)


def prepared_capture(raw, landscape, workdir):
    """Returns a capture turned the right way up for the frame."""
    from PIL import Image
    with Image.open(raw) as image:
        rotate = landscape != (image.width > image.height)
        if not rotate:
            return raw
        # A landscape interface on a portrait Simulator display: its top faces the
        # display's right edge (landscapeRight), so turn it counterclockwise.
        parts = raw.parts[-4:]
        turned = workdir / "-".join(parts)
        image.rotate(90, expand=True).save(turned)
        return turned


def compose(raw_root, out_root, apps, languages):
    if report(check_config(), "appstore/screenshots.json"):
        return 1
    browser = find_browser()
    out_root.mkdir(parents=True, exist_ok=True)
    made, missing = [], []
    with tempfile.TemporaryDirectory() as temp:
        workdir = Path(temp)
        for app_name in apps:
            app = CONFIG["apps"][app_name]
            palette = CONFIG["palettes"][app["palette"]]
            for language in requested_languages(app, languages):
                for device, sizes in CONFIG["devices"].items():
                    folder = out_root / app_name / locale(language)["appStore"] / slot(device)
                    if folder.exists():
                        shutil.rmtree(folder)
                    for scene in app["scenes"]:
                        raw = raw_root / app_name / language / device / f"{scene['id']}.png"
                        if not raw.exists():
                            missing.append(raw)
                            continue
                        landscape = orientation(app, scene, device) == "landscape"
                        width, height = sizes["landscape" if landscape else "portrait"]
                        capture = prepared_capture(raw, landscape, workdir)
                        output = render(browser, page(width, height, landscape, language, palette,
                                                      scene["caption"][language], capture.as_uri()),
                                        width, height, folder / f"{scene['id']}.png", workdir)
                        made.append(output)
                        print(f"{output.relative_to(out_root).as_posix()}  {width}x{height}")
    write_index(out_root, made)
    for raw in missing:
        print(f"::warning::missing capture: {raw}")
    print(f"{len(made)} screenshots written to {out_root}")
    problems = validate(out_root, apps, languages)
    return 1 if problems or not made else 0


def write_index(out_root, made):
    rows = []
    for path in made:
        relative = path.relative_to(out_root).as_posix()
        rows.append(f'<figure><img src="{relative}" loading="lazy"><figcaption>{html.escape(relative)}</figcaption></figure>')
    (out_root / "index.html").write_text(
        "<!doctype html><meta charset='utf-8'><title>App Store screenshots</title>"
        "<style>body{font-family:sans-serif;background:#222;color:#eee;display:flex;flex-wrap:wrap;gap:16px;padding:16px}"
        "figure{margin:0}img{height:420px;display:block}figcaption{font-size:12px;margin-top:4px}</style>"
        + "".join(rows), encoding="utf-8")


def check_file(path, device):
    """App Store Connect's rules for one screenshot; returns the problems found."""
    from PIL import Image
    problems = []
    size = path.stat().st_size
    if size >= MAX_BYTES:
        problems.append(f"{size / 1048576:.1f} MB, over the {MAX_BYTES // 1048576} MB budget (App Store limit 10 MB)")
    try:
        with Image.open(path) as image:
            image.load()
            if image.format not in ("PNG", "JPEG"):
                problems.append(f"format {image.format}, not PNG or JPEG")
            if (path.suffix.lower() == ".png") != (image.format == "PNG"):
                problems.append(f"the extension does not match the {image.format} data")
            if image.mode != "RGB":
                problems.append(f"color mode {image.mode}, not RGB without alpha")
            if "transparency" in image.info:
                problems.append("has a transparency key")
            allowed = {tuple(CONFIG["devices"][device]["portrait"]), tuple(CONFIG["devices"][device]["landscape"])}
            if image.size not in allowed:
                problems.append(f"{image.size[0]}x{image.size[1]}, not "
                                + " or ".join(f"{w}x{h}" for w, h in sorted(allowed)))
            profile = image.info.get("icc_profile")
            if profile:
                try:
                    from PIL import ImageCms
                    description = ImageCms.getProfileDescription(ImageCms.ImageCmsProfile(io.BytesIO(profile)))
                except Exception:
                    description = "sRGB" if b"sRGB" in profile else "unknown"
                if "srgb" not in description.lower():
                    problems.append(f"color profile '{description.strip()}', not sRGB")
    except Exception as error:  # an unreadable file is a problem too
        problems.append(f"cannot be read: {error}")
    return problems


def validate(out_root, apps, languages):
    problems = check_config()
    checked = 0
    for app_name in apps:
        app = CONFIG["apps"][app_name]
        expected = {scene["id"] for scene in app["scenes"]}
        for language in requested_languages(app, languages):
            for device in CONFIG["devices"]:
                folder = out_root / app_name / locale(language)["appStore"] / slot(device)
                label = f"{app_name}/{locale(language)['appStore']}/{slot(device)}"
                files = sorted(path for path in folder.iterdir() if path.is_file()) if folder.is_dir() else []
                images = [path for path in files if path.suffix.lower() in (".png", ".jpg")]
                if not 1 <= len(images) <= 10:
                    problems.append(f"{label}: {len(images)} screenshots (App Store Connect takes 1-10 per slot)")
                for path in files:
                    if path not in images:
                        problems.append(f"{label}/{path.name}: not a PNG or JPEG screenshot")
                        continue
                    if not NAME.match(path.name):
                        problems.append(f"{label}/{path.name}: the name is not NN-id.png")
                    if path.stem not in expected:
                        problems.append(f"{label}/{path.name}: no such scene in appstore/screenshots.json")
                    if path.suffix.lower() == ".jpg" and path.with_suffix(".png").exists():
                        problems.append(f"{label}/{path.name}: both a PNG and a JPEG of this scene")
                    for problem in check_file(path, device):
                        problems.append(f"{label}/{path.name}: {problem}")
                    checked += 1
    report(problems, "Validation")
    if not problems:
        print(f"Validated {checked} screenshots: all meet App Store Connect's rules")
    return problems


def words(values):
    out = []
    for value in values or []:
        out += value.split()
    return out


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check")
    planner = commands.add_parser("plan")
    planner.add_argument("--products", nargs="*", default=["all"])
    planner.add_argument("--languages", nargs="*", default=["all"])
    scenes = commands.add_parser("scenes")
    scenes.add_argument("app")
    languages = commands.add_parser("languages")
    languages.add_argument("app")
    languages.add_argument("--only", nargs="*", default=["all"])
    for name in ("compose", "validate"):
        command = commands.add_parser(name)
        if name == "compose":
            command.add_argument("--raw", type=Path, required=True)
        command.add_argument("--out", type=Path, required=True)
        command.add_argument("--apps", nargs="*", default=None)
        command.add_argument("--languages", nargs="*", default=["all"])
    args = parser.parse_args()
    if args.command == "check":
        problems = report(check_config(), "appstore/screenshots.json")
        if not problems:
            print("appstore/screenshots.json: OK")
        return 1 if problems else 0
    if args.command == "plan":
        return plan(words(args.products), words(args.languages))
    if args.command == "scenes":
        return print_scenes(args.app)
    if args.command == "languages":
        return print_languages(args.app, words(args.only))
    apps = words(args.apps) or [name for name in CONFIG["defaultProducts"] if CONFIG["apps"][name].get("hooks") != "pending"]
    unknown = [name for name in apps if name not in CONFIG["apps"]]
    if unknown:
        sys.exit(f"Unknown apps: {' '.join(unknown)}")
    if args.command == "compose":
        return compose(args.raw.resolve(), args.out.resolve(), apps, words(args.languages))
    return 1 if validate(args.out.resolve(), apps, words(args.languages)) else 0


if __name__ == "__main__":
    sys.exit(main())
