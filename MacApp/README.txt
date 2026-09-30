MacSafe {{VERSION}}
===============

See what's filling up your Mac and clean it up safely.
Free, and nothing leaves your Mac.


INSTALL
-------

1. Move MacSafe into Applications
   Drag MacSafe.app from this folder into your Applications folder
   (in Finder: Go > Applications). Keep it there rather than in
   Downloads: updates install into Applications.

2. Open it
   Double-click MacSafe in Applications, or find it with Spotlight
   (Command-Space, type "MacSafe").

3. Allow it the first time
   MacSafe isn't notarized by Apple, so macOS says it can't verify it.
   Click Done, open System Settings > Privacy & Security, scroll down
   and click Open Anyway. You only do this once.

4. Give it Full Disk Access
   macOS keeps Mail, Messages, Safari and some Library folders private.
   To measure them too, turn MacSafe on in System Settings > Privacy &
   Security > Full Disk Access (if it isn't listed, click + and choose
   it), then rescan.

Needs Python 3. MacSafe's scanner runs on Python 3. If your Mac doesn't
have it, MacSafe says so on launch and links to the free official
installer at https://www.python.org/downloads/macos/


PREFER TERMINAL?
----------------

One command installs the app, the `macsafe` terminal dashboard and, if
needed, Python. Downloads made this way skip the "can't verify" step:

    curl -fsSL https://gabrielesarria167-ai.github.io/MacSafe/install.sh | bash


WHAT IT DOES
------------

- Overview of your disk: macOS & other, app data & caches,
  applications, your files, free space.
- Large files, Unused files, byte-for-byte Duplicates, Caches (safe to
  clear vs review first) and Clutter: old downloads, installers,
  node_modules and virtualenvs, iPhone backups.
- Applications: when each was last opened, the leftovers it keeps in
  Library, and uninstalling.


SAFE BY DEFAULT
---------------

- Move to Trash can be undone. Anything permanent (deleting, clearing a
  cache, emptying the Trash) asks first.
- MacSafe refuses to touch system folders, your standard folders
  themselves (Documents, Desktop, Downloads...), Keychains, Preferences,
  ~/.ssh, or the inside of packages such as a Photos library.
- It runs entirely on your Mac. Nothing is uploaded.


UPDATES
-------

The version at the top right of the window turns into an Update button
when a new version is out. MacSafe > Check for Updates... checks right
away.


UNINSTALL
---------

Quit MacSafe and drag it from Applications to the Trash. If you also
installed the terminal command, this removes everything (Python stays):

    curl -fsSL https://gabrielesarria167-ai.github.io/MacSafe/install.sh | bash -s -- --uninstall


Requires macOS 14 or later, Apple Silicon or Intel.
Website:  https://gabrielesarria167-ai.github.io/MacSafe/
Source:   https://github.com/gabrielesarria167-ai/MacSafe
