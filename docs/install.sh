#!/bin/bash
# MacSafe installer for macOS.
#
#   curl -fsSL https://gabrielesarria167-ai.github.io/MacSafe/install.sh | bash
#   curl -fsSL https://gabrielesarria167-ai.github.io/MacSafe/install.sh | bash -s -- --uninstall
#
# Installs MacSafe.app, the `macsafe` terminal command and, only if it's missing, Python 3
# (the official python.org installer). Files fetched with curl aren't quarantined, so macOS opens the
# app without the "could not verify" Gatekeeper warning. Running it again updates everything; the
# app's Update button and the `macsafe` command run it with --update.
#
# Options: --uninstall   remove the app, the command and their caches (Python is left alone)
#          --update      update without questions, and reopen the app if it was open
#          --no-python   don't install Python even if it's missing
#          --yes         don't ask questions (skips opening Full Disk Access settings)
# For testing: MACSAFE_ZIP=<local zip>  MACSAFE_DEST=<app folder>  MACSAFE_BIN=<command folder>
#              PYTHON_DRY_RUN=1 (only say what would happen to Python)
set -euo pipefail

REPO="gabrielesarria167-ai/MacSafe"
APP_NAME="MacSafe.app"
ZIP_URL="https://github.com/$REPO/releases/latest/download/MacSafe.zip"
# Before version 1.1 the app was called Storage Monitor and the command `storagemon`.
# Installing or updating replaces them, so nobody ends up with two copies.
OLD_APP="Storage Monitor.app"
OLD_CMD="storagemon"
PY_VERSION="3.14.7"
PY_PKG_URL="https://www.python.org/ftp/python/$PY_VERSION/python-$PY_VERSION-macos11.pkg"
PY_TEAM="Python Software Foundation (BMM5U3QVKW)"   # Developer ID that signs python.org installers
MIN_MACOS=14

BIN_DIR="${MACSAFE_BIN:-$HOME/.local/bin}"
UNINSTALL=0; UPDATE=0; INSTALL_PY=1; ASK=1
for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    --update) UPDATE=1; ASK=0; INSTALL_PY=0 ;;
    --no-python) INSTALL_PY=0 ;;
    --yes|-y) ASK=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
[[ -r /dev/tty ]] || ASK=0

bold=$'\033[1m'; dim=$'\033[2m'; red=$'\033[31m'; green=$'\033[32m'; blue=$'\033[34m'; off=$'\033[0m'
[[ -t 1 ]] || { bold=""; dim=""; red=""; green=""; blue=""; off=""; }
step() { printf '%s→%s %s\n' "$blue" "$off" "$*"; }
ok()   { printf '%s✓%s %s\n' "$green" "$off" "$*"; }
note() { printf '  %s%s%s\n' "$dim" "$*" "$off"; }
die()  { printf '%s✗ %s%s\n' "$red" "$*" "$off" >&2; exit 1; }
ask()  {  # ask "question" → 0 for yes (default yes)
  [[ $ASK == 1 ]] || return 1
  local reply; printf '%s [Y/n] ' "$1"; read -r reply </dev/tty || return 1
  [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── uninstall ────────────────────────────────────────────────────────────────
TESTING=0; [[ -n "${MACSAFE_DEST:-}" ]] && TESTING=1   # a test install never touches the real one
WAS_RUNNING=0
quit_app() {  # quits MacSafe (or the old Storage Monitor) and remembers whether it was open
  [[ $TESTING == 1 ]] && return 0
  local pat
  for pat in "$APP_NAME/Contents/MacOS/MacSafe" "$OLD_APP/Contents/MacOS/StorageMonitor"; do
    if pgrep -f "$pat" >/dev/null 2>&1; then
      WAS_RUNNING=1
      pkill -f "$pat" 2>/dev/null || true
    fi
  done
  [[ $WAS_RUNNING == 1 ]] && sleep 1
  return 0
}
old_copies() {  # everything the app left behind under its old name
  printf '%s\n' "/Applications/$OLD_APP" "$HOME/Applications/$OLD_APP" "$BIN_DIR/$OLD_CMD" \
    "$HOME/Library/Caches/StorageMonitor" "$HOME/Library/Logs/StorageMonitor"
}

if [[ $UNINSTALL == 1 ]]; then
  quit_app
  if [[ $TESTING == 1 ]]; then
    targets=("$MACSAFE_DEST/$APP_NAME" "$BIN_DIR/macsafe")
  else
    targets=("/Applications/$APP_NAME" "$HOME/Applications/$APP_NAME" "$BIN_DIR/macsafe"
             "$HOME/Library/Caches/MacSafe" "$HOME/Library/Logs/MacSafe")
    while IFS= read -r p; do targets+=("$p"); done < <(old_copies)
  fi
  for p in "${targets[@]}"; do
    [[ -n "$p" && -e "$p" ]] || continue
    rm -rf "$p" && ok "Removed $p"
  done
  ok "MacSafe is uninstalled. (Python was left in place.)"
  exit 0
fi

if [[ $UPDATE == 1 ]]; then
  printf '\n%sUpdating MacSafe%s\n\n' "$bold" "$off"
else
  printf '\n%sMacSafe installer%s\n\n' "$bold" "$off"
fi

# ── 1. this Mac ──────────────────────────────────────────────────────────────
[[ "$(uname -s)" == Darwin ]] || die "MacSafe only runs on macOS."
macos="$(sw_vers -productVersion)"
(( ${macos%%.*} >= MIN_MACOS )) || die "MacSafe needs macOS $MIN_MACOS or later (this Mac has $macos)."
ok "macOS $macos on $(uname -m)"

# ── 2. Python 3 ──────────────────────────────────────────────────────────────
python_ok() { "$1" -c 'import sys, curses; sys.exit(sys.version_info < (3, 9))' >/dev/null 2>&1; }
find_python() {  # same places the app looks (MacApp/Sources/Engine.swift)
  local c
  for c in /Library/Frameworks/Python.framework/Versions/Current/bin/python3 /opt/homebrew/bin/python3 \
           /usr/local/bin/python3 /usr/bin/python3; do
    [[ -x "$c" ]] || continue
    # /usr/bin/python3 is only a stub that pops up Apple's installer until the Command Line Tools exist
    [[ "$c" == /usr/bin/python3 ]] && ! xcode-select -p >/dev/null 2>&1 && continue
    python_ok "$c" && { echo "$c"; return 0; }
  done
  return 1
}

if PY="$(find_python)"; then
  ok "Python $("$PY" -c 'import platform; print(platform.python_version())') ($PY)"
elif [[ $INSTALL_PY == 0 ]]; then
  die "Python 3.9 or later is needed. Install it from https://www.python.org/downloads/macos/ and run this again."
elif [[ "${PYTHON_DRY_RUN:-}" == 1 ]]; then
  step "Would install Python $PY_VERSION from $PY_PKG_URL (dry run)"
  PY="/Library/Frameworks/Python.framework/Versions/Current/bin/python3"
else
  step "Python 3 isn't installed. Downloading the official installer from python.org (about 80 MB)…"
  curl -fL --progress-bar -o "$TMP/python.pkg" "$PY_PKG_URL" || die "Couldn't download Python."
  sig="$(pkgutil --check-signature "$TMP/python.pkg" 2>&1 || true)"
  grep -q "Developer ID Installer: $PY_TEAM" <<<"$sig" || die "The Python installer's signature didn't check out. Nothing was installed."
  ok "Installer signed by the $PY_TEAM"
  step "Installing Python $PY_VERSION. macOS asks for your password because it installs for all users."
  sudo installer -pkg "$TMP/python.pkg" -target / >/dev/null || die "Python didn't install."
  PY="$(find_python)" || die "Python was installed but can't be found. Open a new Terminal window and run this again."
  ok "Python $PY_VERSION installed"
fi

# ── 3. the app ───────────────────────────────────────────────────────────────
if [[ -n "${MACSAFE_DEST:-}" ]]; then
  DEST="$MACSAFE_DEST"
elif [[ -w /Applications ]]; then
  DEST="/Applications"
else
  DEST="$HOME/Applications"
fi
mkdir -p "$DEST"

if [[ -n "${MACSAFE_ZIP:-}" ]]; then
  cp "$MACSAFE_ZIP" "$TMP/app.zip"
  [[ -f "$MACSAFE_ZIP.sha256" ]] && cp "$MACSAFE_ZIP.sha256" "$TMP/app.zip.sha256"
else
  step "Downloading MacSafe…"
  curl -fL --progress-bar -o "$TMP/app.zip" "$ZIP_URL" || die "Couldn't download $ZIP_URL"
  curl -fsL -o "$TMP/app.zip.sha256" "$ZIP_URL.sha256" || die "Couldn't download the checksum for the app."
fi
if [[ -f "$TMP/app.zip.sha256" ]]; then
  want="$(awk '{print $1}' "$TMP/app.zip.sha256")"
  have="$(shasum -a 256 "$TMP/app.zip" | awk '{print $1}')"
  [[ "$want" == "$have" ]] || die "The download is damaged (checksum mismatch). Nothing was installed."
  ok "Download verified"
fi

ditto -x -k "$TMP/app.zip" "$TMP/unzipped"
[[ -d "$TMP/unzipped/$APP_NAME" ]] || die "The download doesn't contain $APP_NAME."
quit_app
rm -rf "${DEST:?}/$APP_NAME"
ditto "$TMP/unzipped/$APP_NAME" "$DEST/$APP_NAME"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true
# Same path, new bundle: macOS keeps showing the old icon until the app is re-registered.
touch "$DEST/$APP_NAME"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST/$APP_NAME" >/dev/null 2>&1 || true
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DEST/$APP_NAME/Contents/Info.plist" 2>/dev/null || true)"
ok "Installed MacSafe ${VERSION:+$VERSION }in $DEST"

if [[ $TESTING == 0 ]]; then
  removed=0
  while IFS= read -r p; do
    [[ -e "$p" ]] || continue
    rm -rf "$p" && removed=1
  done < <(old_copies)
  [[ $removed == 1 ]] && ok "Removed the old Storage Monitor app and storagemon command"
fi

# ── 4. the terminal command ──────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/macsafe" <<SH
#!/bin/bash
# MacSafe terminal dashboard (installed by install.sh)
PY="$PY"
[[ -x "\$PY" ]] || PY="\$(command -v python3)"
exec "\$PY" "$DEST/$APP_NAME/Contents/Resources/smcli.py" "\$@"
SH
chmod +x "$BIN_DIR/macsafe"
ok "Installed the macsafe command ($BIN_DIR/macsafe)"

# A test install (MACSAFE_DEST) leaves your shell settings alone.
if [[ $TESTING == 0 ]]; then
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      rc="$HOME/.zshrc"; [[ "${SHELL:-}" == */bash ]] && rc="$HOME/.bash_profile"
      if ! grep -qs -e "# added by MacSafe" -e "# added by Storage Monitor" "$rc"; then
        printf '\nexport PATH="%s:$PATH"  # added by MacSafe\n' "$BIN_DIR" >> "$rc"
        ok "Added $BIN_DIR to your PATH in $rc"
      fi
      note "Open a new Terminal window before running macsafe."
      ;;
  esac
fi

# ── 5. done ──────────────────────────────────────────────────────────────────
if [[ $UPDATE == 1 ]]; then
  printf '\n%sMacSafe is up to date.%s\n' "$bold$green" "$off"
  [[ $WAS_RUNNING == 1 ]] && { open "$DEST/$APP_NAME" || true; }
  exit 0
fi

printf '\n%sAll set.%s Open MacSafe from Launchpad or Spotlight, or type %smacsafe%s in Terminal.\n\n' \
  "$bold$green" "$off" "$bold" "$off"
note "For complete results, give MacSafe (and Terminal, for the macsafe command) Full Disk Access:"
note "System Settings › Privacy & Security › Full Disk Access."
if ask "Open Full Disk Access settings now?"; then
  # A new app isn't in that list yet: show it in Finder too, so it can be dragged in.
  open -R "$DEST/$APP_NAME" || true
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" || true
  note "MacSafe won't be listed yet: drag it from the Finder window into the list (or click + and"
  note "choose it), then turn it on. Do the same for Terminal to use the macsafe command."
fi
if [[ $WAS_RUNNING == 1 ]]; then
  open "$DEST/$APP_NAME" || true
elif [[ $TESTING == 0 ]] && ask "Open MacSafe now?"; then
  open "$DEST/$APP_NAME" || true
fi
