"""App Store captures for apps whose screens are a bundled web page (Bounce).

The Simulator never finished Bounce: twice its runner was lost ("The hosted runner
lost communication with the server") with no log. The page is the whole app, so
this script draws it with WebKit, Safari's engine (on macOS also the system's
rounded font), at each device's safe-area size, and lays it on the app's own
background around it, as RetroPongView shows it. The scenes, languages, waits and
orientations come from appstore/screenshots.json.

  python Scripts/appstore-web-scenes.py <App> --out build/appstore-raw [--languages en he] [--browser webkit]

Writes <out>/<App>/<lang>/<iphone|ipad>/<id>.png, as the Simulator captures are.
"""
import argparse
import asyncio
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / "appstore/screenshots.json").read_text(encoding="utf-8"))

# Points, scale and safe-area insets (top, right, bottom, left) of the 6.9-inch iPhone
# and the 13-inch iPad Pro, the devices the Simulator captures use.
DEVICES = {
    "iphone": {"size": (440, 956), "scale": 3,
               "portrait": (62, 0, 34, 0), "landscape": (0, 62, 21, 62)},
    "ipad": {"size": (1032, 1376), "scale": 2,
             "portrait": (24, 0, 20, 0), "landscape": (24, 0, 20, 0)},
}
# RetroPongView's background and the user agent it gives WKWebView.
BACKGROUND = (17, 24, 43)
USER_AGENT = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
              "(KHTML, like Gecko) Mobile/15E148 MinikNative/iOS MinikNativeInsets/1 MinikNativeImmersive/1")


async def capture(app_name, out, languages, browser_name):
    from PIL import Image
    from playwright.async_api import async_playwright

    app = CONFIG["apps"][app_name]
    page_root = ROOT / app["web"]
    prefix = app["web-scene-prefix"]
    wanted = [language for language in app["languages"] if not languages or language in languages]
    missing = 0
    async with async_playwright() as playwright:
        browser = await getattr(playwright, browser_name).launch()
        for language in wanted:
            for device, spec in DEVICES.items():
                for scene in app["scenes"]:
                    orientation = app.get("orientation", {}).get(device, "portrait")
                    width, height = spec["size"] if orientation == "portrait" else spec["size"][::-1]
                    top, right, bottom, left = spec[orientation]
                    target = out / app_name / language / device / f"{scene['id']}.png"
                    target.parent.mkdir(parents=True, exist_ok=True)
                    context = await browser.new_context(
                        viewport={"width": width - left - right, "height": height - top - bottom},
                        device_scale_factor=spec["scale"], is_mobile=browser_name != "firefox",
                        has_touch=True, locale=language, user_agent=USER_AGENT)
                    bootstrap = {"language": language, "state": {}, "paused": False,
                                 "canExit": True, "monetization": False, "parents": True}
                    name = scene["scene"].removeprefix(prefix)
                    await context.add_init_script(
                        f"window.__minikRetroConfig={json.dumps(bootstrap)};"
                        f"window.MinikScreenshotScene={json.dumps(name)};")
                    page = await context.new_page()
                    errors = []
                    page.on("pageerror", lambda error: errors.append(str(error)))
                    try:
                        await page.goto((page_root / "index.html").as_uri())
                        await page.wait_for_timeout(scene.get("wait", 8) * 1000)
                        shot = target.with_suffix(".page.png")
                        await page.screenshot(path=str(shot))
                        scale = spec["scale"]
                        canvas = Image.new("RGB", (width * scale, height * scale), BACKGROUND)
                        with Image.open(shot) as drawn:
                            canvas.paste(drawn.convert("RGB"), (left * scale, top * scale))
                        canvas.save(target)
                        shot.unlink()
                        print(f"Captured {app_name} {language} {device} {scene['id']}")
                    except Exception as error:  # One scene failing must not end the others.
                        missing += 1
                        print(f"::warning::No capture for {app_name} {language} {device} {scene['id']}: {error}")
                    for error in errors[:3]:
                        print(f"::warning::{app_name} {language} {device} {scene['id']}: page error: {error}")
                    await context.close()
        await browser.close()
    print(f"Missing captures: {missing}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("apps", nargs="+")
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--languages", nargs="*", default=[])
    parser.add_argument("--browser", default="webkit", choices=["webkit", "chromium", "firefox"])
    args = parser.parse_args()
    languages = [] if args.languages in ([], ["all"]) else args.languages
    for name in args.apps:
        if "web" not in CONFIG["apps"].get(name, {}):
            sys.exit(f"{name} is not a web app in appstore/screenshots.json")
        asyncio.run(capture(name, args.out, languages, args.browser))
    return 0


if __name__ == "__main__":
    sys.exit(main())
