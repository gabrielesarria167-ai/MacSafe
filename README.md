# Storage Monitor

See what's filling up your Mac and clean it up on the spot. Two front-ends share one engine:

| | How to open | Best for |
|---|---|---|
| **Mac app** | `/Applications/Storage Monitor.app` (Spotlight: "Storage Monitor") | Browsing, sorting, bulk cleanup |
| **Terminal dashboard** | `storagemon` | Quick check without leaving the terminal |

## Install

Paste into Terminal:

```sh
curl -fsSL https://gabrielesarria167-ai.github.io/MacSafe/install.sh | bash
```

It installs the app into Applications, the `storagemon` command into `~/.local/bin`, and Python 3
(the official python.org installer, signature-checked) only if your Mac doesn't have it. Files fetched
with curl aren't quarantined, so macOS opens the app without the "could not verify" warning.
Run it again to update. Requires macOS 14 or later, Apple Silicon or Intel.

* **Regular download:** [StorageMonitor.zip](https://github.com/gabrielesarria167-ai/MacSafe/releases/latest/download/StorageMonitor.zip).
  The app isn't notarized, so the first launch needs System Settings › Privacy & Security › **Open Anyway**.
* **Uninstall:** `curl -fsSL https://gabrielesarria167-ai.github.io/MacSafe/install.sh | bash -s -- --uninstall`
  (Python is left in place).
* **Full Disk Access:** for complete results, turn it on for Storage Monitor (and Terminal, for
  `storagemon`) in System Settings › Privacy & Security › Full Disk Access.

The download page is [gabrielesarria167-ai.github.io/MacSafe](https://gabrielesarria167-ai.github.io/MacSafe/).

## Using it

Both open instantly with the last scan (saved in `~/Library/Caches/StorageMonitor/snapshot.json`)
and rescan in the background when it's older than 15 minutes. `storagemon --report` prints a
summary and exits; `storagemon --app` opens the Mac app; `storagemon --no-mouse` leaves mouse
clicks to the terminal (for selecting text).

### Views
Overview · Explorer (drill into folders) · Large files · Unused (not opened/changed in N months) ·
Duplicates (byte-for-byte) · Caches (safe-to-clear vs review-first) · Clutter (old downloads,
installers, node_modules/venvs, iPhone backups) · Applications (last opened, leftovers, uninstall).

### Deleting
* **Move to Trash** (⌘⌫ in the app, `t` in the terminal) — reversible; **Undo** puts items back.
* **Delete permanently** / **Clear cache** / **Empty Trash** — always shows an "Are you sure? This is
  permanent" warning first. In the app, Return cancels; in the terminal, only the `y` key confirms
  (a mouse click can't).
* Refused no matter what: anything outside your home folder (except apps in /Applications),
  your home, Library, Documents, Desktop, Downloads, Pictures, Movies, Music and other standard
  folders themselves, Keychains, Preferences, ~/.ssh, ~/.gnupg, and anything inside packages
  such as a Photos library or an .app bundle.

## Development

* `engine.py` — scanner + safe delete (Python standard library only)
* `smcli.py` — terminal dashboard (curses)
* `MacApp/` — SwiftUI app
* `docs/` — the GitHub Pages site: `index.html` (download page) and `install.sh` (the installer)
* Engine log: `~/Library/Logs/StorageMonitor/engine.log`

```sh
./build.sh             # build for this Mac into build/
./build.sh --install   # … and install it into /Applications with the storagemon command
./build.sh --release   # universal build → dist/StorageMonitor.zip + .sha256
```

### Releasing
1. Bump `CFBundleShortVersionString` in `MacApp/Info.plist`.
2. `./build.sh --release`
3. `gh release create v<version> dist/StorageMonitor.zip dist/StorageMonitor.zip.sha256`
   — the installer always fetches the latest release.

The site is served by GitHub Pages from the `docs/` folder on `main`
(Settings › Pages › Deploy from a branch › `main` / `docs`).

### If you get an Apple Developer account
Notarizing removes the warning for browser downloads too: sign with
`codesign --force --options runtime --timestamp --sign "Developer ID Application: …"`, zip, then
`xcrun notarytool submit StorageMonitor.zip --keychain-profile … --wait` and
`xcrun stapler staple "Storage Monitor.app"` before re-zipping.
