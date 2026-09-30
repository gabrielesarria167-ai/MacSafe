# MacSafe

See what's filling up your Mac and clean it up on the spot. Two front-ends share one engine:

| | How to open | Best for |
|---|---|---|
| **Mac app** | `/Applications/MacSafe.app` (Spotlight: "MacSafe") | Browsing, sorting, bulk cleanup |
| **Terminal dashboard** | `macsafe` | Quick check without leaving the terminal |

## Install

Paste into Terminal:

```sh
curl -fsSL https://gabrielesarria167-ai.github.io/MacSafe/install.sh | bash
```

It installs the app into Applications, the `macsafe` command into `~/.local/bin`, and Python 3
(the official python.org installer, signature-checked) only if your Mac doesn't have it. Files fetched
with curl aren't quarantined, so macOS opens the app without the "could not verify" warning.
Requires macOS 14 or later, Apple Silicon or Intel. It replaces Storage Monitor.app and the
`storagemon` command, the names MacSafe had before version 1.1.

* **Regular download:** [MacSafe.dmg](https://github.com/gabrielesarria167-ai/MacSafe/releases/latest/download/MacSafe.dmg):
  open it and drag MacSafe into Applications. The app isn't notarized, so the first launch needs
  System Settings › Privacy & Security › **Open Anyway**.
* **Uninstall:** `curl -fsSL https://gabrielesarria167-ai.github.io/MacSafe/install.sh | bash -s -- --uninstall`
  (Python is left in place).
* **Full Disk Access:** for complete results, turn it on for MacSafe (and Terminal, for
  `macsafe`) in System Settings › Privacy & Security › Full Disk Access.

The download page is [gabrielesarria167-ai.github.io/MacSafe](https://gabrielesarria167-ai.github.io/MacSafe/).

## Updates

Both front-ends check GitHub for a newer release at most every 12 hours and update through the same
installer, run with `--update`:

* **Mac app:** the version at the top right of the window turns into an **Update** button when a new
  version is out, and **MacSafe › Check for Updates…** checks right away. The app quits, installs the
  update and reopens.
* **Terminal dashboard:** the header shows the version, or an **Update to x.y** chip (click it or press `U`).
* **Terminal:** `macsafe` installs a newer version on its own before the dashboard opens, then restarts
  on it. `macsafe --update` updates right away; `macsafe --no-update` (or `MACSAFE_NO_UPDATE=1`) skips
  the check.

Update output goes to `~/Library/Logs/MacSafe/update.log` when the app runs it.

## Using it

Both open instantly with the last scan (saved in `~/Library/Caches/MacSafe/snapshot.json`)
and rescan in the background when it's older than 15 minutes. `macsafe --report` prints a
summary and exits; `macsafe --app` opens the Mac app; `macsafe --no-mouse` leaves mouse
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
* Logs: `~/Library/Logs/MacSafe/engine.log` and `update.log`

```sh
./build.sh             # build for this Mac into build/
./build.sh --install   # … and install it into /Applications with the macsafe command
./build.sh --release   # universal build → dist/MacSafe.dmg + MacSafe.zip (app + README.txt), each with a .sha256
```

### Releasing
1. Bump `CFBundleShortVersionString` in `MacApp/Info.plist`.
2. `./build.sh --release`
3. `gh release create v<version> dist/*` (the .dmg is the site's download; the .zip is what
   `install.sh` and the Update button fetch). The disk image's window layout comes from Finder, so the
   first release build asks to let Terminal control Finder.
   — the installer always fetches the latest release, and the update check compares the release tag
   (`v1.2` → 1.2) with the installed app's version, so tag every release `v<CFBundleShortVersionString>`.
4. Push `main` (the site and `install.sh`) after the release exists: the installer downloads
   `MacSafe.zip` from the latest release.

The site is served by GitHub Pages from the `docs/` folder on `main`
(Settings › Pages › Deploy from a branch › `main` / `docs`).

### If you get an Apple Developer account
Notarizing removes the warning for browser downloads too: sign with
`codesign --force --options runtime --timestamp --sign "Developer ID Application: …"`, zip, then
`xcrun notarytool submit MacSafe.zip --keychain-profile … --wait` and
`xcrun stapler staple "MacSafe.app"` before re-zipping.
