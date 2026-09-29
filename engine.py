#!/usr/bin/env python3
"""
MacSafe engine — scans your Mac's storage and removes things safely.

Shared by both front-ends:
  • the Mac app runs `engine.py serve` and talks to it over a private localhost
    JSON API (random port, per-launch token, Host check; exits with the app);
  • the terminal dashboard (smcli.py) imports it directly.

Each finished scan is saved to ~/Library/Caches/MacSafe/snapshot.json so
both open instantly with the last results while a fresh scan runs. Both also update
themselves through the same installer (see "updates" below).
Only the Python standard library is used.
"""
import argparse
import errno
import hashlib
import json
import os
import plistlib
import re
import secrets
import shutil
import stat
import subprocess
import sys
import threading
import time
import traceback
import unicodedata
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOME = os.path.realpath(os.path.expanduser("~"))
APP_DIR = os.path.dirname(os.path.abspath(__file__))
TOKEN = secrets.token_urlsafe(24)
PORT = 0

MB = 1000 * 1000  # decimal units, like Finder
DAY = 86400
DIR_TRACK_MIN = 1 * MB     # folders at least this big are remembered (explorer)
FILE_TRACK_MIN = 5 * MB    # files at least this big are remembered


def H(*parts):
    return os.path.join(HOME, *parts)


LIBRARY = H("Library")
TRASH = H(".Trash")
DOWNLOADS = H("Downloads")
IOS_BACKUPS = H("Library", "Application Support", "MobileSync", "Backup")

# Folders whose every direct child is remembered, however small.
LIST_ALL_CHILDREN = {DOWNLOADS, H("Desktop"), TRASH, H("Library", "Caches"), H(".cache"), IOS_BACKUPS}

# Cloud drives and phone mounts: listing them can hit the network or hang.
SKIP_DIRS = {H("Library", "CloudStorage")}

# Where apps keep their own data; cache folders inside are detected by name.
APPDATA_ROOTS = {H("Library", "Application Support"), H("Library", "Containers"), H("Library", "Group Containers")}
CACHE_DIR_NAMES = {"Cache", "Caches", "Code Cache", "GPUCache", "CachedData", "CacheStorage",
                   "ShaderCache", "GrShaderCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache"}
VENV_NAMES = {"venv", ".venv", "env", ".virtualenv", "virtualenv"}

# macOS "packages": folders Finder shows as a single file. Never poke inside.
PACKAGE_EXTS = {".app", ".photoslibrary", ".photolibrary", ".migratedphotolibrary", ".musiclibrary",
                ".tvlibrary", ".imovielibrary", ".fcpbundle", ".logicx", ".band", ".xcarchive",
                ".framework", ".bundle", ".plugin", ".appex", ".kext", ".rtfd", ".pages", ".numbers",
                ".key", ".sparsebundle", ".xcodeproj", ".xcworkspace", ".playground", ".aplibrary",
                ".theater", ".lrlibrary", ".pvm", ".vmwarevm", ".utm", ".mpkg"}

# Can never be deleted as a whole (their contents may still be listed/cleaned).
PROTECTED = {HOME, LIBRARY, TRASH, DOWNLOADS, H("Documents"), H("Desktop"), H("Pictures"), H("Movies"),
             H("Music"), H("Public"), H("Applications"), H(".ssh"), H(".gnupg"), H(".config"), H(".local")}
# Protected folders whose *contents* may be cleared.
CLEARABLE = {TRASH, H("Library", "Caches"), H("Library", "Logs")}
# Never touched at all.
NEVER = {H("Library", "Keychains"), H(".ssh"), H(".gnupg"), H("Library", "Preferences")}

F_HIDDEN, F_LIB, F_DEV, F_PKG, F_APPDATA, F_CACHE = 1, 2, 4, 8, 16, 32

KINDS = {
    "video": {"mp4", "mov", "mkv", "avi", "m4v", "webm", "wmv", "flv", "mts", "m2ts", "3gp", "prores"},
    "image": {"jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "raw", "cr2", "cr3", "nef",
              "arw", "dng", "psd", "psb", "webp", "exr", "hdr", "bmp", "svg"},
    "audio": {"mp3", "wav", "aiff", "aif", "flac", "m4a", "aac", "ogg", "caf", "alac", "mid"},
    "archive": {"zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "lz4", "cab"},
    "installer": {"dmg", "pkg", "mpkg", "iso", "xip", "img", "msi", "exe", "apk", "ipa"},
    "document": {"pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "xlsm", "key", "pages",
                 "numbers", "epub", "txt", "rtf", "csv"},
    "3d": {"blend", "blend1", "obj", "fbx", "glb", "gltf", "stl", "dwg", "dxf", "max", "c4d", "usdz",
           "usd", "3ds", "skp", "rbxl", "rbxlx", "ma", "mb", "ztl"},
    "vm": {"vmdk", "vdi", "qcow2", "vhd", "vhdx", "raw", "hdd", "sparseimage", "sparsebundle", "utm", "pvm"},
    "data": {"db", "sqlite", "sqlite3", "parquet", "npy", "npz", "pt", "pth", "ckpt", "safetensors",
             "bin", "gguf", "onnx", "h5", "hdf5", "pkl", "json", "log", "tflite", "mlmodel"},
}
INSTALLER_EXTS = {"dmg", "pkg", "mpkg", "iso", "xip"}

# (relative path, display name, group, note, safety, action)
KNOWN_CACHES = [
    (".Trash", "Trash", "Trash", "Files you already deleted. Emptying the Trash frees their space for good.", "safe", "clear"),
    ("Library/Logs", "Logs", "System", "Diagnostic logs written by apps and macOS.", "safe", "clear"),
    ("Library/Developer/Xcode/DerivedData", "Xcode DerivedData", "Developer", "Build products and indexes. Xcode rebuilds them on the next build.", "safe", "clear"),
    ("Library/Developer/Xcode/iOS DeviceSupport", "iOS DeviceSupport", "Developer", "Debug symbols for devices you've plugged in. Re-created when you connect a device.", "safe", "clear"),
    ("Library/Developer/Xcode/watchOS DeviceSupport", "watchOS DeviceSupport", "Developer", "Debug symbols for watches. Re-created when needed.", "safe", "clear"),
    ("Library/Developer/Xcode/Archives", "Xcode Archives", "Developer", "Archived app builds. Keep them if you need to symbolicate crash reports.", "review", "trash"),
    ("Library/Developer/CoreSimulator/Caches", "Simulator caches", "Developer", "Dyld and runtime caches for the iOS Simulator.", "safe", "clear"),
    ("Library/Developer/CoreSimulator/Devices", "iOS Simulator devices", "Developer", "Simulators and the apps installed on them. Tip: `xcrun simctl delete unavailable` removes only stale ones.", "review", "trash"),
    (".npm/_cacache", "npm cache", "Developer", "Downloaded npm packages. Re-downloaded on the next install.", "safe", "clear"),
    (".gradle/caches", "Gradle cache", "Developer", "Downloaded dependencies and build cache.", "safe", "clear"),
    (".m2/repository", "Maven repository", "Developer", "Downloaded Java dependencies.", "safe", "clear"),
    (".cargo/registry", "Cargo registry", "Developer", "Downloaded Rust crates.", "safe", "clear"),
    ("go/pkg/mod", "Go module cache", "Developer", "Downloaded Go modules.", "safe", "clear"),
    (".cocoapods/repos", "CocoaPods specs", "Developer", "The CocoaPods spec repo clone.", "safe", "clear"),
    (".bun/install/cache", "Bun cache", "Developer", "Downloaded Bun packages.", "safe", "clear"),
    ("Library/pnpm/store", "pnpm store", "Developer", "pnpm's shared package store.", "safe", "clear"),
    (".pnpm-store", "pnpm store", "Developer", "pnpm's shared package store.", "safe", "clear"),
    (".yarn/berry/cache", "Yarn cache", "Developer", "Downloaded Yarn packages.", "safe", "clear"),
    (".android/avd", "Android emulators", "Developer", "Android Virtual Devices and their data.", "review", "trash"),
    ("Library/Containers/com.docker.docker/Data/vms", "Docker disk image", "Developer", "Holds every Docker image, container and volume. Clean it from Docker Desktop (Troubleshoot → Clean / Purge data) instead.", "review", "none"),
]
DOTCACHE_NOTES = {
    "huggingface": ("Downloaded AI models and datasets. They're downloaded again when a script needs them.", "review"),
    "lm-studio": ("Downloaded AI models.", "review"),
    "ms-playwright": ("Browsers downloaded by Playwright. Re-installed with `npx playwright install`.", "safe"),
    "puppeteer": ("Chromium builds downloaded by Puppeteer.", "safe"),
    "pip": ("Downloaded Python packages.", "safe"),
    "uv": ("uv's package cache.", "safe"),
    "torch": ("PyTorch hub models.", "review"),
}


# ───────────────────────────── helpers ──────────────────────────────

def ext_of(path):
    name = os.path.basename(path)
    if name.lower().endswith((".tar.gz", ".tar.xz", ".tar.bz2")):
        return "tar"
    return os.path.splitext(name)[1][1:].lower()


def kind_of(path, is_dir, mark=None):
    if mark == "package" or (is_dir and os.path.splitext(path)[1].lower() in PACKAGE_EXTS):
        return "app" if path.endswith(".app") else "package"
    if is_dir:
        return "folder"
    ext = ext_of(path)
    for kind, exts in KINDS.items():
        if ext in exts:
            return kind
    return "other"


def classify(parent, name, path, pflags):
    """Return (flags for this folder's contents, marker for this folder)."""
    f = pflags
    marker = None
    ext = os.path.splitext(name)[1].lower()
    blocked = F_DEV | F_HIDDEN | F_LIB | F_PKG
    if ext in PACKAGE_EXTS and not (pflags & F_PKG):
        marker = "package"
    elif name == "node_modules" and not (pflags & blocked) and os.path.isfile(os.path.join(parent, "package.json")):
        marker = "node_modules"
    elif name in VENV_NAMES and not (pflags & blocked) and os.path.isfile(os.path.join(path, "pyvenv.cfg")):
        marker = "venv"
    elif name in CACHE_DIR_NAMES and (pflags & F_APPDATA) and not (pflags & (F_CACHE | F_PKG)):
        marker = "appcache"
    if name.startswith("."):
        f |= F_HIDDEN
    if path == LIBRARY:
        f |= F_LIB
    if path in APPDATA_ROOTS:
        f |= F_APPDATA
    if marker in ("node_modules", "venv"):
        f |= F_DEV
    if marker == "package":
        f |= F_PKG
    if marker == "appcache":
        f |= F_CACHE
    return f, marker


def flags_for(path):
    """Flags that apply to the *contents* of `path` (must be HOME or inside it)."""
    if path == HOME:
        return 0
    rel = os.path.relpath(path, HOME).split(os.sep)
    cur, f, marker = HOME, 0, None
    for part in rel:
        nxt = os.path.join(cur, part)
        f, marker = classify(cur, part, nxt, f)
        cur = nxt
    return f


def own_flags(parent_flags, name, path):
    """Flags describing where an entry itself lives (context + its own hidden-ness)."""
    f = parent_flags
    if name.startswith("."):
        f |= F_HIDDEN
    if path == LIBRARY:
        f |= F_LIB
    return f


def du(path, same_dev=True):
    """Allocated bytes under `path` (no bookkeeping). Doesn't cross into other volumes."""
    try:
        st = os.lstat(path)
    except OSError:
        return 0
    if not stat.S_ISDIR(st.st_mode):
        return st.st_blocks * 512
    dev = st.st_dev if same_dev else None
    total, stack = 0, [path]
    while stack:
        d = stack.pop()
        try:
            it = os.scandir(d)
        except OSError:
            continue
        try:
            with it:
                for e in it:
                    try:
                        st = e.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if stat.S_ISDIR(st.st_mode):
                        if dev is None or st.st_dev == dev:
                            stack.append(e.path)
                    else:
                        total += st.st_blocks * 512
        except OSError:
            pass
    return total


def spotlight_last_used(root):
    """{path: timestamp} for everything under root that Spotlight saw being opened."""
    try:
        out = subprocess.run(["mdfind", "-onlyin", root, "-attr", "kMDItemLastUsedDate", "kMDItemLastUsedDate = *"],
                             capture_output=True, timeout=180).stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError):
        return {}
    res = {}
    marker = " kMDItemLastUsedDate = "
    for line in out.splitlines():
        i = line.rfind(marker)
        if i < 0:
            continue
        path, val = line[:i].rstrip(), line[i + len(marker):].strip()
        try:
            res[path] = datetime.strptime(val, "%Y-%m-%d %H:%M:%S %z").timestamp()
        except ValueError:
            pass
    return res


def clean_text(s):
    """Drop invisible formatting/control characters some apps put in their names (e.g. U+200E)."""
    return "".join(ch for ch in str(s) if unicodedata.category(ch) not in ("Cf", "Cc")).strip()


def read_plist(path):
    try:
        with open(path, "rb") as fh:
            return plistlib.load(fh)
    except Exception:
        return {}


def pretty_bundle(bid, names):
    if bid in names:
        return names[bid]
    parts = bid.split(".")
    if len(parts) >= 3 and parts[0] in ("com", "org", "net", "io", "app", "dev", "co"):
        tail = parts[2:]
        return " ".join(p[:1].upper() + p[1:] for p in tail)
    return bid


def _chmod_retry(func, path, _exc):
    """rmtree error hook: make things writable (e.g. Go's read-only module cache) and retry."""
    try:
        os.chflags(path, 0) if hasattr(os, "chflags") else None
    except OSError:
        pass
    for p in (os.path.dirname(path), path):
        try:
            os.chmod(p, 0o700)
        except OSError:
            pass
    try:
        func(path)
    except FileNotFoundError:
        pass
    except OSError:
        pass  # left in place; the caller re-measures what remains


def remove_path(path):
    st = os.lstat(path)
    if stat.S_ISDIR(st.st_mode):
        if sys.version_info >= (3, 12):
            shutil.rmtree(path, onexc=_chmod_retry)
        else:
            shutil.rmtree(path, onerror=lambda f, p, e: _chmod_retry(f, p, e))
    else:
        try:
            os.unlink(path)
        except PermissionError:
            _chmod_retry(os.unlink, path, None)


TRASH_JS = r"""
ObjC.import('Foundation');
function listTrash(fm, t) { var a = fm.contentsOfDirectoryAtPathError(t, null); return a ? ObjC.deepUnwrap(a) : []; }
function run(argv) {
  var fm = $.NSFileManager.defaultManager, trash = argv[0], out = [];
  for (var i = 1; i < argv.length; i++) {
    var before = {};
    listTrash(fm, trash).forEach(function (n) { before[n] = 1; });
    var err = $();
    var ok = fm.trashItemAtURLResultingItemURLError($.NSURL.fileURLWithPath(argv[i]), null, err);
    var r = {path: argv[i], ok: !!ok};
    if (ok) {
      var added = listTrash(fm, trash).filter(function (n) { return !before[n]; });
      if (added.length === 1) r.to = trash + '/' + added[0];
    } else {
      r.error = (err && err.localizedDescription) ? err.localizedDescription.js : 'Could not move to Trash';
    }
    out.push(r);
  }
  return JSON.stringify(out);
}
"""


def trash_paths(paths):
    """Move to the Trash with NSFileManager (keeps Finder's “Put Back”). Returns list of result dicts."""
    results = []
    for i in range(0, len(paths), 50):
        chunk = paths[i:i + 50]
        try:
            r = subprocess.run(["osascript", "-l", "JavaScript", "-e", TRASH_JS, TRASH, *chunk],
                               capture_output=True, timeout=600)
            results.extend(json.loads(r.stdout.decode("utf-8") or "[]"))
        except Exception as ex:  # noqa: BLE001
            results.extend({"path": p, "ok": False, "error": str(ex)} for p in chunk)
    # Root-owned apps in /Applications need Finder (it asks for your password).
    for r in results:
        if not r["ok"] and r["path"].startswith("/Applications/") and os.path.lexists(r["path"]):
            script = 'tell application "Finder" to delete (POSIX file %s as alias)' % json.dumps(r["path"], ensure_ascii=False)
            p = subprocess.run(["osascript", "-e", script], capture_output=True, timeout=300)
            if p.returncode == 0:
                r.update(ok=True, error=None)
    return results


# ───────────────────────────── index ──────────────────────────────

MARKERS = ("node_modules", "venv", "appcache", "package")
SNAP_DIR = H("Library", "Caches", "MacSafe")
SNAP_FILE = os.path.join(SNAP_DIR, "snapshot.json")
SNAP_VERSION = 1


class Index:
    """Everything one scan learned. A rescan builds a fresh Index and swaps it in."""

    def __init__(self):
        self.entries = {}      # path -> dict (tracked files & folders)
        self.children = {}     # folder -> set of tracked child paths
        self.markers = {m: set() for m in MARKERS}
        self.apps = {}
        self.outside = []
        self.snapshots = 0
        self.bundle_names = {}
        self.denied = []
        self.scanned_at = 0.0
        self.files = 0
        self.bytes = 0

    def to_json(self):
        return {"version": SNAP_VERSION, "home": HOME, "entries": self.entries,
                "children": {k: sorted(v) for k, v in self.children.items()},
                "markers": {k: sorted(v) for k, v in self.markers.items()},
                "apps": self.apps, "outside": self.outside, "snapshots": self.snapshots,
                "bundle_names": self.bundle_names, "denied": self.denied, "scanned_at": self.scanned_at,
                "files": self.files, "bytes": self.bytes}

    @classmethod
    def from_json(cls, d):
        if d.get("version") != SNAP_VERSION or d.get("home") != HOME:
            return None
        idx = cls()
        idx.entries = d["entries"]
        idx.children = {k: set(v) for k, v in d["children"].items()}
        idx.markers = {m: set(d["markers"].get(m, ())) for m in MARKERS}
        for k in ("apps", "outside", "snapshots", "bundle_names", "denied", "scanned_at", "files", "bytes"):
            setattr(idx, k, d[k])
        return idx


class Walker:
    """Measures folders recursively and records what's worth remembering into an Index."""

    def __init__(self, idx, progress=None):
        self.idx = idx
        self.p = progress if progress is not None else {"files": 0, "bytes": 0, "current": ""}

    @staticmethod
    def dir_entry(st, size, n, newest, f, mark=None):
        return {"size": size, "files": n, "dir": True, "mtime": st.st_mtime, "btime": getattr(st, "st_birthtime", 0),
                "newest": newest or st.st_mtime, "f": f, "mark": mark}

    @staticmethod
    def file_entry(st, f):
        return {"size": st.st_blocks * 512, "lsize": st.st_size, "ino": st.st_ino, "dir": False,
                "mtime": st.st_mtime, "atime": st.st_atime, "btime": getattr(st, "st_birthtime", 0), "f": f}

    def walk(self, path, dev, flags):
        """Returns (bytes, files, newest file mtime) for `path`."""
        idx, prog = self.idx, self.p
        total = nfiles = 0
        newest = 0.0
        kids = set()
        list_all = path in LIST_ALL_CHILDREN
        try:
            it = os.scandir(path)
        except OSError as ex:
            if ex.errno in (errno.EPERM, errno.EACCES) and len(idx.denied) < 500:
                idx.denied.append(path)
            return 0, 0, 0.0
        with it:
            while True:
                try:
                    e = next(it)
                except StopIteration:
                    break
                except OSError:  # e.g. a network-backed folder timing out mid-listing
                    break
                try:
                    st = e.stat(follow_symlinks=False)
                except OSError:
                    continue
                mode = st.st_mode
                p = e.path
                if stat.S_ISDIR(mode):
                    if st.st_dev != dev or p in SKIP_DIRS:
                        continue  # another volume, or a cloud/phone mount
                    cflags, mark = classify(path, e.name, p, flags)
                    s, n, nw = self.walk(p, dev, cflags)
                    total += s
                    nfiles += n
                    if nw > newest:
                        newest = nw
                    if s >= DIR_TRACK_MIN or list_all or p == TRASH:
                        idx.entries[p] = self.dir_entry(st, s, n, nw, own_flags(flags, e.name, p), mark)
                        kids.add(p)
                        if mark:
                            idx.markers[mark].add(p)
                elif stat.S_ISREG(mode):
                    sz = st.st_blocks * 512
                    nfiles += 1
                    total += sz
                    prog["files"] += 1
                    prog["bytes"] += sz
                    if st.st_mtime > newest:
                        newest = st.st_mtime
                    if sz >= FILE_TRACK_MIN or list_all:
                        idx.entries[p] = self.file_entry(st, own_flags(flags, e.name, p))
                        kids.add(p)
                    if not (prog["files"] & 2047):
                        prog["current"] = path
                else:
                    total += st.st_blocks * 512
        if kids:
            idx.children[path] = kids
        return total, nfiles, newest


def has_full_disk_access():
    try:
        with open(H("Library", "Application Support", "com.apple.TCC", "TCC.db"), "rb"):
            return True
    except PermissionError:
        return False
    except OSError:
        return True  # file missing: nothing to learn


# ───────────────────────────── engine ──────────────────────────────

class Engine:
    def __init__(self, use_snapshot=True):
        self.lock = threading.RLock()
        self.idx = None
        self.thread = None
        self.scan = {"state": "idle"}
        self.progress = {"files": 0, "bytes": 0, "current": ""}
        self.touched = []          # paths changed while a scan was running
        self.removed_apps = {}
        self.left_sizes = {}       # memoized sizes of app leftover folders
        self.dups = {"state": "idle"}
        if use_snapshot:
            self.load_snapshot()

    # ── snapshot (instant start) ──
    def load_snapshot(self):
        try:
            with open(SNAP_FILE, "r", encoding="utf-8") as fh:
                self.idx = Index.from_json(json.load(fh))
        except (OSError, ValueError, KeyError, TypeError):
            self.idx = None
        return self.idx is not None

    def save_snapshot(self):
        with self.lock:
            if self.idx is None:
                return
            data = json.dumps(self.idx.to_json(), separators=(",", ":"))
        try:
            os.makedirs(SNAP_DIR, exist_ok=True)
            tmp = SNAP_FILE + ".tmp%d" % os.getpid()
            with open(tmp, "w", encoding="utf-8") as fh:
                fh.write(data)
            os.replace(tmp, SNAP_FILE)
        except OSError:
            pass

    @property
    def age(self):
        return time.time() - self.idx.scanned_at if self.idx else None

    @property
    def scanning(self):
        return self.scan.get("state") == "scanning"

    # ── scanning ──
    def start_scan(self):
        with self.lock:
            if self.thread and self.thread.is_alive():
                return False
            self.progress = {"files": 0, "bytes": 0, "current": ""}
            self.touched = []
            self.scan = {"state": "scanning", "phase": "Scanning your home folder", "started": time.time()}
            threading.stack_size(128 * 1024 * 1024)  # deep folder trees recurse deeply
            try:
                self.thread = threading.Thread(target=self._run, daemon=True)
                self.thread.start()
            finally:
                threading.stack_size(0)
            return True

    def status(self):
        s = dict(self.scan)
        if s.get("state") == "scanning":
            s.update(files=self.progress["files"], bytes=self.progress["bytes"],
                     current=self.progress["current"].replace(HOME, "~", 1),
                     elapsed=time.time() - s.get("started", time.time()))
            if self.idx and self.idx.files:
                s["fraction"] = min(0.99, self.progress["files"] / float(self.idx.files))
        idx = self.idx
        return {"scan": s, "has_data": idx is not None, "scanned_at": idx.scanned_at if idx else None,
                "denied": len(idx.denied) if idx else 0, "disk": self.disk(), "fda": has_full_disk_access(),
                "home": HOME}

    def _run(self):
        t0 = time.time()
        try:
            idx = Index()
            w = Walker(idx, self.progress)
            st = os.stat(HOME)
            size, n, newest = w.walk(HOME, st.st_dev, 0)
            idx.entries[HOME] = Walker.dir_entry(st, size, n, newest, 0)
            self.scan["phase"] = "Reading “last opened” dates from Spotlight"
            for p, ts in spotlight_last_used(HOME).items():
                e = idx.entries.get(p)
                if e is not None:
                    e["used"] = ts
            self.scan["phase"] = "Measuring applications"
            self._scan_apps(idx)
            self._scan_outside(idx)
            idx.scanned_at = time.time()
            idx.files, idx.bytes = self.progress["files"], self.progress["bytes"]
            with self.lock:
                # anything deleted or restored mid-scan: make the fresh index agree with the disk
                touched = sorted(set(self.touched), key=len)
                for p in touched:
                    self._refresh(idx, p, self._measure(idx, p))
                    if p in idx.apps and not os.path.lexists(p):
                        del idx.apps[p]
                if touched:
                    self._refresh(idx, TRASH, self._measure(idx, TRASH))
                self.touched = []
                self.idx = idx
                self.left_sizes = {}
                self.scan = {"state": "done", "started": t0, "finished": time.time()}
            self.save_snapshot()
        except Exception:  # noqa: BLE001
            self.scan = {"state": "error", "error": traceback.format_exc()}

    def _scan_apps(self, idx):
        used = spotlight_last_used("/Applications")
        apps = {}
        for root in ("/Applications", H("Applications")):
            try:
                top = sorted(os.listdir(root))
            except OSError:
                continue
            cands = []
            for name in top:
                p = os.path.join(root, name)
                if name.endswith(".app"):
                    cands.append(p)
                elif os.path.isdir(p) and not os.path.islink(p):
                    try:
                        cands += [os.path.join(p, n) for n in os.listdir(p) if n.endswith(".app")]
                    except OSError:
                        pass
            for p in cands:
                try:
                    st = os.lstat(p)
                except OSError:
                    continue
                if stat.S_ISLNK(st.st_mode) or (getattr(st, "st_flags", 0) & stat.SF_RESTRICTED):
                    continue  # symlink or SIP-protected system app
                info = read_plist(os.path.join(p, "Contents", "Info.plist"))
                name = clean_text(info.get("CFBundleDisplayName") or info.get("CFBundleName") or os.path.basename(p)[:-4])
                bid = str(info.get("CFBundleIdentifier", ""))
                if bid:
                    idx.bundle_names[bid] = name
                e = idx.entries.get(p)
                self.scan["phase"] = "Measuring applications · " + name
                apps[p] = {"size": e["size"] if e else du(p), "name": name, "bid": bid,
                           "version": str(info.get("CFBundleShortVersionString", "")),
                           "used": used.get(p) or (e or {}).get("used"), "mtime": st.st_mtime,
                           "btime": getattr(st, "st_birthtime", 0),
                           "store": os.path.exists(os.path.join(p, "Contents", "_MASReceipt"))}
        idx.apps = apps

    def _scan_outside(self, idx):
        """Measure the big folders outside your home so “macOS & other” isn't a mystery."""
        try:
            tmp = subprocess.run(["getconf", "DARWIN_USER_TEMP_DIR"], capture_output=True, timeout=10).stdout.decode().strip()
            tmp_root = os.path.dirname(os.path.realpath(tmp.rstrip("/"))) if tmp else None
        except (OSError, subprocess.SubprocessError):
            tmp_root = None
        locs = [
            ("/Library", "System-wide Library", "App data, fonts, plug-ins and simulator runtimes shared by every account."),
            ("/opt/homebrew", "Homebrew", "Command-line tools installed with Homebrew. `brew cleanup` removes old versions."),
            ("/usr/local", "/usr/local", "Tools installed outside Homebrew (or by Intel Homebrew)."),
            ("/Users/Shared", "Shared folder", "Files shared between user accounts."),
            (tmp_root, "Temporary files", "Per-user temp files and system caches. macOS trims these on restart."),
            ("/private/var/vm", "Swap & sleep image", "Virtual memory managed by macOS. It shrinks after a restart."),
        ]
        out = []
        for p, name, note in locs:
            if not p or not os.path.isdir(p):
                continue
            self.scan["phase"] = "Measuring " + name
            size = du(p)
            if size >= 20 * MB:
                out.append({"path": p, "name": name, "note": note, "size": size})
        idx.outside = sorted(out, key=lambda x: -x["size"])
        try:
            r = subprocess.run(["tmutil", "listlocalsnapshots", "/"], capture_output=True, timeout=20)
            idx.snapshots = sum(1 for line in r.stdout.decode().splitlines() if "com.apple" in line)
        except (OSError, subprocess.SubprocessError):
            idx.snapshots = 0

    # ── items ──
    @staticmethod
    def activity(e):
        base = e["newest"] if e["dir"] else e["mtime"]
        opened = e.get("used") or (0 if e["dir"] else e.get("atime", 0))
        return max(base, opened, e.get("btime") or 0)

    def item(self, p, **extra):
        idx = self.idx
        e = idx.entries[p]
        d = {"path": p, "name": os.path.basename(p), "size": e["size"], "dir": e["dir"],
             "kind": kind_of(p, e["dir"], e.get("mark")), "mtime": e["mtime"], "used": e.get("used"),
             "activity": self.activity(e), "loc": self.location(p),
             "drill": e["dir"] and e.get("mark") != "package" and bool(idx.children.get(p)),
             "appdata": bool(e["f"] & (F_LIB | F_HIDDEN))}
        d.update(extra)
        return d

    @staticmethod
    def location(p):
        parent = os.path.dirname(p)
        if parent == HOME or parent.startswith(HOME + os.sep):
            return "~" + parent[len(HOME):]
        return parent

    @staticmethod
    def visible(e, include_appdata):
        if e["f"] & F_PKG:
            return False
        if not include_appdata and e["f"] & (F_LIB | F_HIDDEN | F_DEV):
            return False
        return True

    # ── views (call with self.lock held or via the HTTP layer) ──
    @staticmethod
    def disk():
        d = shutil.disk_usage(HOME)
        return {"total": d.total, "free": d.free, "used": d.total - d.free}

    def overview(self):
        idx = self.idx
        disk = self.disk()
        home = idx.entries.get(HOME, {"size": 0})["size"]
        lib = idx.entries.get(LIBRARY, {"size": 0})["size"]
        hidden = sum(idx.entries[k]["size"] for k in idx.children.get(HOME, ())
                     if os.path.basename(k).startswith(".") and k in idx.entries)
        apps = sum(a["size"] for p, a in idx.apps.items() if not p.startswith(HOME + "/"))
        system = max(0, disk["used"] - home - apps)
        top = sorted((self.item(k) for k in idx.children.get(HOME, ()) if k in idx.entries),
                     key=lambda x: -x["size"])[:12]
        caches = self.caches()
        clutter = self.clutter()
        old = time.time() - 90 * DAY
        return {
            "disk": disk,
            "breakdown": [
                {"key": "apps", "label": "Applications", "size": apps},
                {"key": "files", "label": "Your files", "size": max(0, home - lib - hidden)},
                {"key": "appdata", "label": "App data & caches", "size": lib + hidden},
                {"key": "system", "label": "macOS & other", "size": system},
            ],
            "home": home,
            "top": top,
            "wins": {
                "trash": idx.entries.get(TRASH, {"size": 0})["size"],
                "caches": sum(c["size"] for c in caches if c["safety"] == "safe" and c["action"] == "clear" and c["path"] != TRASH),
                "downloads": sum(i["size"] for i in clutter["downloads"] if i["activity"] < old),
                "installers": sum(i["size"] for i in clutter["installers"]),
                "dev": sum(i["size"] for i in clutter["dev"]),
                "backups": sum(i["size"] for i in clutter["backups"]),
            },
            "large": self.large(min_mb=200, include_appdata=False, limit=8),
            "outside": idx.outside,
            "snapshots": idx.snapshots,
        }

    def large(self, min_mb=100, include_appdata=True, limit=500, kind=None, q=None):
        min_b = min_mb * MB
        out = []
        for p, e in self.idx.entries.items():
            if e["size"] < min_b or p == HOME:
                continue
            if e["dir"] and e.get("mark") != "package":
                continue
            if not self.visible(e, include_appdata):
                continue
            it = self.item(p)
            if kind and it["kind"] != kind:
                continue
            if q and q.lower() not in p.lower():
                continue
            out.append(it)
        out.sort(key=lambda x: -x["size"])
        return out[:limit]

    def unused(self, days=90, min_mb=10, include_appdata=False, limit=500):
        cutoff = time.time() - days * DAY
        min_b = min_mb * MB
        files, folders = [], []
        for p, e in self.idx.entries.items():
            if e["size"] < min_b or not self.visible(e, include_appdata):
                continue
            if self.activity(e) >= cutoff:
                continue
            if not e["dir"] or e.get("mark") == "package":
                files.append(self.item(p))
            elif p not in PROTECTED and not p.startswith(TRASH + "/") and os.path.relpath(p, HOME).count(os.sep) <= 2:
                folders.append(p)
        folders.sort()  # keep only the top-most stale folders
        kept, last = [], None
        for p in folders:
            if last and p.startswith(last + os.sep):
                continue
            kept.append(p)
            last = p
        in_kept = tuple(k + os.sep for k in kept)
        for f in files:
            f["in_stale_folder"] = f["path"].startswith(in_kept)
        files.sort(key=lambda x: -x["size"])
        return {"files": files[:limit], "folders": sorted((self.item(p) for p in kept), key=lambda x: -x["size"])[:limit]}

    def caches(self):
        idx = self.idx
        out, seen = [], set()

        def add(p, name, group, note, safety, action, sub=None):
            e = idx.entries.get(p)
            if not e or p in seen or e["size"] < MB:
                return
            seen.add(p)
            out.append({"path": p, "name": name, "sub": sub or ("~" + p[len(HOME):]), "group": group, "note": note,
                        "safety": safety, "action": action, "size": e["size"], "dir": e["dir"],
                        "activity": self.activity(e), "kind": "folder" if e["dir"] else kind_of(p, False)})

        for rel, name, group, note, safety, action in KNOWN_CACHES:
            add(H(rel), name, group, note, safety, action)
        for p in idx.children.get(H("Library", "Caches"), ()):
            bid = os.path.basename(p)
            if bid in ("com.apple.bird", "MacSafe", "StorageMonitor") or p in seen:
                continue
            system = bid.startswith("com.apple.")
            add(p, pretty_bundle(bid, idx.bundle_names), "macOS caches" if system else "App caches",
                "macOS rebuilds this cache when needed; a few files may be in use." if system else
                "Temporary files the app re-creates. Quit the app first for best results.",
                "safe", "clear", sub=bid)
        for p in idx.children.get(H(".cache"), ()):
            base = os.path.basename(p)
            note, safety = DOTCACHE_NOTES.get(base, ("Tool cache; re-created when needed.", "safe"))
            add(p, base, "Developer", note, safety, "clear")
        for p in idx.markers["appcache"]:
            rel = os.path.relpath(p, LIBRARY).split(os.sep)
            if rel[0] in ("Containers", "Group Containers"):
                owner = rel[1]
                if owner.startswith("group."):
                    owner = owner[6:]
                head = owner.split(".", 1)[0]
                if len(head) == 10 and head.isalnum() and head.isupper():
                    owner = owner.split(".", 1)[-1]  # strip the team ID prefix
                name = "%s › %s" % (pretty_bundle(owner, idx.bundle_names), rel[-1])
            else:
                name = rel[1] if len(rel) == 2 else "%s › %s" % (rel[1], rel[-1])
            add(p, name, "App caches", "A cache folder inside the app's data. Quit the app before clearing it.",
                "safe", "clear")
        out.sort(key=lambda x: -x["size"])
        return [c for c in out if c["size"] >= 5 * MB or c["path"] == TRASH]

    def clutter(self):
        idx = self.idx
        # .localized and .DS_Store are Finder's own markers, not downloads anyone wants to review.
        downloads = sorted((self.item(p) for p in idx.children.get(DOWNLOADS, ())
                            if p in idx.entries and os.path.basename(p) not in (".localized", ".DS_Store")),
                           key=lambda x: -x["size"])
        installers = sorted((self.item(p) for p, e in idx.entries.items()
                             if not e["dir"] and ext_of(p) in INSTALLER_EXTS and self.visible(e, False)),
                            key=lambda x: -x["size"])
        dev = []
        for mark, label in (("node_modules", "node_modules"), ("venv", "Python virtualenv")):
            for p in idx.markers[mark]:
                if p not in idx.entries:
                    continue
                proj = os.path.dirname(p)
                pe = idx.entries.get(proj)
                dev.append(self.item(p, label=label, project=os.path.basename(proj),
                                     activity=self.activity(pe) if pe else idx.entries[p]["mtime"]))
        dev.sort(key=lambda x: -x["size"])
        backups = []
        for p in idx.children.get(IOS_BACKUPS, ()):
            if p not in idx.entries or not idx.entries[p]["dir"]:
                continue
            info = read_plist(os.path.join(p, "Info.plist"))
            last = info.get("Last Backup Date")
            backups.append(self.item(p, label=info.get("Device Name") or "Device backup",
                                     product=str(info.get("Product Type", "")),
                                     activity=last.timestamp() if isinstance(last, datetime) else idx.entries[p]["mtime"]))
        backups.sort(key=lambda x: -x["size"])
        return {"downloads": downloads, "installers": installers, "dev": dev, "backups": backups}

    def explore(self, path):
        idx = self.idx
        path = os.path.normpath(path or HOME)
        if not (path == HOME or path.startswith(HOME + os.sep)) or path not in idx.entries:
            path = HOME
        e = idx.entries[path]
        items = sorted((self.item(k) for k in idx.children.get(path, ()) if k in idx.entries), key=lambda x: -x["size"])
        crumbs, cur = [], path
        while True:
            crumbs.append({"path": cur, "name": "Home" if cur == HOME else os.path.basename(cur)})
            if cur == HOME:
                break
            cur = os.path.dirname(cur)
        return {"path": path, "size": e["size"], "files": e["files"], "items": items,
                "other": max(0, e["size"] - sum(i["size"] for i in items)), "crumbs": crumbs[::-1]}

    def leftovers(self, app):
        """Support folders an app leaves in ~/Library after its .app is gone."""
        bid, name = app["bid"], app["name"]
        if not bid or bid.startswith("com.apple.") or "/" in bid:
            return []
        cands = [H("Library", "Application Support", bid), H("Library", "Caches", bid), H("Library", "Containers", bid),
                 H("Library", "Saved Application State", bid + ".savedState"), H("Library", "HTTPStorages", bid),
                 H("Library", "WebKit", bid), H("Library", "Logs", bid)]
        if name and "/" not in name and not name.startswith("."):
            cands += [H("Library", "Application Support", name), H("Library", "Logs", name)]
        out, seen = [], set()
        for p in dict.fromkeys(cands):
            try:
                st = os.lstat(p)
            except OSError:
                continue
            key = (st.st_dev, st.st_ino)  # the disk is case-insensitive: "Foo" and "foo" are one folder
            if not stat.S_ISDIR(st.st_mode) or key in seen or self.check(p, "trash"):
                continue
            seen.add(key)
            if p not in self.left_sizes:
                self.left_sizes[p] = self._measure(self.idx, p)
            out.append({"path": p, "size": self.left_sizes[p], "loc": "~" + p[len(HOME):]})
        return out

    def app_list(self):
        out = []
        for p, a in self.idx.apps.items():
            if not os.path.lexists(p):
                continue
            left = self.leftovers(a)
            out.append({"path": p, "name": a["name"], "bid": a["bid"], "version": a["version"], "size": a["size"],
                        "used": a["used"], "activity": a["used"] or max(a["mtime"], a["btime"]), "store": a["store"],
                        "kind": "app", "dir": True, "loc": os.path.dirname(p), "leftovers": left,
                        "leftover_size": sum(x["size"] for x in left)})
        out.sort(key=lambda x: -x["size"])
        return out

    # ── duplicates ──
    def start_dups(self):
        with self.lock:
            if self.dups.get("state") == "running" or self.idx is None:
                return
            self.dups = {"state": "running", "done": 0, "total": 0}
        threading.Thread(target=self._dups, daemon=True).start()

    def _dups(self):
        try:
            with self.lock:
                entries = dict(self.idx.entries)
            by_size = {}
            for p, e in entries.items():
                if e["dir"] or not self.visible(e, False) or p.startswith(TRASH + "/"):
                    continue
                by_size.setdefault(e["lsize"], []).append(p)
            groups = []
            for size, paths in by_size.items():
                inos, uniq = set(), []
                for p in paths:  # hard links are the same file, not duplicates
                    if entries[p]["ino"] not in inos:
                        inos.add(entries[p]["ino"])
                        uniq.append(p)
                if len(uniq) > 1:
                    groups.append((size, uniq))
            self.dups["total"] = sum(size * len(ps) for size, ps in groups)

            def digest(p, full):
                h = hashlib.blake2b(digest_size=20)
                st = os.stat(p)
                with open(p, "rb") as fh:
                    if full:
                        for chunk in iter(lambda: fh.read(4 * MB), b""):
                            h.update(chunk)
                            self.dups["done"] += len(chunk)
                    else:
                        h.update(fh.read(256 * 1024))
                        if st.st_size > 512 * 1024:
                            fh.seek(-256 * 1024, os.SEEK_END)
                            h.update(fh.read(256 * 1024))
                try:  # reading bumps "last opened"; put it back so Unused stays honest
                    os.utime(p, (st.st_atime, st.st_mtime), follow_symlinks=False)
                except OSError:
                    pass
                return h.hexdigest()

            result = []
            for size, paths in groups:
                buckets = {}
                for p in paths:
                    try:
                        buckets.setdefault(digest(p, False), []).append(p)
                    except OSError:
                        pass
                for ps in buckets.values():
                    if len(ps) < 2:
                        self.dups["done"] += size * len(ps)
                        continue
                    full = {}
                    for p in ps:
                        try:
                            full.setdefault(digest(p, True), []).append(p)
                        except OSError:
                            pass
                    result.extend({"size": entries[s[0]]["size"], "paths": s} for s in full.values() if len(s) > 1)
            result.sort(key=lambda g: -g["size"] * (len(g["paths"]) - 1))
            self.dups = {"state": "done", "groups": result, "finished": time.time()}
        except Exception:  # noqa: BLE001
            self.dups = {"state": "error", "error": traceback.format_exc()}

    def dup_view(self):
        d = dict(self.dups)
        if d.get("state") == "running":
            d["fraction"] = d["done"] / float(d["total"]) if d.get("total") else 0.0
        if d.get("state") != "done":
            return d
        groups = []
        for g in d["groups"]:
            items = [self.item(p) for p in g["paths"] if p in self.idx.entries]
            if len(items) > 1:
                items.sort(key=lambda x: x["activity"], reverse=True)
                groups.append({"size": g["size"], "wasted": g["size"] * (len(items) - 1), "items": items})
        d["groups"] = groups
        d["wasted"] = sum(g["wasted"] for g in groups)
        return d

    # ── deleting ──
    def check(self, p, mode):
        """Why `p` may not be removed with `mode`, or None if it may."""
        if not isinstance(p, str) or not p.startswith("/") or "\0" in p or os.path.normpath(p) != p:
            return "Invalid path"
        if not os.path.lexists(p):
            return "It no longer exists"
        parent = os.path.dirname(p)
        rparent = os.path.realpath(parent)
        in_home = rparent == HOME or rparent.startswith(HOME + os.sep)
        is_app = p.endswith(".app") and (rparent == "/Applications" or os.path.dirname(rparent) == "/Applications")
        if not (in_home or is_app):
            return "Only items in your home folder or /Applications can be removed"
        if in_home and rparent != parent:
            return "The path goes through a symbolic link"
        for n in NEVER:
            if p == n or p.startswith(n + os.sep):
                return "This folder holds sensitive data and is never touched"
        if mode == "clear":
            if (p in PROTECTED or parent == LIBRARY) and p not in CLEARABLE:
                return "Protected folder"
        elif p in PROTECTED or parent == LIBRARY:
            return "“%s” is a protected folder" % os.path.basename(p)
        if mode == "trash" and p.startswith(TRASH + os.sep):
            return "Already in the Trash; delete it permanently instead"
        if in_home:
            rel = os.path.relpath(parent, HOME)
            if rel != "." and any(os.path.splitext(part)[1].lower() in PACKAGE_EXTS for part in rel.split(os.sep)):
                return "It's inside a package (like a Photos library); manage it from its app"
        return None

    @staticmethod
    def _measure(idx, p):
        e = idx.entries.get(p)
        return e["size"] if e else du(p)

    @staticmethod
    def _purge(idx, p):
        """Forget p and everything below it."""
        pre = p + os.sep
        for k in [k for k in idx.entries if k == p or k.startswith(pre)]:
            del idx.entries[k]
        for k in [k for k in idx.children if k == p or k.startswith(pre)]:
            del idx.children[k]
        for s in idx.markers.values():
            for k in [k for k in s if k == p or k.startswith(pre)]:
                s.discard(k)
        kids = idx.children.get(os.path.dirname(p))
        if kids:
            kids.discard(p)

    def _refresh(self, idx, p, old):
        """Re-measure p after it changed on disk and fix every ancestor's size."""
        if not (p == HOME or p.startswith(HOME + os.sep)):
            return
        prev = idx.entries.get(p)
        self._purge(idx, p)
        new = 0
        if os.path.lexists(p):
            parent = os.path.dirname(p)
            pflags = flags_for(parent) if p != HOME else 0
            try:
                st = os.lstat(p)
            except OSError:
                st = None
            if st and stat.S_ISDIR(st.st_mode):
                cflags, mark = classify(parent, os.path.basename(p), p, pflags) if p != HOME else (0, None)
                new, n, nw = Walker(idx).walk(p, st.st_dev, cflags)
                if new >= DIR_TRACK_MIN or parent in LIST_ALL_CHILDREN or p in (HOME, TRASH) or prev:
                    idx.entries[p] = Walker.dir_entry(st, new, n, nw, own_flags(pflags, os.path.basename(p), p), mark)
                    if prev and prev.get("used"):
                        idx.entries[p]["used"] = prev["used"]
                    if mark:
                        idx.markers[mark].add(p)
            elif st:
                new = st.st_blocks * 512
                if new >= FILE_TRACK_MIN or parent in LIST_ALL_CHILDREN:
                    idx.entries[p] = Walker.file_entry(st, own_flags(pflags, os.path.basename(p), p))
            if p in idx.entries and p != HOME:
                idx.children.setdefault(parent, set()).add(p)
        delta = new - old
        cur = p
        while cur != HOME:
            cur = os.path.dirname(cur)
            e = idx.entries.get(cur)
            if e:
                e["size"] = max(0, e["size"] + delta)

    def delete(self, paths, mode):
        """mode: 'trash' (reversible), 'delete' (permanent) or 'clear' (permanently empty a folder)."""
        if mode not in ("trash", "delete", "clear"):
            return {"error": "Unknown mode"}
        paths = [p for p in paths if isinstance(p, str)]
        chosen = set(paths)

        def covered(p):  # an ancestor is being removed too
            cur = os.path.dirname(p)
            while cur not in ("/", ""):
                if cur in chosen:
                    return True
                cur = os.path.dirname(cur)
            return False

        results, ok_paths = [], []
        with self.lock:
            self.left_sizes = {}
            idx = self.idx
            if idx is None:
                return {"error": "Wait for the first scan to finish"}
            olds = {}
            for p in dict.fromkeys(paths):
                if covered(p):
                    continue
                err = self.check(p, mode)
                if err:
                    results.append({"path": p, "ok": False, "error": err})
                else:
                    olds[p] = self._measure(idx, p)
                    ok_paths.append(p)
            if mode == "trash":
                old_trash = self._measure(idx, TRASH)
                results += trash_paths(ok_paths)
            else:
                for p in ok_paths:
                    try:
                        if mode == "clear" and os.path.isdir(p) and not os.path.islink(p):
                            for child in os.scandir(p):
                                try:
                                    remove_path(child.path)
                                except OSError:
                                    pass
                        else:
                            remove_path(p)
                        results.append({"path": p, "ok": True})
                    except OSError as ex:
                        results.append({"path": p, "ok": False, "error": ex.strerror or str(ex)})
            by_path = {r["path"]: r for r in results}
            for p in ok_paths:
                if p not in by_path:
                    by_path[p] = {"path": p, "ok": False, "error": "Could not move it to the Trash"}
                    results.append(by_path[p])
            freed = 0
            for r in results:
                p = r["path"]
                if p not in olds:
                    continue
                self._refresh(idx, p, olds[p])
                if p in idx.apps and not os.path.lexists(p):
                    self.removed_apps[p] = idx.apps.pop(p)
                remaining = self._measure(idx, p) if os.path.lexists(p) else 0
                r["freed"] = max(0, olds[p] - remaining)
                if r["ok"] and remaining and mode != "trash":
                    r["partial"] = True
                freed += r["freed"]
            if mode == "trash" and ok_paths:
                self._refresh(idx, TRASH, old_trash)
            if self.scanning:
                self.touched += ok_paths
        self.save_snapshot()
        return {"results": results, "freed": freed, "mode": mode, "disk": self.disk()}

    def restore(self, items):
        """Undo a move to Trash: put items back where they came from."""
        out = []
        with self.lock:
            self.left_sizes = {}
            idx = self.idx
            if idx is None:
                return {"results": [], "disk": self.disk()}
            old_trash = self._measure(idx, TRASH)
            touched = False
            for it in items:
                src, dst = it.get("from", ""), it.get("to", "")
                if not (isinstance(src, str) and isinstance(dst, str)) or os.path.normpath(src) != src \
                        or os.path.dirname(src) != TRASH:
                    out.append({"path": dst, "ok": False, "error": "Invalid item"})
                    continue
                if os.path.lexists(dst) or not os.path.isdir(os.path.dirname(dst)) or self._restore_target_bad(dst):
                    out.append({"path": dst, "ok": False, "error": "Can't put it back there"})
                    continue
                try:
                    os.rename(src, dst)
                except OSError as ex:
                    out.append({"path": dst, "ok": False, "error": ex.strerror or str(ex)})
                    continue
                touched = True
                out.append({"path": dst, "ok": True})
                self._refresh(idx, dst, 0)
                if dst in self.removed_apps:
                    idx.apps[dst] = self.removed_apps.pop(dst)
                if self.scanning:
                    self.touched.append(dst)
            if touched:
                self._refresh(idx, TRASH, old_trash)
        self.save_snapshot()
        return {"results": out, "disk": self.disk()}

    @staticmethod
    def _restore_target_bad(dst):
        if os.path.normpath(dst) != dst:
            return True
        parent = os.path.realpath(os.path.dirname(dst))
        ok_home = parent == HOME or parent.startswith(HOME + os.sep)
        ok_app = dst.endswith(".app") and (parent == "/Applications" or os.path.dirname(parent) == "/Applications")
        return not (ok_home or ok_app)


def reveal(path):
    if os.path.lexists(path):
        subprocess.Popen(["open", "-R", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ───────────────────────────── updates ──────────────────────────────
# Both front-ends update the same way: ask GitHub for the latest release and, when it's newer than
# the app this file ships in, run the same install.sh a new user pastes into Terminal, with --update.

REPO = "gabrielesarria167-ai/MacSafe"
INSTALL_URL = "https://gabrielesarria167-ai.github.io/MacSafe/install.sh"
RELEASES_URL = "https://github.com/%s/releases" % REPO
UPDATE_FILE = os.path.join(SNAP_DIR, "update.json")
UPDATE_LOG = H("Library", "Logs", "MacSafe", "update.log")
UPDATE_EVERY = 12 * 3600
_update = {"state": "idle"}   # the install this engine started: idle | installing | failed


def app_version():
    """Version of the MacSafe.app this file ships in, or None when it runs from a source checkout."""
    plist = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Info.plist")
    try:
        with open(plist, "rb") as fh:
            return plistlib.load(fh).get("CFBundleShortVersionString")
    except (OSError, ValueError, plistlib.InvalidFileException):
        return None


def version_key(v):
    return tuple(int(n) for n in re.findall(r"\d+", v or ""))


def latest_release(timeout=6):
    """Newest published version on GitHub, e.g. "1.2". Goes through curl, which trusts the macOS
    keychain: python.org's Python has no certificates until its Install Certificates script runs."""
    try:
        out = subprocess.run(["curl", "-fsSL", "--max-time", str(timeout), "-H", "Accept: application/vnd.github+json",
                              "https://api.github.com/repos/%s/releases/latest" % REPO],
                             capture_output=True, timeout=timeout + 2).stdout
        tag = (json.loads(out.decode("utf-8")) or {}).get("tag_name") or ""
    except (OSError, subprocess.SubprocessError, ValueError, AttributeError):
        return None
    tag = tag.lstrip("vV")
    return tag if version_key(tag) else None


def update_status(force=False, timeout=6):
    """What the Update button and the `macsafe` command act on. Asks GitHub at most every 12 hours
    unless forced (Check for Updates…), and never from a source checkout."""
    current = app_version()
    try:
        with open(UPDATE_FILE, encoding="utf-8") as fh:
            saved = json.load(fh)
    except (OSError, ValueError):
        saved = {}
    latest, checked, error = saved.get("latest"), saved.get("checked", 0), None
    if current and (force or time.time() - checked > UPDATE_EVERY):
        found = latest_release(timeout)
        checked = time.time()
        if found:
            latest = found
        else:
            error = "Couldn't reach GitHub to check for updates."
        try:
            os.makedirs(SNAP_DIR, exist_ok=True)
            with open(UPDATE_FILE, "w", encoding="utf-8") as fh:
                json.dump({"latest": latest, "checked": checked}, fh)
        except OSError:
            pass
    available = bool(current and latest and version_key(latest) > version_key(current))
    return dict(_update, current=current, latest=latest, available=available, checked=checked or None,
                error=error or _update.get("error"), releases=RELEASES_URL)


def _last_line(path):
    try:
        with open(path, "rb") as fh:
            fh.seek(max(0, os.path.getsize(path) - 4096))
            lines = [l.strip() for l in fh.read().decode("utf-8", "replace").splitlines() if l.strip()]
    except OSError:
        return ""
    return lines[-1].lstrip("✗ ").strip() if lines else ""


def install_update(wait=False):
    """Run install.sh --update. The terminal command waits and shows its progress (wait=True).
    The Mac app can't wait: the installer quits the app once the download checks out, swaps in
    the new version and reopens it, so it runs detached and outlives this engine."""
    cmd = ["/bin/bash", "-c", 'set -o pipefail; curl -fsSL "$1" | bash -s -- --update', "macsafe-update", INSTALL_URL]
    if wait:
        return subprocess.call(cmd)
    if _update.get("state") == "installing":
        return None
    os.makedirs(os.path.dirname(UPDATE_LOG), exist_ok=True)
    with open(UPDATE_LOG, "ab") as log:
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                start_new_session=True, close_fds=True)
    _update.clear()
    _update["state"] = "installing"

    def watch():
        code = proc.wait()   # only returns while the app is still open, i.e. the update stopped early
        _update.clear()
        if code == 0:
            _update["state"] = "idle"
        else:
            _update.update(state="failed", error=_last_line(UPDATE_LOG) or "The update didn't install.")
    threading.Thread(target=watch, daemon=True).start()
    return None


# ───────────────────────────── HTTP (used by the Mac app) ──────────────────────────────

ENGINE = None


class Handler(BaseHTTPRequestHandler):
    server_version = "MacSafe"

    def log_message(self, fmt, *args):
        pass

    def _host_ok(self):
        return self.headers.get("Host", "") in ("127.0.0.1:%d" % PORT, "localhost:%d" % PORT)

    def _send(self, code, body):
        data = json.dumps(body).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _authed(self):
        return self._host_ok() and secrets.compare_digest(self.headers.get("X-Token", ""), TOKEN)

    def do_GET(self):
        if not self._authed():
            return self._send(403, {"error": "forbidden"})
        u = urlparse(self.path)
        q = {k: v[-1] for k, v in parse_qs(u.query).items()}
        e = ENGINE
        route = u.path[len("/api/"):] if u.path.startswith("/api/") else ""
        if route == "status":
            return self._send(200, e.status())
        if route == "update":
            return self._send(200, update_status(force=q.get("force") == "1"))
        if e.idx is None:
            return self._send(409, {"error": "The first scan hasn't finished yet"})

        def num(key, default):
            try:
                return float(q.get(key, default))
            except ValueError:
                return default
        with e.lock:
            if route == "overview":
                return self._send(200, e.overview())
            if route == "large":
                return self._send(200, {"items": e.large(num("min", 100), q.get("appdata", "1") == "1",
                                                         kind=q.get("kind") or None, q=q.get("q") or None)})
            if route == "unused":
                return self._send(200, e.unused(num("days", 90), num("min", 10), q.get("appdata") == "1"))
            if route == "caches":
                return self._send(200, {"items": e.caches()})
            if route == "clutter":
                return self._send(200, e.clutter())
            if route == "explore":
                return self._send(200, e.explore(q.get("path", HOME)))
            if route == "apps":
                return self._send(200, {"items": e.app_list()})
            if route == "duplicates":
                return self._send(200, e.dup_view())
        return self._send(404, {"error": "unknown endpoint"})

    def do_POST(self):
        if not self._authed():
            return self._send(403, {"error": "forbidden"})
        try:
            n = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(min(n, 4 * MB))) if n else {}
        except (ValueError, json.JSONDecodeError):
            return self._send(400, {"error": "bad json"})
        e = ENGINE
        route = urlparse(self.path).path[len("/api/"):]
        if route == "scan":
            e.start_scan()
            return self._send(200, {"ok": True})
        if route == "delete":
            paths = body.get("paths") or []
            if not isinstance(paths, list) or len(paths) > 5000:
                return self._send(400, {"error": "bad paths"})
            return self._send(200, e.delete(paths, body.get("mode", "trash")))
        if route == "restore":
            return self._send(200, e.restore(body.get("items") or []))
        if route == "duplicates":
            e.start_dups()
            return self._send(200, {"ok": True})
        if route == "update":
            if not update_status()["available"]:
                return self._send(409, {"error": "MacSafe is already up to date."})
            install_update()
            return self._send(200, {"ok": True})
        return self._send(404, {"error": "unknown endpoint"})


def serve(rescan_after):
    """Run the JSON API for the Mac app. Prints one handshake line, exits when stdin closes."""
    global ENGINE, PORT
    sys.setrecursionlimit(20000)
    ENGINE = Engine()
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    PORT = server.server_address[1]
    if ENGINE.idx is None or ENGINE.age > rescan_after:
        ENGINE.start_scan()
    print(json.dumps({"port": PORT, "token": TOKEN, "pid": os.getpid()}), flush=True)

    def watch_parent():
        try:
            while sys.stdin.buffer.read(1):
                pass
        except OSError:
            pass
        os._exit(0)  # the app quit (or crashed): don't linger
    threading.Thread(target=watch_parent, daemon=True).start()
    server.serve_forever()


def main():
    ap = argparse.ArgumentParser(description="MacSafe engine")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("serve", help="JSON API for the Mac app (handshake on stdout)")
    s.add_argument("--rescan-after", type=float, default=15 * 60, help="seconds before a snapshot is considered stale")
    sub.add_parser("scan", help="scan now and save a snapshot")
    args = ap.parse_args()
    if args.cmd == "serve":
        serve(args.rescan_after)
    elif args.cmd == "scan":
        sys.setrecursionlimit(20000)
        e = Engine(use_snapshot=False)
        e.start_scan()
        while e.scanning:
            time.sleep(0.3)
        print(json.dumps(e.status()["scan"]))


if __name__ == "__main__":
    main()
