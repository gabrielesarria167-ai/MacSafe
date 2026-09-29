#!/bin/bash
# Builds "Storage Monitor.app".
#   ./build.sh             build for this Mac into build/
#   ./build.sh --install   … and put it in /Applications, plus the `storagemon` command in ~/.local/bin
#   ./build.sh --release   universal (Apple Silicon + Intel) build, zipped into dist/ for a GitHub Release
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
MODE="${1:-}"
APP="$ROOT/build/Storage Monitor.app"
ICONSET="$ROOT/build/AppIcon.iconset"
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" MacApp/Info.plist)"

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

compile() {  # compile <arch> <output>
  swiftc -O -parse-as-library -swift-version 5 -target "$1-apple-macos14.0" MacApp/Sources/*.swift -o "$2"
}

if [[ "$MODE" == "--release" ]]; then
  echo "→ compiling (arm64 + x86_64)"
  compile arm64 "$ROOT/build/StorageMonitor-arm64"
  compile x86_64 "$ROOT/build/StorageMonitor-x86_64"
  lipo -create "$ROOT/build/StorageMonitor-arm64" "$ROOT/build/StorageMonitor-x86_64" \
    -output "$APP/Contents/MacOS/StorageMonitor"
  rm -f "$ROOT/build/StorageMonitor-arm64" "$ROOT/build/StorageMonitor-x86_64"
else
  echo "→ compiling"
  compile "$(uname -m)" "$APP/Contents/MacOS/StorageMonitor"
fi

echo "→ icon"
swift MacApp/make_icon.swift "$ROOT/build/icon_1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ROOT/build/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ROOT/build/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ bundle"
cp MacApp/Info.plist "$APP/Contents/Info.plist"
cp engine.py smcli.py MacApp/storagemon.command "$APP/Contents/Resources/"
# Ad-hoc signature (required on Apple Silicon). It isn't notarized, so install.sh fetches it with curl,
# which doesn't quarantine it; a browser download needs System Settings › Privacy & Security › Open Anyway.
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP ($VERSION)"

if [[ "$MODE" == "--release" ]]; then
  DIST="$ROOT/dist"
  rm -rf "$DIST" && mkdir -p "$DIST"
  ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "$DIST/StorageMonitor.zip"
  (cd "$DIST" && shasum -a 256 StorageMonitor.zip > StorageMonitor.zip.sha256)
  echo "Release $VERSION:"
  echo "  $DIST/StorageMonitor.zip"
  echo "  $DIST/StorageMonitor.zip.sha256"
  echo "Upload both to a GitHub Release, e.g.:"
  echo "  gh release create v$VERSION dist/StorageMonitor.zip dist/StorageMonitor.zip.sha256 --title \"Storage Monitor $VERSION\""
fi

if [[ "$MODE" == "--install" ]]; then
  DEST="/Applications/Storage Monitor.app"
  OLD="$HOME/Applications/Storage Monitor.app"   # earlier install location
  mkdir -p "$HOME/.local/bin"
  pkill -f "Storage Monitor.app/Contents/MacOS/StorageMonitor" 2>/dev/null && sleep 1 || true
  rm -rf "$DEST" "$OLD"
  ditto "$APP" "$DEST"
  cat > "$HOME/.local/bin/storagemon" <<SH
#!/bin/bash
# Storage Monitor terminal dashboard (installed by $ROOT/build.sh)
exec /usr/bin/env python3 "$DEST/Contents/Resources/smcli.py" "\$@"
SH
  chmod +x "$HOME/.local/bin/storagemon"
  echo "Installed $DEST"
  echo "Installed ~/.local/bin/storagemon"
fi
