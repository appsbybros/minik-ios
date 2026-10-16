#!/usr/bin/env bash
# Builds the Xcode project of Minik Maze for iOS, on macOS (the TestFlight and Compile Check workflows run it):
#
#   bash Maze/build-ios-project.sh <Apple team ID> <build number>
#
# 1. Downloads Godot 4.7.2 (the macOS editor and the export templates) and checks them against Godot's
#    published SHA-512 sums.
# 2. Builds the App Store library (Maze/native) with godot-cpp godot-4.5-stable.
# 3. Lets Godot import Maze/game and export build/maze/MinikMaze.xcodeproj ("project only": the workflow archives
#    and signs it with xcodebuild, like the other apps).
set -euo pipefail

TEAM_ID="${1:?Usage: build-ios-project.sh <Apple team ID> <build number>}"
BUILD_NUMBER="${2:?Usage: build-ios-project.sh <Apple team ID> <build number>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="$ROOT/Maze/game"
NATIVE="$ROOT/Maze/native"
OUT="$ROOT/build/maze"
TOOLS="${MAZE_TOOLS:-$HOME/.cache/minik-maze}"

GODOT_VERSION="4.7.2"
GODOT_ZIP="Godot_v${GODOT_VERSION}-stable_macos.universal.zip"
GODOT_ZIP_SHA512="38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca"
TEMPLATES_TPZ="Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
TEMPLATES_SHA512="ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"
GODOT_CPP_TAG="godot-4.5-stable"
GODOT_CPP_COMMIT="e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77"
SCONS_VERSION="4.9.1"

mkdir -p "$TOOLS"

fetch() { # file sha512
  local file="$1" sum="$2"
  if [ ! -f "$TOOLS/$file" ]; then
    echo "Downloading $file"
    curl -fsSL --retry 3 -o "$TOOLS/$file.part" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/$file"
    mv "$TOOLS/$file.part" "$TOOLS/$file"
  fi
  if [ "$(shasum -a 512 "$TOOLS/$file" | cut -d' ' -f1)" != "$sum" ]; then
    rm -f "$TOOLS/$file"
    echo "error: $file does not match Godot's published SHA-512 sum"
    exit 1
  fi
}

# 1. Godot and its iOS export template.
fetch "$GODOT_ZIP" "$GODOT_ZIP_SHA512"
fetch "$TEMPLATES_TPZ" "$TEMPLATES_SHA512"
GODOT_APP="$TOOLS/Godot-$GODOT_VERSION/Godot.app"
if [ ! -x "$GODOT_APP/Contents/MacOS/Godot" ]; then
  rm -rf "$TOOLS/Godot-$GODOT_VERSION"
  unzip -q "$TOOLS/$GODOT_ZIP" -d "$TOOLS/Godot-$GODOT_VERSION"
fi
GODOT="$GODOT_APP/Contents/MacOS/Godot"
TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable"
if [ ! -f "$TEMPLATES/ios.zip" ]; then
  mkdir -p "$TEMPLATES"
  unzip -q -j -o "$TOOLS/$TEMPLATES_TPZ" templates/ios.zip templates/version.txt -d "$TEMPLATES"
fi
"$GODOT" --version

# 2. The App Store library.
if [ ! -d "$NATIVE/godot-cpp/.git" ]; then
  git clone -q --depth 1 --branch "$GODOT_CPP_TAG" https://github.com/godotengine/godot-cpp "$NATIVE/godot-cpp"
fi
if [ "$(git -C "$NATIVE/godot-cpp" rev-parse HEAD)" != "$GODOT_CPP_COMMIT" ]; then
  echo "error: Maze/native/godot-cpp is not $GODOT_CPP_TAG ($GODOT_CPP_COMMIT)"
  exit 1
fi
# A cached venv breaks when the runner's Python changes; it is made again then.
if ! "$TOOLS/scons-$SCONS_VERSION/bin/python" -c "import SCons" >/dev/null 2>&1; then
  rm -rf "$TOOLS/scons-$SCONS_VERSION"
  python3 -m venv "$TOOLS/scons-$SCONS_VERSION"
  "$TOOLS/scons-$SCONS_VERSION/bin/pip" install --quiet "scons==$SCONS_VERSION"
fi
# The selected Xcode's toolchain (godot-cpp assumes /Applications/Xcode.app otherwise).
(cd "$NATIVE" && "$TOOLS/scons-$SCONS_VERSION/bin/scons" platform=ios arch=arm64 target=template_release \
  ios_min_version=15.0 IOS_TOOLCHAIN_PATH="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
  -j"$(sysctl -n hw.ncpu)")
mkdir -p "$GAME/ios/bin"
cp "$NATIVE/bin/libmazestorekit.ios.template_release.arm64.dylib" "$GAME/ios/bin/"

# 3. Import and export. The team ID and build number go into the preset for this export only.
PRESETS="$GAME/export_presets.cfg"
cp "$PRESETS" "$PRESETS.committed"
trap 'mv "$PRESETS.committed" "$PRESETS"' EXIT
python3 - "$PRESETS" "$TEAM_ID" "$BUILD_NUMBER" <<'PY'
import re
import sys

path, team, build = sys.argv[1:]
text = open(path, encoding="utf-8").read()
for key, value in (("application/app_store_team_id", team), ("application/version", build)):
    text, count = re.subn(r'^%s=".*"$' % re.escape(key), '%s="%s"' % (key, value), text, flags=re.M)
    if count != 1:
        sys.exit("export_presets.cfg has no single %s" % key)
open(path, "w", encoding="utf-8").write(text)
PY

rm -rf "$OUT"
mkdir -p "$OUT"
echo "Importing Maze/game"
"$GODOT" --headless --path "$GAME" --import
echo "Exporting the Xcode project"
"$GODOT" --headless --path "$GAME" --export-release "iOS" "$OUT/MinikMaze.ipa"

for expected in "$OUT/MinikMaze.xcodeproj/project.pbxproj" "$OUT/MinikMaze.pck"; do
  if [ ! -e "$expected" ]; then
    echo "error: Godot did not write ${expected#$ROOT/}"
    exit 1
  fi
done
if [ -z "$(find "$OUT" -maxdepth 6 -name 'libmazestorekit*.framework' -print -quit)" ]; then
  echo "error: the App Store library (ios/maze_storekit.gdextension) is not in the exported project"
  exit 1
fi
echo "Exported build/maze/MinikMaze.xcodeproj (build $BUILD_NUMBER)"
