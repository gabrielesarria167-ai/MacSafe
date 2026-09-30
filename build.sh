#!/bin/bash
# Builds "MacSafe.app".
#   ./build.sh             build for this Mac into build/
#   ./build.sh --install   … and put it in /Applications, plus the `macsafe` command in ~/.local/bin
#   ./build.sh --release   universal (Apple Silicon + Intel) build: dist/MacSafe.dmg + MacSafe.zip for a GitHub Release
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
MODE="${1:-}"
APP="$ROOT/build/MacSafe.app"
ICONSET="$ROOT/build/AppIcon.iconset"
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" MacApp/Info.plist)"

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

compile() {  # compile <arch> <output>
  swiftc -O -parse-as-library -swift-version 5 -target "$1-apple-macos14.0" MacApp/Sources/*.swift -o "$2"
}

if [[ "$MODE" == "--release" ]]; then
  echo "→ compiling (arm64 + x86_64)"
  compile arm64 "$ROOT/build/MacSafe-arm64"
  compile x86_64 "$ROOT/build/MacSafe-x86_64"
  lipo -create "$ROOT/build/MacSafe-arm64" "$ROOT/build/MacSafe-x86_64" \
    -output "$APP/Contents/MacOS/MacSafe"
  rm -f "$ROOT/build/MacSafe-arm64" "$ROOT/build/MacSafe-x86_64"
else
  echo "→ compiling"
  compile "$(uname -m)" "$APP/Contents/MacOS/MacSafe"
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
cp engine.py smcli.py MacApp/macsafe.command "$APP/Contents/Resources/"
# Ad-hoc signature (required on Apple Silicon). It isn't notarized, so install.sh fetches it with curl,
# which doesn't quarantine it; a browser download needs System Settings › Privacy & Security › Open Anyway.
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP ($VERSION)"

if [[ "$MODE" == "--release" ]]; then
  DIST="$ROOT/dist"
  rm -rf "$DIST" && mkdir -p "$DIST"
  # The zip is what install.sh and the Update button download; people downloading in a browser get
  # the disk image, whose window shows them to drag the app into Applications.
  ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "$DIST/MacSafe.zip"

  echo "→ disk image"
  VOLNAME="MacSafe installer"   # the window title; the Finder script below names it too
  VOL="/Volumes/$VOLNAME"
  [[ -d "$VOL" ]] && hdiutil detach "$VOL" -quiet -force
  STAGE="$ROOT/build/dmg"
  rm -rf "$STAGE" && mkdir -p "$STAGE/.background"
  ditto "$APP" "$STAGE/MacSafe.app"
  ln -s /Applications "$STAGE/Applications"
  swift MacApp/make_dmg_background.swift "$ROOT/build/dmg_bg.png" 1
  swift MacApp/make_dmg_background.swift "$ROOT/build/dmg_bg@2x.png" 2
  tiffutil -cathidpicheck "$ROOT/build/dmg_bg.png" "$ROOT/build/dmg_bg@2x.png" -out "$ROOT/build/dmg_bg.tiff" 2>/dev/null
  tiffutil -lzw "$ROOT/build/dmg_bg.tiff" -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
  cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
  rm -f "$ROOT/build/rw.dmg"
  hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$ROOT/build/rw.dmg"
  hdiutil attach -quiet -readwrite -noverify -noautoopen "$ROOT/build/rw.dmg"
  SetFile -a C "$VOL"
  # Window layout is stored by Finder, so it has to be asked to make it (needs Automation access for
  # Terminal the first time). Without it the image still works, just with Finder's default layout.
  if ! osascript <<'OSA' >/dev/null
tell application "Finder"
  tell disk "MacSafe installer"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 800, 520}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "MacSafe.app" of container window to {160, 200}
    set position of item "Applications" of container window to {440, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
  then
    echo "  (couldn't lay out the window: allow Terminal to control Finder, then build again)"
  fi
  chmod -Rf go-w "$VOL" 2>/dev/null || true
  sync
  hdiutil detach "$VOL" -quiet || hdiutil detach "$VOL" -quiet -force
  hdiutil convert -quiet "$ROOT/build/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DIST/MacSafe.dmg"
  rm -f "$ROOT/build/rw.dmg"

  (cd "$DIST" && shasum -a 256 MacSafe.zip > MacSafe.zip.sha256 && shasum -a 256 MacSafe.dmg > MacSafe.dmg.sha256)
  echo "Release $VERSION:"
  echo "  $DIST/MacSafe.dmg   (browser download)"
  echo "  $DIST/MacSafe.zip   (install.sh and the Update button)"
  echo "Upload them with their .sha256 files to a GitHub Release, e.g.:"
  echo "  gh release create v$VERSION dist/* --title \"MacSafe $VERSION\""
fi

if [[ "$MODE" == "--install" ]]; then
  DEST="/Applications/MacSafe.app"
  # Earlier install locations, including the app's name before it became MacSafe.
  OLD=("$HOME/Applications/MacSafe.app" "/Applications/Storage Monitor.app" "$HOME/Applications/Storage Monitor.app")
  mkdir -p "$HOME/.local/bin"
  pkill -f "MacSafe.app/Contents/MacOS/MacSafe" 2>/dev/null && sleep 1 || true
  pkill -f "Storage Monitor.app/Contents/MacOS/StorageMonitor" 2>/dev/null && sleep 1 || true
  rm -rf "$DEST" "${OLD[@]}" "$HOME/.local/bin/storagemon"
  ditto "$APP" "$DEST"
  cat > "$HOME/.local/bin/macsafe" <<SH
#!/bin/bash
# MacSafe terminal dashboard (installed by $ROOT/build.sh)
exec /usr/bin/env python3 "$DEST/Contents/Resources/smcli.py" "\$@"
SH
  chmod +x "$HOME/.local/bin/macsafe"
  echo "Installed $DEST"
  echo "Installed ~/.local/bin/macsafe"
fi
