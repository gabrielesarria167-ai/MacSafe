# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users
Everyday Mac owners who have just hit a "disk almost full" warning (or a sluggish, nearly-full Mac) and are nervous about deleting the wrong thing. Not assumed to be comfortable in Terminal, though the install is a single pasted command.

## Product Purpose
MacSafe shows where a Mac's storage went and lets the owner clean it up on the spot, safely. Success: the owner sees what is taking space within seconds of opening it, and frees space without breaking anything.

## Positioning
Leads with *seeing where the space went*: a single breakdown of the disk (macOS & other, app data & caches, applications, your files, free) that the user can click into, backed by focused views that name the culprits. Free, runs entirely on the Mac, nothing uploaded, source on GitHub.

## Operating Context
- Two front-ends on one engine: a SwiftUI Mac app (MacSafe.app) and a `macsafe` terminal dashboard.
- Install: `curl -fsSL https://gabrielesarria167-ai.github.io/MacSafe/install.sh | bash` (installs app, `macsafe`, and Python 3 from python.org only if missing, signature-checked). Re-run to update.
- Regular download is a disk image (MacSafe.dmg: drag the app into Applications). Not notarized, so first launch needs System Settings › Privacy & Security › Open Anyway. MacSafe.zip stays in each release for install.sh and in-app updates.
- Full Disk Access recommended for complete totals (MacSafe, and Terminal for `macsafe`).
- Uninstall via the same script with `--uninstall`; Python stays.

## Capabilities and Constraints
- Views: Overview, Explorer, Large files (>100 MB), Unused (untouched for months), Duplicates (byte-for-byte), Caches (safe-to-clear vs review-first), Clutter (old downloads, installers, node_modules/venvs, iPhone backups), Applications (last opened, leftovers, uninstall), Outside your home.
- Deleting: Move to Trash is reversible with Undo; permanent delete / clear cache / empty Trash always warns first; system and standard folders, Keychains, Preferences, ~/.ssh, package contents are refused outright.
- Requirements: macOS 14 or later, Apple Silicon and Intel. Free.
- Name: MacSafe everywhere since 1.1 (app bundle MacSafe.app, zip MacSafe.zip, command `macsafe`). Before 1.1 it was "Storage Monitor" / `storagemon`; the installer removes those copies.
- Updates: the app shows an Update button and Check for Updates…; the `macsafe` command installs newer versions on its own (at most one check every 12 hours; `--no-update` / `MACSAFE_NO_UPDATE=1` opt out). Both run install.sh `--update`.

## Brand Commitments
- Name: MacSafe (confirmed 2026-09-29).
- App category colors in use: system/other, app data & caches, applications, your files, free.
- Register: serious and professional (confirmed 2026-09-29). Illustrative or playful metaphors (cardboard boxes, food labels, sci-fi consoles) were rejected as childish. Benchmarks for polish: Apple's macOS product pages and modern dev-tool sites (Raycast, Linear, Tailscale).

## Evidence on Hand
- Real install commands, URLs, requirements, and feature list (docs/index.html, README.md).
- No screenshots of the app in the repo yet; example disk figures on the page are illustrative.
- No testimonials, user counts, press, ratings, or benchmarks exist. Do not fabricate them.

## Product Principles
1. Show before you ask: the disk picture comes first, cleanup follows understanding.
2. Nothing irreversible without a warning; the safe path is the default path.
3. Local and free: nothing leaves the Mac, nothing to subscribe to.
4. Plain language for people who don't know what ~/Library is.
