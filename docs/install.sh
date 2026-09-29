#!/bin/bash
# Storage Monitor installer for macOS.
#
#   curl -fsSL https://gabrielesarria167-ai.github.io/MacSafe/install.sh | bash
#   curl -fsSL https://gabrielesarria167-ai.github.io/MacSafe/install.sh | bash -s -- --uninstall
#
# Installs Storage Monitor.app, the `storagemon` terminal command and, only if it's missing, Python 3
# (the official python.org installer). Files fetched with curl aren't quarantined, so macOS opens the
# app without the "could not verify" Gatekeeper warning.
#
# Options: --uninstall   remove the app, the command and their caches (Python is left alone)
#          --no-python   don't install Python even if it's missing
#          --yes         don't ask questions (skips opening Full Disk Access settings)
# For testing: STORAGEMON_ZIP=<local zip>  STORAGEMON_DEST=<app folder>  STORAGEMON_BIN=<command folder>
#              PYTHON_DRY_RUN=1 (only say what would happen to Python)
set -euo pipefail

REPO="gabrielesarria167-ai/MacSafe"
APP_NAME="Storage Monitor.app"
ZIP_URL="https://github.com/$REPO/releases/latest/download/StorageMonitor.zip"
PY_VERSION="3.14.7"
PY_PKG_URL="https://www.python.org/ftp/python/$PY_VERSION/python-$PY_VERSION-macos11.pkg"
PY_TEAM="Python Software Foundation (BMM5U3QVKW)"   # Developer ID that signs python.org installers
MIN_MACOS=14

BIN_DIR="${STORAGEMON_BIN:-$HOME/.local/bin}"
UNINSTALL=0; INSTALL_PY=1; ASK=1
for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
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
TESTING=0; [[ -n "${STORAGEMON_DEST:-}" ]] && TESTING=1   # a test install never touches the real one
quit_app() { [[ $TESTING == 1 ]] || { pkill -f "$APP_NAME/Contents/MacOS/StorageMonitor" 2>/dev/null && sleep 1; } || true; }

if [[ $UNINSTALL == 1 ]]; then
  quit_app
  if [[ $TESTING == 1 ]]; then
    targets=("$STORAGEMON_DEST/$APP_NAME" "$BIN_DIR/storagemon")
  else
    targets=("/Applications/$APP_NAME" "$HOME/Applications/$APP_NAME" "$BIN_DIR/storagemon"
             "$HOME/Library/Caches/StorageMonitor" "$HOME/Library/Logs/StorageMonitor")
  fi
  for p in "${targets[@]}"; do
    [[ -n "$p" && -e "$p" ]] || continue
    rm -rf "$p" && ok "Removed $p"
  done
  ok "Storage Monitor is uninstalled. (Python was left in place.)"
  exit 0
fi

printf '\n%sStorage Monitor installer%s\n\n' "$bold" "$off"

# ── 1. this Mac ──────────────────────────────────────────────────────────────
[[ "$(uname -s)" == Darwin ]] || die "Storage Monitor only runs on macOS."
macos="$(sw_vers -productVersion)"
(( ${macos%%.*} >= MIN_MACOS )) || die "Storage Monitor needs macOS $MIN_MACOS or later (this Mac has $macos)."
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
if [[ -n "${STORAGEMON_DEST:-}" ]]; then
  DEST="$STORAGEMON_DEST"
elif [[ -w /Applications ]]; then
  DEST="/Applications"
else
  DEST="$HOME/Applications"
fi
mkdir -p "$DEST"

if [[ -n "${STORAGEMON_ZIP:-}" ]]; then
  cp "$STORAGEMON_ZIP" "$TMP/app.zip"
  [[ -f "$STORAGEMON_ZIP.sha256" ]] && cp "$STORAGEMON_ZIP.sha256" "$TMP/app.zip.sha256"
else
  step "Downloading Storage Monitor…"
  curl -fL --progress-bar -o "$TMP/app.zip" "$ZIP_URL" || die "Couldn't download $ZIP_URL"
  curl -fsL -o "$TMP/app.zip.sha256" "$ZIP_URL.sha256" || die "Couldn't download the checksum for the app."
fi
if [[ -f "$TMP/app.zip.sha256" ]]; then
  want="$(awk '{print $1}' "$TMP/app.zip.sha256")"
  have="$(shasum -a 256 "$TMP/app.zip" | awk '{print $1}')"
  [[ "$want" == "$have" ]] || die "The download is damaged (checksum mismatch). Nothing was installed."
  ok "Download verified"
fi

quit_app
ditto -x -k "$TMP/app.zip" "$TMP/unzipped"
[[ -d "$TMP/unzipped/$APP_NAME" ]] || die "The download doesn't contain $APP_NAME."
rm -rf "${DEST:?}/$APP_NAME"
ditto "$TMP/unzipped/$APP_NAME" "$DEST/$APP_NAME"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true
ok "Installed $DEST/$APP_NAME"

# ── 4. the terminal command ──────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/storagemon" <<SH
#!/bin/bash
# Storage Monitor terminal dashboard (installed by install.sh)
PY="$PY"
[[ -x "\$PY" ]] || PY="\$(command -v python3)"
exec "\$PY" "$DEST/$APP_NAME/Contents/Resources/smcli.py" "\$@"
SH
chmod +x "$BIN_DIR/storagemon"
ok "Installed the storagemon command ($BIN_DIR/storagemon)"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    rc="$HOME/.zshrc"; [[ "${SHELL:-}" == */bash ]] && rc="$HOME/.bash_profile"
    if ! grep -qs "# added by Storage Monitor" "$rc"; then
      printf '\nexport PATH="%s:$PATH"  # added by Storage Monitor\n' "$BIN_DIR" >> "$rc"
      ok "Added $BIN_DIR to your PATH in $rc"
    fi
    note "Open a new Terminal window before running storagemon."
    ;;
esac

# ── 5. done ──────────────────────────────────────────────────────────────────
printf '\n%sAll set.%s Open Storage Monitor from Launchpad or Spotlight, or type %sstoragemon%s in Terminal.\n\n' \
  "$bold$green" "$off" "$bold" "$off"
note "For complete results, give Storage Monitor (and Terminal, for storagemon) Full Disk Access:"
note "System Settings › Privacy & Security › Full Disk Access."
if ask "Open Full Disk Access settings now?"; then
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" || true
fi
if [[ -z "${STORAGEMON_DEST:-}" ]] && ask "Open Storage Monitor now?"; then
  open "$DEST/$APP_NAME" || true
fi
