#!/usr/bin/env python3
"""
MacSafe — terminal dashboard.

    macsafe             open the dashboard (instant: shows the last scan, rescans in the background)
    macsafe --report    print a one-shot summary and exit
    macsafe --app       open the Mac app instead
    macsafe --update    install the latest version now
    macsafe --light     force colours for a light terminal (--dark for a dark one; default: auto-detect)
    macsafe --no-mouse  keep mouse clicks for the terminal (e.g. to select text)

Every 12 hours at most, opening the dashboard checks for a newer MacSafe and installs it first.
--no-update (or MACSAFE_NO_UPDATE=1) skips that.

Keys are listed at the bottom of the screen; press ? for the full list.
"""
import argparse
import curses
import locale
import math
import os
import re
import select
import subprocess
import sys
import threading
import time
import unicodedata
from types import SimpleNamespace

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import engine as E  # noqa: E402

RESCAN_AFTER = 15 * 60
VIEWS = ["Overview", "Large", "Unused", "Caches", "Clutter", "Apps", "Explorer", "Duplicates"]
VIEWS_SHORT = ["Overview", "Large", "Unused", "Caches", "Clutter", "Apps", "Explorer", "Dupes"]
SIZE_STEPS = [10, 50, 100, 500, 1000]           # MB
PERIODS = [30, 90, 180, 365, 730]               # days
KIND_TAG = {"folder": "dir", "video": "vid", "image": "img", "audio": "aud", "archive": "zip",
            "installer": "dmg", "document": "doc", "3d": "3d", "vm": "vm", "data": "dat",
            "app": "app", "package": "pkg", "other": ""}
BLOCKS = " ▏▎▍▌▋▊▉█"
SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
WIDE = 110                                      # columns needed for the two-column overview
STALE = 90 * 86400                              # apps not opened for this long are highlighted

# Colour roles as xterm-256 indices. Normal text uses the terminal's own foreground (-1).
DARK = dict(text=-1, muted=245, faint=240, border=239, rule=237, frule=236, track=235, track_cur=238,
            cursor=236, chip=237, chip_fg=252, accent=75, on_accent=16, good=114, warn=221, bad=203, big=215,
            apps=75, files=215, appdata=176, system=103, free=239,
            apps_dim=24, files_dim=94, appdata_dim=96, system_dim=60, free_dim=236)
LIGHT = dict(text=-1, muted=243, faint=247, border=249, rule=252, frule=253, track=254, track_cur=251,
             cursor=254, chip=254, chip_fg=238, accent=32, on_accent=231, good=28, warn=130, bad=160, big=166,
             apps=32, files=208, appdata=133, system=60, free=252,
             apps_dim=153, files_dim=223, appdata_dim=182, system_dim=146, free_dim=255)
CATS = ("system", "appdata", "apps", "files", "free")   # donut order, clockwise from 12 o'clock
CAT_SHORT = {"system": "macOS", "appdata": "App data", "apps": "Apps", "files": "Files", "free": "Free"}
CAT_HINT = {"system": "⏎ see what's outside your home", "appdata": "⏎ explore ~/Library",
            "apps": "⏎ open the Apps view", "files": "⏎ explore your home folder", "free": ""}
CHIP_KEYS = {"⏎": 10, "space": 32, "esc": 27, "←": curses.KEY_LEFT, "→": curses.KEY_RIGHT}
WHEEL_UP = curses.BUTTON4_PRESSED
WHEEL_DOWN = getattr(curses, "BUTTON5_PRESSED", 0)
DOUBLE_CLICK = 0.4                              # seconds


# ───────────────────────────── text helpers ──────────────────────────────

def fmt_size(b):
    b = float(b or 0)
    if b < 1000:
        return "%d B" % b
    for unit in ("KB", "MB", "GB", "TB"):
        b /= 1000.0
        if b < 1000 or unit == "TB":
            return ("%.0f %s" if b >= 100 else "%.1f %s") % (b, unit)


def fmt_ago(ts):
    if not ts:
        return "never"
    d = time.time() - ts
    if d < 3600:
        return "just now"
    if d < 86400:
        return "%dh ago" % (d // 3600)
    days = int(d // 86400)
    if days == 1:
        return "yesterday"
    if days < 45:
        return "%d days ago" % days
    if days < 548:
        return "%d months ago" % round(days / 30.4)
    return "%.1f years ago" % (days / 365.0)


def fmt_period(days):
    return {30: "1 month", 90: "3 months", 180: "6 months", 365: "1 year", 730: "2 years"}.get(days, "%d days" % days)


def bar(frac, width):
    frac = max(0.0, min(1.0, frac))
    cells = frac * width
    full = int(cells)
    rest = int((cells - full) * 8)
    s = "█" * full + (BLOCKS[rest] if full < width and rest else "")
    return s.ljust(width)


def cwidth(ch):
    if ch < "ᄀ":
        return 1
    if unicodedata.combining(ch):
        return 0
    return 2 if unicodedata.east_asian_width(ch) in "WF" else 1


def dwidth(s):
    return sum(cwidth(c) for c in s)


def clean(s):
    s = unicodedata.normalize("NFC", str(s))
    return s if s.isprintable() else E.clean_text(s)


def clip(s, w):
    s = clean(s)
    if w <= 0:
        return ""
    if dwidth(s) <= w:
        return s
    out, used = [], 0
    for c in s:
        cw = cwidth(c)
        if used + cw > w - 1:
            break
        out.append(c)
        used += cw
    return "".join(out) + "…"


def wrap(text, w):
    lines, line = [], ""
    for word in text.split():
        if line and dwidth(line) + 1 + dwidth(word) > w:
            lines.append(line)
            line = word
        else:
            line = (line + " " + word).strip()
    return lines + [line] if line else lines


def pad(s, w, right=False):
    s = clip(s, w)
    gap = " " * max(0, w - dwidth(s))
    return gap + s if right else s + gap


def chips_width(chips):
    return sum(len(k) + len(label) + 5 for k, label in chips) - 2 if chips else 0


# ───────────────────────────── charts ──────────────────────────────

_DONUTS = {}


def donut_cells(W, H, segs, hole=0.6):
    """A ring drawn with half blocks: every cell holds two square pixels (▀ = top in fg, bottom in bg).
    segs is a tuple of (fraction, colour) clockwise from 12 o'clock; a colour of None leaves a gap.
    Cells are (char, fg, bg, reverse). Colour goes in the cell background wherever it can, because
    background always fills the whole cell while block glyphs can come up short (fonts, line spacing)
    and leave stripes; a half-empty cell is the coloured background with the empty half drawn reversed."""
    key = (W, H, segs, hole)
    if key in _DONUTS:
        return _DONUTS[key]
    R = W / 2.0 - 0.25
    r = R * hole
    cx, cy = W / 2.0, float(H)

    def px(i, j):
        dx, dy = i + 0.5 - cx, j + 0.5 - cy
        d = math.hypot(dx, dy)
        if d > R or d < r:
            return None
        t = (math.atan2(dx, -dy) / (2 * math.pi)) % 1.0
        acc = 0.0
        for f, c in segs:
            acc += f
            if t < acc:
                return c
        return segs[-1][1]

    rows = []
    for row in range(H):
        cells = []
        for col in range(W):
            top, bot = px(col, 2 * row), px(col, 2 * row + 1)
            if top is None and bot is None:
                cells.append(None)
            elif top == bot:
                cells.append((" ", -1, top, False))
            elif top is None:
                cells.append(("▀", bot, -1, True))
            elif bot is None:
                cells.append(("▄", top, -1, True))
            else:
                cells.append(("▀", top, bot, False))
        rows.append(cells)
    _DONUTS[key] = rows
    return rows


def donut_seg_at(W, H, fracs, col, row, hole=0.6):
    """Which segment of donut_cells(W, H, …) the cell (col, row) belongs to, or None for the hole/outside."""
    R = W / 2.0 - 0.25
    dx, dy = col + 0.5 - W / 2.0, 2 * row + 1 - float(H)
    d = math.hypot(dx, dy)
    if d > R + 1 or d < R * hole - 1:
        return None
    t = (math.atan2(dx, -dy) / (2 * math.pi)) % 1.0
    acc = 0.0
    for i, f in enumerate(fracs):
        acc += f
        if t < acc:
            return i
    return len(fracs) - 1


class Canvas:
    """The whole screen is painted here every frame, then copied to curses in runs of equal colour."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        blank = (" ", -1, None, False, False)
        self.cells = [[blank] * w for _ in range(h)]


class Line:
    """One screen row. A row that spans side-by-side panels has cols = [(x, w, item or None)] per panel."""
    __slots__ = ("kind", "text", "item", "fg", "bold", "draw", "meta", "cols")

    def __init__(self, kind, text="", item=None, fg=None, bold=False, draw=None, meta=None, cols=None):
        self.kind, self.text, self.item, self.fg, self.bold, self.draw, self.meta, self.cols = \
            kind, text, item, fg, bold, draw, meta or {}, cols


class Dashboard:
    def __init__(self, scr, engine, light=False, mouse=True):
        self.scr = scr
        self.mouse = mouse
        self.e = engine
        self.view = 0
        self.lines = []
        self.cur = 0
        self.col = 0                 # which panel the cursor is in, on rows that span several (Overview)
        self.top = 0
        self.follow = True           # keep the cursor on screen (off while scrolling past the last item)
        self.sel = set()
        self.msg = ""
        self.msg_kind = "info"
        self.msg_until = 0
        self.prompt = None           # (text, {key: callback}, answer chips, permanent)
        self.prompt_hint = ""
        self.last_trash = []
        self.explore_path = E.HOME
        self.large_min = 100
        self.large_appdata = True
        self.unused_days = 90
        self.unused_min = 10
        self.unused_appdata = False
        self.apps_days = 0
        self.dl_days = 90
        self.sort = "size"
        self.show_help = False
        self.help_top = 0
        self.was_scanning = engine.scanning
        self.update = None           # engine.update_status(): fills in shortly after start
        self.want_update = False     # set when the user confirms; main() installs once curses is gone
        threading.Thread(target=self._check_update, daemon=True).start()
        self.cv = None
        self.row_bg = None
        self._pairs = {}
        self._attrs = {}
        self.hits = []               # clickable regions of the last frame: (y, x0, x1, key, callback)
        self.last_click = None       # (time, key) for spotting double clicks
        self._theme(light)

    # ── colours ──
    def _theme(self, light):
        curses.start_color()
        try:
            curses.use_default_colors()
            self.default_ok = True
        except curses.error:
            self.default_ok = False
        if curses.COLORS >= 256:
            t = dict(LIGHT if light else DARK)
        else:
            c = curses
            t = dict(text=-1, muted=-1, faint=-1, border=-1, rule=-1, frule=-1, track=-1, track_cur=-1,
                     cursor=c.COLOR_BLUE, chip=-1, chip_fg=-1, accent=c.COLOR_BLUE, on_accent=c.COLOR_WHITE,
                     good=c.COLOR_GREEN, warn=c.COLOR_YELLOW, bad=c.COLOR_RED, big=c.COLOR_YELLOW,
                     apps=c.COLOR_BLUE, files=c.COLOR_YELLOW, appdata=c.COLOR_MAGENTA, system=c.COLOR_CYAN, free=None)
            t.update({k + "_dim": t[k] for k in CATS})
        self.t = SimpleNamespace(**t)

    def attr(self, fg, bg, bold, rev=False):
        key = (fg, bg, bold, rev)
        a = self._attrs.get(key)
        if a is None:
            f = -1 if fg is None else fg
            b = -1 if bg is None else bg
            if not self.default_ok:
                f = curses.COLOR_WHITE if f == -1 else f
                b = curses.COLOR_BLACK if b == -1 else b
            p = self._pairs.get((f, b))
            if p is None:
                p = len(self._pairs) + 1
                try:
                    curses.init_pair(p, f, b)
                except (curses.error, ValueError, OverflowError):
                    p = 0
                self._pairs[(f, b)] = p
            a = curses.color_pair(p) | (curses.A_BOLD if bold else 0) | (curses.A_REVERSE if rev else 0)
            self._attrs[key] = a
        return a

    # ── painting ──
    def put(self, y, x, text, fg=-1, bg=None, bold=False, rev=False):
        cv = self.cv
        if y < 0 or y >= cv.h:
            return x
        if bg is None:
            bg = self.row_bg
        row = cv.cells[y]
        for ch in str(text):
            cw = cwidth(ch)
            if cw == 0:
                continue
            if 0 <= x < cv.w:
                if cw == 2 and x + 1 >= cv.w:
                    ch, cw = " ", 1
                row[x] = (ch, fg, bg, bold, rev)
                if cw == 2:
                    row[x + 1] = ("", fg, bg, bold, rev)
            x += cw
        return x

    def fill(self, y, x, w, bg):
        self.put(y, x, " " * max(0, w), -1, bg)

    def blit(self):
        scr, cv = self.scr, self.cv
        for y, row in enumerate(cv.cells):
            n = cv.w - (1 if y == cv.h - 1 else 0)     # curses can't write the bottom-right cell
            x = 0
            while x < n:
                style = row[x][1:]
                j, buf = x, []
                while j < n and row[j][1:] == style:
                    buf.append(row[j][0])
                    j += 1
                try:
                    scr.addstr(y, x, "".join(buf), self.attr(*style))
                except curses.error:
                    pass
                x = j
        scr.noutrefresh()
        curses.doupdate()

    def hbar(self, y, x, w, frac, fg, track):
        """Horizontal bar with 1/8-cell precision on a background-coloured track."""
        frac = max(0.0, min(1.0, frac))
        cells = frac * w
        full = int(cells)
        rem = int(round((cells - full) * 8))
        if rem == 8:
            full, rem = full + 1, 0
        if frac > 0 and full == 0 and rem == 0:
            rem = 1
        for i in range(w):
            if i < full:
                if fg in (None, -1):    # no colour to paint the background with (8-colour terminals)
                    self.put(y, x + i, "█", fg, track)
                else:                   # background fills the whole cell; █ can fall short of it
                    self.put(y, x + i, " ", fg, fg)
            elif i == full and rem:
                self.put(y, x + i, BLOCKS[rem], fg, track)
            else:
                self.put(y, x + i, " ", fg, track)

    def chips(self, y, x, chips, keyboard_only=()):
        """Key hints; clicking one presses its key. Keys in keyboard_only are drawn in red and ignore clicks."""
        t = self.t
        for k, label in chips:
            x0 = x
            if k in keyboard_only:
                x = self.put(y, x, " %s " % k, t.on_accent, t.bad, bold=True)
                x = self.put(y, x, " " + label, t.bad, bold=True)
                self.hit(y, x0, x, ("chip", k), lambda kind, mx, my: self._keyboard_only())
            else:
                x = self.put(y, x, " %s " % k, t.chip_fg, t.chip)
                x = self.put(y, x, " " + label, t.muted)
                code = CHIP_KEYS.get(k, ord(k) if len(k) == 1 else None)
                if code is not None:
                    self.hit(y, x0, x, ("chip", k), lambda kind, mx, my, code=code: self.handle(code))
            x += 2
        return x

    def _keyboard_only(self):
        self.prompt_hint = "Press y on the keyboard to confirm — a click can't confirm a permanent action."


    def hit(self, y, x0, x1, key, cb):
        """Make screen cells y, x0..x1-1 clickable; cb(kind, x, y) with kind click / double / right."""
        self.hits.append((y, x0, x1, key, cb))

    # ── helpers ──
    def say(self, text, kind="info", secs=6):
        self.msg, self.msg_kind, self.msg_until = text, kind, time.time() + secs

    def items(self):
        return [ln for ln in self.lines if ln.kind == "item"]

    def all_items(self):
        out = []
        for ln in self.items():
            out += [c[2] for c in ln.cols if c[2]] if ln.cols else [ln.item]
        return out

    def current(self):
        if 0 <= self.cur < len(self.lines) and self.lines[self.cur].kind == "item":
            ln = self.lines[self.cur]
            if ln.cols:
                return ln.cols[self.col][2] if self.col < len(ln.cols) else None
            return ln.item
        return None

    def targets(self):
        if self.sel:
            return [it for it in self.all_items() if it["path"] in self.sel]
        it = self.current()
        return [it] if it and not it.get("virtual") else []

    def locate(self, path):
        for i, ln in enumerate(self.lines):
            if ln.kind != "item":
                continue
            for ci, c in enumerate(ln.cols or [(0, 0, ln.item)]):
                if c[2] and c[2]["path"] == path:
                    return i, ci
        return None

    def select(self, i, ci=0):
        self.cur, self.col, self.follow = i, ci, True

    def width(self):
        return self.scr.getmaxyx()[1]

    # ── building views ──
    def rebuild(self, keep_cursor=True):
        old_path = (self.current() or {}).get("path") if keep_cursor else None
        if self.e.idx is None:
            lines = self.build_first_scan()
        else:
            with self.e.lock:
                lines = getattr(self, "build_" + VIEWS[self.view].lower())()
        self.lines = [Line("blank")] + lines
        self.sel &= {it["path"] for it in self.all_items()}
        self.cur = 0
        found = self.locate(old_path) if old_path else None
        if found:
            self.cur, self.col = found
        self._snap_cursor(1)
        self.follow = True

    def _sorted(self, items):
        if self.sort == "age":
            return sorted(items, key=lambda x: x.get("activity") or 0)
        if self.sort == "name":
            return sorted(items, key=lambda x: x["name"].lower())
        return sorted(items, key=lambda x: -x["size"])

    def _item_lines(self, items, **meta):
        return [Line("item", item=it, meta=meta) for it in self._sorted(items)]

    def bar_line(self, text, sub="", chips=None, fg=None):
        return Line("bar", text, fg=fg, meta={"sub": sub, "chips": chips or []})

    def head(self, text, sub=""):
        return Line("head", text, meta={"sub": sub})

    def none(self, text="none"):
        return Line("text", "   " + text, fg="muted")

    def build_first_scan(self):
        return [Line("text", "Scanning your Mac for the first time…", bold=True),
                Line("text", "This takes about a minute. Everything shows up here as soon as it's done.", fg="muted"),
                Line("blank"),
                Line("custom", draw=self._draw_scan_progress)]

    # overview ─────────────────────────────────────────────
    def build_overview(self):
        o = self.e.overview()
        d = o["disk"]
        t = self.t
        w = self.width()
        wide = w >= WIDE
        L = []
        if not self.e.status()["fda"]:
            L += [Line("text", "! No Full Disk Access, so some folders were skipped — System Settings › "
                               "Privacy & Security › Full Disk Access.", fg="warn"), Line("blank")]
        total = float(d["total"]) or 1.0
        by = {s["key"]: s for s in o["breakdown"]}
        cats = [(k, by[k]["label"], by[k]["size"]) for k in CATS[:-1] if k in by]
        cats.append(("free", "Free", d["free"]))
        disk = self._disk_rows(cats, d, total, wide)
        folders = self._folder_rows(o["top"], wide)
        wins, freeable = self._win_rows(o["wins"])
        outside = self._outside_rows(o)
        wins_rt = ("%s to free" % fmt_size(freeable)) if freeable else "all tidy"
        if wide:
            lw = 68
            rx = 1 + lw + 2
            rw = w - 1 - rx
            L += self.columns(self.panel(1, lw, "Macintosh HD", fmt_size(d["total"]), None, disk, 15),
                              self.panel(rx, rw, "Biggest folders", "⏎ explore", None, folders, 15))
            L.append(Line("blank"))
            h = max(len(wins), len(outside))
            cols = [self.panel(1, lw, "Quick wins", wins_rt, t.good, wins, h)]
            if outside:
                cols.append(self.panel(rx, rw, "Outside your home", "⏎ Finder", None, outside, h))
            L += self.columns(*cols)
        else:
            pw = w - 2
            L += self.columns(self.panel(1, pw, "Macintosh HD", fmt_size(d["total"]), None, disk, 9))
            L.append(Line("blank"))
            L += self.columns(self.panel(1, pw, "Biggest folders", "⏎ explore", None, folders))
            L.append(Line("blank"))
            L += self.columns(self.panel(1, pw, "Quick wins", wins_rt, t.good, wins))
            if outside:
                L.append(Line("blank"))
                L += self.columns(self.panel(1, pw, "Outside your home", "⏎ Finder", None, outside))
        return L

    def _disk_rows(self, cats, d, total, wide):
        """Donut + legend. Every legend row is selectable, and so is every slice of the donut (by mouse);
        while a category is selected its slice stays lit, the others dim and the centre shows its size."""
        t = self.t
        W, H, top, dcol, lcol, n = (26, 13, 1, 1, 31, 15) if wide else (18, 9, 0, 1, 24, 9)
        fracs = tuple(size / total for _, _, size in cats)
        reveal = {"apps": "/Applications", "appdata": E.LIBRARY, "files": E.HOME}
        items = [{"path": "cat:" + k, "name": label, "size": size, "cat": k, "virtual": True, "reveal": reveal.get(k)}
                 for k, label, size in cats]
        used = d["used"]
        pct = int(round(used / total * 100))
        if wide:
            overall = [(fmt_size(used), t.text, True), ("of " + fmt_size(d["total"]), t.muted, False),
                       ("%d%% used" % pct, t.muted, False)]
        else:
            overall = [(fmt_size(used), t.text, True), ("used", t.muted, False), ("%d%%" % pct, t.muted, False)]
        cy = top + H // 2 - 1
        ly = top + H // 2 - 2

        def spotlight():
            it = self.current()
            return it if it and it.get("cat") else None

        def click(kind, mx, x, dr):
            seg = donut_seg_at(W, H, fracs, mx - x - dcol, dr)
            found = self.locate(items[seg]["path"]) if seg is not None else None
            if found:
                self.select(*found)
                if kind == "double":
                    self.do_open()

        def row(r):
            def draw(y, x, cw, cur):
                sel = spotlight()
                on = sel["cat"] if sel else None
                dr = r - top
                if 0 <= dr < H:
                    segs = tuple((f, getattr(t, k if on in (None, k) else k + "_dim")) for f, (k, _, _) in zip(fracs, cats))
                    for c, cell in enumerate(donut_cells(W, H, segs)[dr]):
                        if cell:
                            ch, fg, bg, rev = cell
                            self.put(y, x + dcol + c, ch, fg, bg, rev=rev)
                    self.hit(y, x + dcol, x + dcol + W, ("donut", r),
                             lambda kind, mx, my: click(kind, mx, x, dr))
                k = r - cy
                if 0 <= k < 3:
                    if sel:
                        share = "%d%%" % round(sel["size"] / total * 100)
                        center = [(fmt_size(sel["size"]), t.text if on == "free" else getattr(t, on) or t.text, True),
                                  (CAT_SHORT[on], t.muted, False), (share + (" of disk" if wide else ""), t.muted, False)]
                    else:
                        center = overall
                    s, fg, b = center[k]
                    self.put(y, x + dcol + W // 2 - dwidth(s) // 2, s, fg, -1, bold=b)
                k = r - ly
                if 0 <= k < len(cats):
                    key, label, size = cats[k]
                    free = key == "free"
                    color = getattr(t, key)
                    lx = x + lcol
                    self.put(y, lx, "●", t.muted if color is None else color)
                    self.put(y, lx + 2, pad(label, 17), t.muted if free and not cur else t.text, bold=cur)
                    self.put(y, lx + 20, pad(fmt_size(size), 8, True), t.text, bold=not free)
                    self.put(y, lx + 29, pad("%d%%" % round(size / total * 100), 4, True), t.muted)
                if r == ly + len(cats) + 1 and on:
                    self.put(y, x + lcol + 2, clip(CAT_HINT[on], cw - lcol - 2), t.muted)
            return draw
        return [(row(r), items[r - ly], lcol - 1) if 0 <= r - ly < len(items) else (row(r), None)
                for r in range(n)]

    def _folder_rows(self, top, wide):
        t = self.t
        mx = float(top[0]["size"]) if top else 1.0

        def row(it):
            color = t.appdata if it["name"] == "Library" or it["name"].startswith(".") else t.files

            def draw(y, x, cw, cur):
                self.put(y, x, pad(it["name"], 13), t.text, bold=cur)
                self.hbar(y, x + 14, max(4, cw - 24), it["size"] / mx, color, t.track_cur if cur else t.track)
                self.put(y, x + cw - 8, pad(fmt_size(it["size"]), 8, True), t.text, bold=True)
            return draw

        def legend(y, x, cw, cur):
            xx = self.put(y, x, "●", t.appdata)
            xx = self.put(y, xx, " app data & caches   ", t.muted)
            xx = self.put(y, xx, "●", t.files)
            self.put(y, xx, " your files", t.muted)

        rows = [(None, None)] if wide else []
        rows += [(row(it), it) for it in top]
        if not top:
            rows.append((lambda y, x, cw, cur: self.put(y, x, "Nothing here yet.", t.muted), None))
        rows += [(None, None), (legend, None)]
        return rows

    def _win_rows(self, wins):
        t = self.t
        spec = [("Safe-to-clear caches", "caches", "4", "Caches"),
                ("node_modules & virtualenvs", "dev", "5", "Clutter"),
                ("Installers & disk images", "installers", "5", "Clutter"),
                ("Downloads untouched 3+ months", "downloads", "5", "Clutter"),
                ("iPhone / iPad backups", "backups", "5", "Clutter")]

        def row(label, size, key, view):
            def draw(y, x, cw, cur):
                self.put(y, x, pad(label, 30), t.text, bold=cur)
                self.put(y, x + 31, pad(fmt_size(size), 8, True), t.text, bold=True)
                self.chips(y, x + 42, [(key, view)])
            return draw

        def trash(y, x, cw, cur):
            if wins["trash"]:
                self.put(y, x, pad("Trash", 30), t.text, bold=cur)
                self.put(y, x + 31, pad(fmt_size(wins["trash"]), 8, True), t.text, bold=True)
                self.chips(y, x + 42, [("E", "empty")])
            else:
                self.put(y, x, pad("Trash", 30), t.muted)
                self.put(y, x + 31, pad("empty", 8, True), t.muted)
                self.put(y, x + 42, "✓", t.good)

        rows = [(None, None)]
        rows += [(row(label, wins[k], key, view), {"path": "win:" + k, "name": label, "size": wins[k],
                                                   "virtual": True, "goto": VIEWS.index(view)})
                 for label, k, key, view in spec if wins[k]]
        rows += [(trash, {"path": "win:trash", "name": "Trash", "size": wins["trash"], "virtual": True,
                          "trash": True, "reveal": E.TRASH}), (None, None)]
        return rows, sum(wins.values())

    def _outside_rows(self, o):
        t = self.t
        if not o["outside"]:
            return []
        mx = float(max(x["size"] for x in o["outside"])) or 1.0
        default = ["Managed by macOS or other tools."]
        if o["snapshots"]:
            default.append("+ %d Time Machine snapshot%s, removed by macOS when it needs space." % (
                o["snapshots"], "" if o["snapshots"] == 1 else "s"))

        def row(x_):
            def draw(y, x, cw, cur):
                self.put(y, x, pad(x_["name"], 20), t.text, bold=cur)
                self.hbar(y, x + 21, max(4, cw - 31), x_["size"] / mx, t.system, t.track_cur if cur else t.track)
                self.put(y, x + cw - 8, pad(fmt_size(x_["size"]), 8, True), t.text, bold=True)
            return draw

        def note(i):
            def draw(y, x, cw, cur):
                it = self.current()
                text = wrap(it["note"], cw) if it and it.get("outside") else [clip(s, cw) for s in default]
                if i < len(text):
                    self.put(y, x, text[i], t.muted)
            return draw

        rows = [(None, None)]
        rows += [(row(x_), dict(x_, virtual=True, outside=True, reveal=x_["path"])) for x_ in o["outside"]]
        rows += [(None, None), (note(0), None), (note(1), None)]
        return rows

    def panel(self, x, w, title, rt, rtc, rows, height=0):
        """A rounded box as one spec per screen row: (draw(y, cur), item). A row given as (draw, item, hl)
        only highlights from hl columns in, so the cursor can sit on the legend beside the donut."""
        specs = [(lambda y, cur: self._panel_top(y, x, w, title, rt, rtc), None)]
        for i in range(max(height, len(rows))):
            d, item, hl = (tuple(rows[i]) + (0,))[:3] if i < len(rows) else (None, None, 0)
            specs.append((lambda y, cur, d=d, item=item, hl=hl:
                          self._panel_side(y, x, w, d, cur and item is not None, hl), item))
        specs.append((lambda y, cur: self.put(y, x, "╰" + "─" * (w - 2) + "╯", self.t.border), None))
        return {"x": x, "w": w, "specs": specs}

    def _panel_top(self, y, x, w, title, rt, rtc):
        t = self.t
        self.put(y, x, "╭" + "─" * (w - 2) + "╮", t.border)
        self.put(y, x + 2, " %s " % title, t.text, bold=True)
        if rt:
            self.put(y, x + w - 4 - dwidth(rt), " %s " % rt, rtc or t.muted)

    def _panel_side(self, y, x, w, draw, cur, hl=0):
        t = self.t
        self.put(y, x, "│", t.border)
        self.put(y, x + w - 1, "│", t.border)
        if cur:
            self.row_bg = t.cursor
            self.fill(y, x + 1 + hl, w - 2 - hl, t.cursor)
            self.put(y, x + 1 + hl, "▌", t.accent)
        if draw:
            draw(y, x + 2, w - 4, cur)
        self.row_bg = None

    def columns(self, *panels):
        """Merge side-by-side panels into screen rows; each panel is a column the cursor can be in."""
        lines = []
        for r in range(max(len(p["specs"]) for p in panels)):
            parts = [p["specs"][r] if r < len(p["specs"]) else (None, None) for p in panels]
            cols = [(p["x"], p["w"], it) for p, (_, it) in zip(panels, parts)]
            first = next((it for _, _, it in cols if it is not None), None)

            def draw(y, w, cur, fns=[f for f, _ in parts]):
                for ci, f in enumerate(fns):
                    if f:
                        f(y, cur and self.col == ci)
            lines.append(Line("item" if first is not None else "custom", item=first, draw=draw,
                              cols=cols if first is not None else None))
        return lines

    # list views ─────────────────────────────────────────────
    def build_large(self):
        items = self.e.large(self.large_min, self.large_appdata)
        L = [self.bar_line("Files bigger than %s" % fmt_size(self.large_min * E.MB),
                           "" if self.large_appdata else " · app data hidden",
                           [("f", "min size"), ("a", "app data: %s" % ("shown" if self.large_appdata else "hidden")),
                            ("s", "sort: " + self.sort)]), Line("blank")]
        if not items:
            return L + [Line("text", "Nothing that big. Press f to lower the minimum size.", fg="muted")]
        return L + [Line("colhead")] + self._item_lines(items, max=items[0]["size"])

    def build_unused(self):
        u = self.e.unused(self.unused_days, self.unused_min, self.unused_appdata)
        L = [self.bar_line("Not opened or changed in %s" % fmt_period(self.unused_days),
                           " · bigger than %s" % fmt_size(self.unused_min * E.MB),
                           [("p", "period"), ("f", "min size"),
                            ("a", "app data: %s" % ("shown" if self.unused_appdata else "hidden")),
                            ("s", "sort: " + self.sort)]), Line("blank"), Line("colhead")]
        mx = max([i["size"] for i in u["folders"] + u["files"]] or [1])
        L.append(self.head("Folders", "%d · %s" % (len(u["folders"]), fmt_size(sum(i["size"] for i in u["folders"])))))
        L += self._item_lines(u["folders"], max=mx) or [self.none()]
        L.append(Line("blank"))
        L.append(self.head("Files", "%d · %s" % (len(u["files"]), fmt_size(sum(i["size"] for i in u["files"])))))
        L += self._item_lines(u["files"], max=mx) or [self.none("none — try a shorter period (p) or a smaller size (f)")]
        return L

    def build_caches(self):
        items = self.e.caches()
        safe = sum(c["size"] for c in items if c["safety"] == "safe" and c["action"] == "clear" and c["path"] != E.TRASH)
        L = [self.bar_line("%s can be cleared safely" % fmt_size(safe), " · ✓ safe  ! review first",
                           [("c", "clear selected"), ("C", "clear all safe"), ("t", "trash review items")]),
             Line("blank"), Line("colhead")]
        groups = {}
        for c in items:
            groups.setdefault(c["group"], []).append(c)
        mx = max([c["size"] for c in items] or [1])
        for g in ("Trash", "App caches", "Developer", "macOS caches", "System"):
            if g not in groups:
                continue
            L.append(self.head(g, fmt_size(sum(c["size"] for c in groups[g]))))
            L += [Line("item", item=c, meta={"max": mx, "cache": True}) for c in self._sorted(groups[g])]
            L.append(Line("blank"))
        return L

    def build_clutter(self):
        c = self.e.clutter()
        cutoff = time.time() - self.dl_days * E.DAY
        dls = [i for i in c["downloads"] if i["activity"] < cutoff]
        mx = max([i["size"] for k in ("downloads", "installers", "dev", "backups") for i in c[k]] or [1])
        L = [self.bar_line("Leftovers that are usually safe to remove", "",
                           [("p", "downloads: %s" % ("older than " + fmt_period(self.dl_days) if self.dl_days else "all"))]),
             Line("blank"), Line("colhead")]
        dl_title = "Downloads older than %s" % fmt_period(self.dl_days) if self.dl_days else "All downloads"
        sections = [(dl_title, dls, "ages", ""),
                    ("Installers & disk images", c["installers"], None, ""),
                    ("node_modules & Python virtualenvs", c["dev"], "dev", " · date is the project's last activity"),
                    ("iPhone / iPad backups", c["backups"], "backup", "")]
        for title, items, tag, note in sections:
            L.append(self.head(title, "%d · %s%s" % (len(items), fmt_size(sum(i["size"] for i in items)), note)))
            L += self._item_lines(items, max=mx, tag=tag) or [self.none()]
            L.append(Line("blank"))
        return L

    def build_apps(self):
        apps = self.e.app_list()
        if self.apps_days:
            cutoff = time.time() - self.apps_days * E.DAY
            apps = [a for a in apps if (a["used"] or 0) < cutoff]
        sub = " · %s" % fmt_size(sum(a["size"] for a in apps))
        if self.apps_days:
            sub += " · not opened in %s" % fmt_period(self.apps_days)
        L = [self.bar_line("%d app%s" % (len(apps), "" if len(apps) == 1 else "s"), sub,
                           [("p", "last opened: %s" % ("any" if not self.apps_days else "%s+" % fmt_period(self.apps_days))),
                            ("s", "sort: " + self.sort)]), Line("blank")]
        if not apps:
            return L + [Line("text", "No apps match. Press p to change the filter.", fg="muted")]
        return L + [Line("colhead")] + self._item_lines(apps, max=max(a["size"] for a in apps), app=True)

    def build_explorer(self):
        x = self.e.explore(self.explore_path)
        self.explore_path = x["path"]
        crumbs = " › ".join(c["name"] for c in x["crumbs"])
        L = [self.bar_line(crumbs, " · " + fmt_size(x["size"]), [("⏎", "open"), ("←", "up")]), Line("blank")]
        L[0].meta["crumbs"] = [(c["name"], c["path"]) for c in x["crumbs"]]
        if not x["items"]:
            return L + [Line("text", "Nothing big enough to list in here.", fg="muted")]
        L += [Line("colhead")] + self._item_lines(x["items"], max=x["items"][0]["size"], noloc=True)
        if x["other"] > 0:
            other = x["other"]

            def draw(y, w, cur):
                g = self.geometry(w, False, True)
                self.put(y, g["name"], "(smaller items)", self.t.muted)
                self.put(y, g["size"], pad(fmt_size(other), 8, True), self.t.muted)
            L.append(Line("custom", draw=draw))
        return L

    def build_duplicates(self):
        d = self.e.dup_view()
        st = d.get("state")
        if st == "idle":
            return [self.bar_line("Find identical files", " · 5 MB and bigger, anywhere in your folders", [("F", "find")]),
                    Line("blank"),
                    Line("text", "Press F to start. It reads the files to compare them, so it can take a while.",
                         fg="muted")]
        if st == "running":
            return [self.bar_line("Comparing files…"), Line("blank"),
                    Line("custom", draw=lambda y, w, cur: self._draw_progress(y, w, d.get("fraction", 0)))]
        if st == "error":
            return [Line("text", "Duplicate search failed: " + d.get("error", "")[-200:], fg="bad")]
        groups = d["groups"]
        L = [self.bar_line("%d set%s of identical files" % (len(groups), "" if len(groups) == 1 else "s"),
                           " · %s could be freed" % fmt_size(d["wasted"]), [("K", "select extra copies")]),
             Line("blank")]
        if not groups:
            return L + [Line("text", "No duplicates found. ✓", fg="good")]
        L.append(Line("colhead"))
        for g in groups:
            L.append(self.head("%d copies" % len(g["items"]), "%s each" % fmt_size(g["size"])))
            for i, it in enumerate(g["items"]):
                L.append(Line("item", item=it, meta={"max": groups[0]["size"], "dup_first": i == 0}))
            L.append(Line("blank"))
        return L

    # ── drawing ──
    def geometry(self, w, show_loc, tag):
        W = w - 1                                   # last column is the scrollbar
        bar_w = 16 if W >= 110 else (10 if W >= 90 else 8)
        name_x = 4 + (4 if tag else 0)
        rest = W - name_x - (8 + 2 + bar_w + 2 + 13 + 2) - 1
        if show_loc and rest >= 40:
            name_w = max(20, rest * 55 // 100)
            loc_w = rest - name_w - 2
        else:
            name_w, loc_w = rest, 0
        size_x = name_x + name_w + 2
        bar_x = size_x + 10
        age_x = bar_x + bar_w + 2
        return {"name": name_x, "name_w": name_w, "size": size_x, "bar": bar_x, "bar_w": bar_w,
                "age": age_x, "loc": age_x + 15, "loc_w": loc_w}

    def _view_layout(self):
        """(show location column, show kind tag) for the current view."""
        return self.view != 6, self.view != 5

    def draw_colhead(self, y, w):
        t = self.t
        show_loc, tag = self._view_layout()
        g = self.geometry(w, show_loc, tag)
        name = {1: "FILE", 3: "CACHE", 5: "APP", 7: "FILE"}.get(self.view, "NAME")
        age = "LAST OPENED" if self.view == 5 else "LAST USED"
        sortable = self.view != 7
        for key, text, x, right in (("name", name, g["name"], False), ("size", "SIZE", g["size"], True),
                                    ("age", age, g["age"], False)):
            on = sortable and self.sort == key
            label = ("▾" if on else "") + text if right else text + (" ▾" if on else "")
            if right:
                x += 8 - dwidth(label)
            end = self.put(y, x, label, t.text if on else t.muted, bold=on)
            if sortable:
                self.hit(y, x, end, ("sort", key), lambda kind, mx, my, key=key: self.set_sort(key))
        if g["loc_w"]:
            loc = {5: "LEFTOVERS IN ~/LIBRARY"}.get(self.view, "LOCATION")
            self.put(y, g["loc"], clip(loc, g["loc_w"]), t.muted)

    def draw_item(self, y, w, ln, cur):
        t = self.t
        it = ln.item
        m = ln.meta
        show_loc, tag = self._view_layout()
        g = self.geometry(w, show_loc and not m.get("noloc"), tag)
        if cur:
            self.row_bg = t.cursor
            self.fill(y, 0, w - 1, t.cursor)
            self.put(y, 0, "▌", t.accent)
        if it["path"] in self.sel:
            self.put(y, 2, "●", t.accent)
        if tag:
            self.put(y, 4, KIND_TAG.get(it.get("kind", ""), ""), t.faint)
        # name
        x, nw = g["name"], g["name_w"]
        name = it.get("label") or it["name"]
        if m.get("tag") == "dev":
            name = "%s  (%s)" % (it.get("project"), it.get("label"))
        if it.get("dir") and it.get("kind") == "folder":
            name += "/"
        fg = t.muted if it.get("appdata") and not m.get("cache") and self.view != 6 else t.text
        if m.get("cache"):
            safe = it["safety"] == "safe"
            self.put(y, x, "✓" if safe else "!", t.good if safe else t.warn, bold=True)
            x, nw = x + 2, nw - 2
        end = self.put(y, x, clip(name, nw), fg, bold=cur)
        if m.get("app") and it.get("version"):
            ver = " " + clean(it["version"])
            if dwidth(ver) <= x + nw - end:
                self.put(y, end, ver, t.muted)
        # size + bar
        self.put(y, g["size"], pad(fmt_size(it["size"]), 8, True), t.text, bold=True)
        self.hbar(y, g["bar"], g["bar_w"], it["size"] / float(m.get("max") or 1), t.accent,
                  t.track_cur if cur else t.track)
        # age
        age_fg = t.muted
        if m.get("app"):
            used = it.get("used")
            when = fmt_ago(used) if used else "never opened"
            age_fg = t.warn if not used or time.time() - used > STALE else t.text
        else:
            when = fmt_ago(it.get("activity"))
        if m.get("dup_first"):
            when, age_fg = "newest · keep", t.good
        self.put(y, g["age"], clip(when, 13), age_fg)
        # location / leftovers
        if g["loc_w"]:
            if m.get("app"):
                left = it.get("leftover_size")
                if left:
                    big = left >= 100 * E.MB
                    self.put(y, g["loc"], clip("+" + fmt_size(left), g["loc_w"]), t.big if big else t.muted, bold=big)
                else:
                    self.put(y, g["loc"], "—", t.faint)
            else:
                extra = it.get("sub", "") if m.get("cache") else it.get("loc") or ""
                self.put(y, g["loc"], clip(extra, g["loc_w"]), t.muted)
        self.row_bg = None

    def draw_bar(self, y, w, ln):
        t = self.t
        fg = getattr(t, ln.fg) if ln.fg else t.text
        crumbs = ln.meta.get("crumbs")
        if crumbs and dwidth(ln.text) <= w - 3:           # Explorer: every folder in the path is clickable
            x = 1
            for n, (name, path) in enumerate(crumbs):
                if n:
                    x = self.put(y, x, " › ", t.faint)
                last = n == len(crumbs) - 1
                x0, x = x, self.put(y, x, name, fg if last else t.muted, bold=last)
                if not last:
                    self.hit(y, x0, x, ("crumb", path), lambda kind, mx, my, path=path: self.explore(path))
        else:
            x = self.put(y, 1, clip(ln.text, w - 3), fg, bold=True)
        sub = ln.meta.get("sub")
        if sub:
            x = self.put(y, x, clip(sub, w - 2 - x), t.muted)
        chips = list(ln.meta.get("chips") or [])
        while chips and x + 3 + chips_width(chips) > w - 1:
            chips.pop()
        if chips:
            self.chips(y, w - 1 - chips_width(chips), chips)

    def _draw_progress(self, y, w, frac):
        t = self.t
        bw = min(40, w - 12)
        self.hbar(y, 1, bw, frac, t.accent, t.track)
        self.put(y, bw + 3, "%d%%" % (100 * frac), t.text, bold=True)

    def _draw_scan_progress(self, y, w, cur):
        p = self.e.progress
        spin = SPINNER[int(time.time() * 8) % len(SPINNER)]
        self.put(y, 1, "%s %s files · %s" % (spin, format(p["files"], ","), fmt_size(p["bytes"])), self.t.accent)

    def header_status(self, st, room):
        t = self.t
        scan, disk = st["scan"], st["disk"]
        if scan.get("state") == "scanning":
            spin = SPINNER[int(time.time() * 8) % len(SPINNER)]
            frac = scan.get("fraction")
            pct = " %d%%" % (frac * 100) if frac else ""
            options = ["%s %sscanning%s · %s files" % (spin, "re" if st["has_data"] else "", pct,
                                                      format(scan.get("files", 0), ",")),
                       "%s scanning%s" % (spin, pct)]
            fg = t.accent
        elif scan.get("state") == "error":
            options, fg = ["✗ scan failed — r to retry", "✗ scan failed"], t.bad
        else:
            free = "%s free" % fmt_size(disk["free"])
            options = ["%s · scanned %s" % (free, fmt_ago(st["scanned_at"])), free] if st["scanned_at"] else [free]
            fg = t.muted
        for s in options:
            if dwidth(s) <= room:
                return s, fg
        return "", fg

    def _check_update(self):
        try:
            self.update = E.update_status(timeout=3)
        except Exception:  # noqa: BLE001  never let an update check take the dashboard down
            pass

    def ask_update(self):
        u = self.update or {}
        if not u.get("available"):
            return
        self.confirm("Update to MacSafe %s? The dashboard closes, installs it and reopens." % u["latest"],
                     lambda: setattr(self, "want_update", True), yes="update")

    def draw_header(self, w, st):
        t = self.t
        self.put(0, 1, "◆", t.accent, bold=True)
        x = self.put(0, 3, "MacSafe", t.text, bold=True)
        u = self.update or {}
        if u.get("available") and w >= 48:
            label = " ↑ Update to %s " % u["latest"]
            x0 = x + 2
            x = self.put(0, x0, label, t.on_accent, t.accent, bold=True)
            self.hit(0, x0, x, ("update",), lambda kind, mx, my: self.ask_update())
            x = self.put(0, x + 1, "U", t.faint)
        elif u.get("current"):
            x = self.put(0, x + 1, u["current"], t.faint)
        right, fg = self.header_status(st, w - x - 3)
        if right:
            self.put(0, w - 1 - dwidth(right), right, fg)
        n = len(VIEWS)
        styles = [[" %d %s " % (i + 1, v) for i, v in enumerate(VIEWS)],
                  [" %s " % v for v in VIEWS_SHORT],
                  [" %d %s " % (i + 1, v) if i == self.view else " %d " % (i + 1) for i, v in enumerate(VIEWS_SHORT)]]
        labels = next((s for s in styles if sum(map(len, s)) + n - 1 <= w - 2), styles[-1])
        x = 1
        for i, label in enumerate(labels):
            self.hit(1, x, x + len(label), ("tab", i), lambda kind, mx, my, i=i: self.switch(i))
            if i == self.view:
                self.put(1, x, label, t.on_accent, t.accent, bold=True)
            else:
                self.put(1, x, label, t.muted)
                if label.startswith(" %d" % (i + 1)):
                    self.put(1, x + 1, str(i + 1), t.faint)
            x += len(label) + 1
        self.put(2, 0, "─" * w, t.rule)

    def draw_footer(self, h, w):
        t = self.t
        self.put(h - 3, 0, "─" * w, t.frule)
        y = h - 2
        if self.prompt and self.prompt[3]:          # permanent: a red warning over two rows
            text, _, answers, _ = self.prompt
            self.fill(h - 3, 0, w, None)
            x = self.put(h - 3, 1, "⚠", t.bad, bold=True)
            warning = self.prompt_hint or ("Are you sure? This action is permanent: "
                                           "nothing goes to the Trash and it can't be undone.")
            self.put(h - 3, x + 1, clip(warning, w - x - 2), t.bad, bold=True)
            x = self.put(y, 3, clip(text, max(10, w - 10 - chips_width(answers))), t.text)
            self.chips(y, x + 3, answers, keyboard_only=("y",))
        elif self.prompt:
            text, _, answers, _ = self.prompt
            x = self.put(y, 1, "?", t.warn, bold=True)
            x = self.put(y, x + 1, clip(text, max(10, w - x - 6 - chips_width(answers))), t.warn, bold=True)
            self.chips(y, x + 3, answers)
        elif self.msg and time.time() < self.msg_until:
            icon, fg = {"good": ("✓", t.good), "bad": ("✗", t.bad), "warn": ("!", t.warn),
                        "muted": ("", t.muted)}.get(self.msg_kind, ("•", t.accent))
            x = 1
            if icon:
                x = self.put(y, 1, icon, fg, bold=True) + 1
            self.put(y, x, clip(self.msg, w - x - 1), fg)
        elif self.sel:
            chosen = [ln.item for ln in self.items() if ln.item["path"] in self.sel]
            x = self.put(y, 1, " %d selected " % len(chosen), t.on_accent, t.accent, bold=True)
            x = self.put(y, x + 1, fmt_size(sum(i["size"] for i in chosen)), t.text, bold=True)
            if self.view == 5:
                left = sum(i.get("leftover_size") or 0 for i in chosen)
                if left:
                    x = self.put(y, x, " + %s of leftovers" % fmt_size(left), t.muted)
            acts = [("t", "uninstall" if self.view == 5 else "trash"), ("x", "delete")]
            if self.view == 3:
                acts.append(("c", "clear"))
            acts.append(("esc", "clear selection"))
            while acts and x + 3 + chips_width(acts) > w - 1:
                acts.pop(0)
            self.chips(y, x + 3, acts)
        keys = [("↑↓", "move")] + ([("←→", "panels")] if self.wide_overview() else [])
        keys += {0: [("⏎", "open")], 6: [("⏎", "open"), ("←", "up")], 3: [("c", "clear")],
                 7: [("F", "find"), ("K", "keep newest")]}.get(self.view, [])
        keys += [("space", "select"), ("t", "uninstall" if self.view == 5 else "trash"), ("x", "delete"),
                 ("u", "undo"), ("o", "Finder"), ("1-8", "views"), ("r", "rescan")]
        must = [("?", "help"), ("q", "quit")]
        while keys and chips_width(keys + must) > w - 2:
            keys.pop()
        self.chips(h - 1, 1, keys + must)

    def draw(self):
        h, w = self.scr.getmaxyx()
        self.cv = Canvas(w, h)
        self.row_bg = None
        self.hits = []
        t = self.t
        if h < 12 or w < 70:
            self.put(0, 0, clip("Make the terminal a bit bigger (at least 70×12).", w), t.warn)
            return self.blit()
        st = self.e.status()
        self.draw_header(w, st)
        body_top, body_h = 3, h - 6
        if self.show_help:
            self.draw_help(body_top, body_h, w)
        else:
            n = len(self.lines)
            if self.follow:
                if self.cur < self.top:
                    self.top = self.cur
                if self.cur >= self.top + body_h:
                    self.top = self.cur - body_h + 1
            self.top = max(0, min(self.top, max(0, n - body_h)))
            for row in range(min(body_h, n - self.top)):
                i = self.top + row
                ln, y, cur = self.lines[i], body_top + row, i == self.cur
                if ln.kind == "item":
                    for ci, (cx, cw, it) in enumerate(ln.cols or [(0, w - 1, ln.item)]):
                        if it is not None:
                            self.hit(y, cx, cx + cw, ("row", i, ci),
                                     lambda kind, mx, my, i=i, ci=ci: self.click_row(i, ci, kind))
                    if not ln.cols:           # the ● column ticks the row for cleanup
                        self.hit(y, 1, 4, ("mark", i), lambda kind, mx, my, i=i: (self.select(i), self.toggle_mark()))
                if ln.draw:
                    ln.draw(y, w, cur)
                elif ln.kind == "item":
                    self.draw_item(y, w, ln, cur)
                elif ln.kind == "head":
                    x = self.put(y, 1, clip(ln.text, w - 3), t.accent, bold=True)
                    if ln.meta.get("sub"):
                        self.put(y, x + 2, clip(ln.meta["sub"], w - x - 4), t.muted)
                elif ln.kind == "bar":
                    self.draw_bar(y, w, ln)
                elif ln.kind == "colhead":
                    self.draw_colhead(y, w)
                elif ln.kind == "text":
                    self.put(y, 1, clip(ln.text, w - 3), getattr(t, ln.fg) if ln.fg else t.text, bold=ln.bold)
                self.row_bg = None
            self.draw_scrollbar(body_top, body_h, w, n, self.top, "top")
        self.draw_footer(h, w)
        self.blit()

    def draw_scrollbar(self, y0, hgt, w, n, top, attr):
        if n <= hgt:
            return
        t = self.t
        size = max(1, hgt * hgt // n)
        pos = int(round((hgt - size) * top / float(max(1, n - hgt))))
        for i in range(hgt):
            on = pos <= i < pos + size
            self.put(y0 + i, w - 1, "┃" if on else "│", t.muted if on else t.rule)
            self.hit(y0 + i, w - 1, w, ("scroll", attr), lambda kind, mx, my, i=i: self.scroll_to(
                attr, int(round((n - hgt) * i / float(max(1, hgt - 1))))))

    def scroll_to(self, attr, top):
        setattr(self, attr, top)
        if attr == "top":
            self.follow = False

    HELP = [
        ("Moving around", [("↑ ↓  j k", "move"), ("← →  h l", "switch panel (Overview)"),
                           ("PgUp PgDn", "page"), ("g  G", "top / bottom"), ("1–8  Tab", "switch view"),
                           ("⏎  →", "open · explore · show in Finder"), ("←  ⌫", "up a folder (Explorer)")]),
        ("Cleaning up", [("space", "select / unselect"), ("A", "select all"), ("esc", "clear selection"),
                         ("t", "move to Trash — u puts it back"), ("x", "delete permanently (asks first)"),
                         ("c  C", "clear selected / every safe cache"), ("E", "empty the Trash"),
                         ("o", "show in Finder")]),
        ("Filters", [("f", "minimum size"), ("p", "period / age"), ("a", "include app data"),
                     ("s", "sort: size · age · name")]),
        ("Other", [("r", "rescan"), ("F", "find duplicates"), ("K", "select extra copies"),
                   ("U", "install an update (when the header offers one)"), ("ctrl-L", "redraw the screen"),
                   ("q", "quit")]),
        ("Mouse", [("click", "select a row or a donut slice"), ("double-click", "open (same as ⏎)"),
                   ("right-click", "select for cleanup"), ("tabs, keys", "click to use them"),
                   ("headers", "click to sort by that column"), ("wheel", "scroll")]),
    ]
    HELP_NOTE = ("Everything goes through the same safety checks as the Mac app: system folders, your standard "
                 "folders and anything inside app bundles or Photos libraries can't be removed. Permanent actions "
                 "(delete, clear, empty the Trash) show a red warning and can only be confirmed with the y key.")

    def _help_block(self, sections):
        rows = []
        for title, keys in sections:
            if rows:
                rows.append(None)
            rows.append(("title", title))
            rows += [("key", k) for k in keys]
        return rows

    def draw_help(self, y0, hgt, w):
        t = self.t

        def paint(rows, x, colw, top):
            for i, r in enumerate(rows[top:top + hgt]):
                y = y0 + i
                if r is None:
                    continue
                if r[0] == "title":
                    self.put(y, x, r[1], t.accent, bold=True)
                elif r[0] == "key":
                    k, desc = r[1]
                    self.put(y, x + 2, pad(k, 13), t.text, bold=True)
                    self.put(y, x + 16, clip(desc, colw - 16), t.muted)
                else:
                    self.put(y, x, clip(r[1], colw), t.muted)

        note = wrap(self.HELP_NOTE + ("" if self.mouse else " Mouse support is off (--no-mouse)."),
                    (w - 6) // 2 if w >= 100 else w - 4)
        note_rows = [None] + [("note", s) for s in note]
        if w >= 100:
            left = self._help_block(self.HELP[:1] + self.HELP[2:4])
            right = self._help_block(self.HELP[1:2] + self.HELP[4:])
            colw = (w - 6) // 2
            self.help_top = max(0, min(self.help_top, max(len(left), len(right)) + len(note_rows) - hgt))
            paint(left + note_rows if len(left) >= len(right) else left, 2, colw, self.help_top)
            paint(right if len(left) >= len(right) else right + note_rows, 4 + colw, colw, self.help_top)
            total = max(len(left), len(right)) + len(note_rows)
        else:
            rows = self._help_block(self.HELP) + note_rows
            self.help_top = max(0, min(self.help_top, len(rows) - hgt))
            paint(rows, 2, w - 4, self.help_top)
            total = len(rows)
        self.draw_scrollbar(y0, hgt, w, total, self.help_top, "help_top")

    # ── actions ──
    def confirm(self, text, on_yes, permanent=False, yes="yes"):
        """Ask before acting. Permanent actions get a red warning and can only be confirmed with the y key."""
        self.prompt_hint = ""
        self.prompt = (text, {ord("y"): on_yes, ord("Y"): on_yes}, [("y", yes), ("n", "cancel" if permanent else "no")],
                       permanent)

    def _busy(self, text):
        self.say(text, "info", 60)
        self.draw()

    def _report(self, res, verb):
        ok = [r for r in res.get("results", []) if r.get("ok")]
        bad = [r for r in res.get("results", []) if not r.get("ok")]
        if res.get("error"):
            return self.say(res["error"], "bad")
        moved = sum(r.get("freed", 0) for r in ok)
        if res.get("mode") == "trash":
            self.last_trash = [{"from": r["to"], "to": r["path"]} for r in ok if r.get("to")]
            text = "Moved %d item%s (%s) to the Trash%s" % (len(ok), "" if len(ok) == 1 else "s", fmt_size(moved),
                                                         " — u to undo, E to empty the Trash" if self.last_trash else "")
        else:
            text = "%s %d item%s — freed %s" % (verb, len(ok), "" if len(ok) == 1 else "s", fmt_size(res.get("freed", 0)))
        if bad:
            text += "   ✗ %d failed: %s" % (len(bad), bad[0].get("error", ""))
        self.say(text, "bad" if bad and not ok else ("warn" if bad else "good"), 10)
        self.sel.clear()
        self.rebuild()

    def do_trash(self):
        items = [i for i in self.targets() if i.get("action") != "none"]
        if not items:
            return
        self._busy("Moving to Trash…")
        self._report(self.e.delete([i["path"] for i in items], "trash"), "Trashed")

    def do_uninstall(self):
        apps = self.targets()
        if not apps:
            return
        left = [x for a in apps for x in a.get("leftovers", [])]
        size = sum(a["size"] for a in apps)
        names = ", ".join(a["name"] for a in apps[:3]) + ("…" if len(apps) > 3 else "")

        def run(with_left):
            self.prompt = None
            self._busy("Uninstalling…")
            paths = [a["path"] for a in apps] + ([x["path"] for x in left] if with_left else [])
            self._report(self.e.delete(paths, "trash"), "Uninstalled")
        if left:
            lsize = sum(x["size"] for x in left)
            self.prompt = ("Uninstall %s (%s)? Also trash %d leftover folder%s in ~/Library (%s)?" % (
                names, fmt_size(size), len(left), "" if len(left) == 1 else "s", fmt_size(lsize)),
                {ord("y"): lambda: run(True), ord("a"): lambda: run(False)},
                [("y", "with leftovers"), ("a", "app only"), ("n", "cancel")], False)
        else:
            self.confirm("Move %s (%s) to the Trash?" % (names, fmt_size(size)), lambda: run(False))

    def do_delete(self):
        items = [i for i in self.targets() if i.get("action") != "none"]
        if not items:
            return
        size = sum(i["size"] for i in items)
        what = items[0]["name"] if len(items) == 1 else "%d items" % len(items)

        def run():
            self.prompt = None
            self._busy("Deleting…")
            self._report(self.e.delete([i["path"] for i in items], "delete"), "Deleted")
        self.confirm("Delete %s (%s)?" % (what, fmt_size(size)), run,
                     permanent=True, yes="delete permanently")

    def do_clear(self, everything=False):
        if self.view != 3:
            return
        if everything:
            items = [ln.item for ln in self.items() if ln.item["safety"] == "safe" and ln.item["action"] == "clear"
                     and ln.item["path"] != E.TRASH]
        else:
            items = [i for i in self.targets() if i.get("action") == "clear"]
        if not items:
            return self.say("Nothing clearable selected. 'Review' items are moved to the Trash with t.", "warn")
        size = sum(i["size"] for i in items)

        def run():
            self.prompt = None
            self._busy("Clearing caches…")
            self._report(self.e.delete([i["path"] for i in items], "clear"), "Cleared")
        self.confirm("Clear %d cache%s (%s)? Apps rebuild what they need." % (
            len(items), "" if len(items) == 1 else "s", fmt_size(size)), run, permanent=True, yes="clear")

    def do_empty_trash(self):
        size = (self.e.idx.entries.get(E.TRASH) or {}).get("size", 0) if self.e.idx else 0
        if not size:
            return self.say("The Trash is already empty.", "muted", 3)

        def run():
            self.prompt = None
            self._busy("Emptying the Trash…")
            self.last_trash = []
            self._report(self.e.delete([E.TRASH], "clear"), "Emptied the Trash:")
        self.confirm("Empty the Trash (%s)?" % fmt_size(size), run,
                     permanent=True, yes="empty the Trash")

    def do_undo(self):
        if not self.last_trash:
            return self.say("Nothing to undo.", "muted")
        res = self.e.restore(self.last_trash)
        ok = sum(1 for r in res["results"] if r["ok"])
        self.last_trash = []
        self.say("Put back %d item%s." % (ok, "" if ok == 1 else "s"), "good")
        self.rebuild()

    def do_open(self):
        it = self.current()
        if not it:
            return
        if it.get("cat"):
            return self.open_category(it)
        if it.get("goto") is not None:
            return self.switch(it["goto"])
        if it.get("trash"):
            return self.do_empty_trash() if it["size"] else self.say("The Trash is already empty.", "muted")
        if it.get("virtual"):
            return E.reveal(it["reveal"]) if it.get("reveal") else None
        if self.view in (0, 6) and it.get("drill"):
            self.explore_path = it["path"]
            self.switch(6)
        else:
            E.reveal(it["path"])

    def explore(self, path):
        child = self.explore_path
        self.explore_path = path
        self.rebuild(keep_cursor=False)
        while child and child != path:          # land on the folder we came out of
            found = self.locate(child)
            if found:
                self.select(*found)
                break
            child = os.path.dirname(child) if child != os.path.dirname(child) else None

    def open_category(self, it):
        cat = it["cat"]
        if cat == "apps":
            self.switch(5)
        elif cat in ("appdata", "files"):
            self.explore_path = E.LIBRARY if cat == "appdata" else E.HOME
            self.switch(6)
        elif cat == "system":
            found = next(((i, ci) for i, ln in enumerate(self.lines) if ln.cols
                          for ci, c in enumerate(ln.cols) if c[2] and c[2].get("outside")), None)
            if found:
                self.select(*found)
            self.say("macOS itself, other accounts, Homebrew and system caches. It's measured, not cleaned here.",
                     "muted", 8)
        else:
            self.say("%s free of %s." % (fmt_size(it["size"]), fmt_size(self.e.disk()["total"])), "muted")

    def reveal(self):
        it = self.current()
        path = it and (it.get("reveal") if it.get("virtual") else it["path"])
        if path:
            E.reveal(path)
        elif it:
            self.say("Nothing to show in Finder for %s." % it["name"], "muted", 3)

    def switch(self, v):
        self.view = v % len(VIEWS)
        self.sel.clear()
        self.show_help = False
        self.cur = self.top = self.col = 0
        self.rebuild(keep_cursor=False)

    def _selectable(self, i, ci=None):
        ln = self.lines[i]
        if ln.kind != "item":
            return False
        return ci is None or not ln.cols or (ci < len(ln.cols) and ln.cols[ci][2] is not None)

    def _fix_col(self):
        """Keep the cursor in a panel that has something selectable on the cursor row (the nearest one)."""
        if not (0 <= self.cur < len(self.lines)):
            return
        cols = self.lines[self.cur].cols
        if not cols:
            return
        if not self._selectable(self.cur, self.col):
            ok = [ci for ci in range(len(cols)) if cols[ci][2] is not None]
            if ok:
                self.col = min(ok, key=lambda ci: abs(ci - self.col))

    def _snap_cursor(self, step):
        n = len(self.lines)
        if not n:
            self.cur = 0
            return
        i = max(0, min(self.cur, n - 1))
        while 0 <= i < n and self.lines[i].kind != "item":
            i += step
        if not (0 <= i < n):
            i = max(0, min(self.cur, n - 1))
            while 0 <= i < n and self.lines[i].kind != "item":
                i -= step
        self.cur = i if 0 <= i < n else 0
        self._fix_col()

    def move(self, delta):
        n = len(self.lines)
        if not n:
            return
        step = 1 if delta > 0 else -1
        i = self.cur
        for _ in range(abs(delta)):
            j = i + step
            while 0 <= j < n and not self._selectable(j, self.col):     # stay in the same panel…
                j += step
            if not (0 <= j < n):
                j = i + step
                while 0 <= j < n and not self._selectable(j):           # …unless it has nothing further
                    j += step
            if not (0 <= j < n):
                break
            i = j
        if i == self.cur:             # nothing selectable further: scroll the rest into view instead
            self.top = max(0, self.top + delta)
            self.follow = False
        else:
            self.cur = i
            self.follow = True
            self._fix_col()

    def move_col(self, delta):
        """← → between side-by-side panels: jump to the nearest selectable row of the neighbouring panel."""
        cols = self.lines[self.cur].cols if 0 <= self.cur < len(self.lines) else None
        if not cols or len(cols) < 2:
            return False
        target = self.col + delta
        if not 0 <= target < len(cols):
            return True
        n = len(self.lines)
        for dist in range(n):
            for j in (self.cur - dist, self.cur + dist):
                if 0 <= j < n and self._selectable(j, target) and self.lines[j].cols \
                        and len(self.lines[j].cols) > target:
                    self.select(j, target)
                    return True
        return True

    def wide_overview(self):
        return self.view == 0 and any(ln.cols and len(ln.cols) > 1 for ln in self.lines)

    def toggle_mark(self):
        it = self.current()
        if not it:
            return
        if it.get("virtual"):
            return self.say("Press ⏎ to open %s — only files and folders can be selected." % it["name"], "muted", 3)
        self.sel.symmetric_difference_update({it["path"]})

    def on_mouse(self):
        try:
            _, mx, my, _, b = curses.getmouse()
        except curses.error:
            return True
        if b & WHEEL_UP or (WHEEL_DOWN and b & WHEEL_DOWN):
            step = -3 if b & WHEEL_UP else 3
            if self.show_help:
                self.help_top = max(0, self.help_top + step)
            elif not self.prompt:
                self.top = max(0, self.top + step)
                self.follow = False
            return True
        if b & (curses.BUTTON1_PRESSED | curses.BUTTON1_CLICKED):
            kind = "click"
        elif b & curses.BUTTON1_DOUBLE_CLICKED:
            kind = "double"
        elif b & (curses.BUTTON3_PRESSED | curses.BUTTON3_CLICKED):
            kind = "right"
        else:
            return True
        target = next((h for h in reversed(self.hits) if h[0] == my and h[1] <= mx < h[2]), None)
        key = (self.view, target[3]) if target else None
        now = time.time()
        if kind == "click" and key and self.last_click and self.last_click[1] == key \
                and now - self.last_click[0] < DOUBLE_CLICK:
            kind, self.last_click = "double", None
        elif kind == "click":
            self.last_click = (now, key)
        if self.prompt:               # while asking, only the answer chips respond; any other click cancels
            if target and target[3][0] == "chip":
                return target[4](kind, mx, my) is not False
            return self.handle(ord("n"))
        if target is None:
            if self.show_help and kind != "right":
                self.show_help = False
            return True
        res = target[4](kind, mx, my)
        if key and key[0] != self.view:
            self.last_click = None    # the view changed: a second click is a new click, not a double
        return res is not False

    def click_row(self, i, ci, kind):
        self.select(i, ci)
        if kind == "double":
            self.do_open()
        elif kind == "right":
            self.toggle_mark()

    def set_sort(self, key):
        self.sort = key
        self.say("Sorted by %s" % key, "muted", 2)
        self.top = 0
        self.rebuild(keep_cursor=False)

    def cycle(self, value, options):
        return options[(options.index(value) + 1) % len(options)] if value in options else options[0]

    def handle(self, k):
        if k == curses.KEY_MOUSE:
            return self.on_mouse()
        if self.prompt:
            actions = self.prompt[1]
            self.prompt = None
            if k in actions:
                actions[k]()
            else:
                self.say("Cancelled.", "muted", 2)
            return True
        if k in (ord("q"), ord("Q")):
            return False
        h, _ = self.scr.getmaxyx()
        page = max(1, h - 8)
        if k == curses.KEY_RESIZE:
            self.scr.clear()
            self.rebuild()
            return True
        if k == 12:                   # ctrl-L
            self.scr.clear()
            return True
        if self.show_help:
            if k in (curses.KEY_DOWN, ord("j")):
                self.help_top += 1
            elif k in (curses.KEY_UP, ord("k")):
                self.help_top = max(0, self.help_top - 1)
            elif k == curses.KEY_NPAGE:
                self.help_top += page
            elif k == curses.KEY_PPAGE:
                self.help_top = max(0, self.help_top - page)
            else:
                self.show_help = False
            return True
        if k in (curses.KEY_DOWN, ord("j")):
            self.move(1)
        elif k in (curses.KEY_UP, ord("k")):
            self.move(-1)
        elif k == curses.KEY_NPAGE:
            self.move(page)
        elif k == curses.KEY_PPAGE:
            self.move(-page)
        elif k in (ord("g"), curses.KEY_HOME):
            self.cur = 0
            self.top = 0
            self._snap_cursor(1)
            self.follow = True
        elif k in (ord("G"), curses.KEY_END):
            self.cur = len(self.lines) - 1
            self._snap_cursor(-1)
            self.top = len(self.lines)
            self.follow = False
        elif ord("1") <= k <= ord("8"):
            self.switch(k - ord("1"))
        elif k == 9:
            self.switch(self.view + 1)
        elif k == curses.KEY_BTAB:
            self.switch(self.view - 1)
        elif k == ord("?"):
            self.show_help = True
            self.help_top = 0
        elif k == ord(" "):
            self.toggle_mark()
            if self.current() and not self.current().get("virtual"):
                self.move(1)
        elif k == ord("A"):
            paths = {it["path"] for it in self.all_items() if not it.get("virtual")}
            self.sel = set() if paths <= self.sel else paths
        elif k == 27:
            self.sel.clear()
        elif k in (curses.KEY_LEFT, curses.KEY_RIGHT, ord("h"), ord("l")) and self.wide_overview():
            self.move_col(1 if k in (curses.KEY_RIGHT, ord("l")) else -1)
        elif k in (10, 13, curses.KEY_ENTER, curses.KEY_RIGHT, ord("l")):
            self.do_open()
        elif k in (curses.KEY_LEFT, curses.KEY_BACKSPACE, 127, 8, ord("h")) and self.view == 6:
            if self.explore_path != E.HOME:
                self.explore(os.path.dirname(self.explore_path))
        elif k == ord("t"):
            self.do_uninstall() if self.view == 5 else self.do_trash()
        elif k in (ord("x"), curses.KEY_DC):
            self.do_delete()
        elif k == ord("c"):
            self.do_clear()
        elif k == ord("C"):
            self.do_clear(everything=True)
        elif k == ord("E"):
            self.do_empty_trash()
        elif k == ord("u"):
            self.do_undo()
        elif k == ord("U"):
            self.ask_update()
        elif k == ord("o"):
            self.reveal()
        elif k == ord("r"):
            if self.e.start_scan():
                self.say("Rescanning in the background — you can keep working.", "info")
        elif k == ord("f"):
            if self.view == 1:
                self.large_min = self.cycle(self.large_min, SIZE_STEPS[1:])
            elif self.view == 2:
                self.unused_min = self.cycle(self.unused_min, SIZE_STEPS)
            self.rebuild()
        elif k == ord("p"):
            if self.view == 2:
                self.unused_days = self.cycle(self.unused_days, PERIODS)
            elif self.view == 4:
                self.dl_days = self.cycle(self.dl_days, [0, 30, 90, 365])
            elif self.view == 5:
                self.apps_days = self.cycle(self.apps_days, [0, 90, 180, 365])
            self.rebuild()
        elif k == ord("a"):
            if self.view == 1:
                self.large_appdata = not self.large_appdata
            elif self.view == 2:
                self.unused_appdata = not self.unused_appdata
            self.rebuild()
        elif k == ord("s"):
            self.set_sort(self.cycle(self.sort, ["size", "age", "name"]))
        elif k == ord("F") and self.view == 7:
            if self.e.idx is not None:
                self.e.start_dups()
                self.rebuild()
        elif k == ord("K") and self.view == 7:
            self.sel = {ln.item["path"] for ln in self.items() if not ln.meta.get("dup_first")}
        return True

    def loop(self):
        curses.curs_set(0)
        self.scr.timeout(250)
        self.scr.keypad(True)
        curses.set_escdelay(25) if hasattr(curses, "set_escdelay") else None
        if self.mouse:
            curses.mousemask(curses.ALL_MOUSE_EVENTS)
            curses.mouseinterval(0)   # report presses at once; double clicks are spotted in on_mouse
        self.rebuild(keep_cursor=False)
        dup_running = False
        while True:
            scanning = self.e.scanning
            if self.was_scanning and not scanning:
                state = self.e.scan.get("state")
                self.say("Scan finished — everything is up to date." if state == "done" else "Scan failed.",
                         "good" if state == "done" else "bad")
                self.rebuild()
            self.was_scanning = scanning
            running = self.e.dups.get("state") == "running"
            if self.view == 7 and (running or dup_running):
                self.rebuild()
            dup_running = running
            self.draw()
            k = self.scr.getch()
            if k == -1:
                continue
            if not self.handle(k) or self.want_update:
                break


# ───────────────────────────── terminal setup ──────────────────────────────

def ensure_utf8():
    """Without a UTF-8 locale curses miscounts the width of ▀ █ ● and the screen falls apart."""
    locale.setlocale(locale.LC_ALL, "")
    if "utf" in (locale.getpreferredencoding(False) or "").lower():
        return
    for name in ("en_US.UTF-8", "C.UTF-8", "UTF-8"):
        try:
            locale.setlocale(locale.LC_CTYPE, name)
            return
        except locale.Error:
            pass


def light_background():
    """Ask the terminal for its background colour (OSC 11); a DA1 query after it guarantees an answer."""
    env = os.environ.get("MACSAFE_THEME", "").lower()
    if env in ("light", "dark"):
        return env == "light"
    fgbg = os.environ.get("COLORFGBG", "")
    if fgbg:
        try:
            return int(fgbg.split(";")[-1]) in (7, 15)
        except ValueError:
            pass
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        return False
    import termios
    import tty
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    buf = b""
    try:
        tty.setraw(fd)
        os.write(sys.stdout.fileno(), b"\033]11;?\033\\\033[c")
        end = time.time() + 0.5
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], max(0, end - time.time()))
            if not r:
                break
            buf += os.read(fd, 256)
            if re.search(rb"\033\[\?[0-9;]*c", buf):
                break
    except OSError:
        pass
    finally:
        termios.tcsetattr(fd, termios.TCSAFLUSH, old)
    m = re.search(rb"rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+)", buf)
    if not m:
        return False
    r, g, b = (int(v, 16) / float(16 ** len(v) - 1) for v in m.groups())
    return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.5


# ───────────────────────────── one-shot report ──────────────────────────────

def report(engine):
    if engine.idx is None or engine.age > RESCAN_AFTER:
        engine.start_scan()
        while engine.scanning:
            p = engine.progress
            sys.stderr.write("\rScanning… %s files, %s   " % (format(p["files"], ","), fmt_size(p["bytes"])))
            sys.stderr.flush()
            time.sleep(0.3)
        sys.stderr.write("\r" + " " * 60 + "\r")
    if engine.idx is None:
        sys.exit("Scan failed: %s" % engine.scan.get("error", "unknown error"))
    with engine.lock:
        o = engine.overview()
    d = o["disk"]
    print("Macintosh HD — %s free of %s (%s used)" % (fmt_size(d["free"]), fmt_size(d["total"]), fmt_size(d["used"])))
    print("  " + bar(d["used"] / float(d["total"]), 40))
    for seg in o["breakdown"]:
        print("  %-20s %10s" % (seg["label"], fmt_size(seg["size"])))
    w = o["wins"]
    print("\nQuick wins")
    for label, key in (("Trash", "trash"), ("Safe-to-clear caches", "caches"), ("Old downloads (3+ months)", "downloads"),
                       ("Installers & disk images", "installers"), ("node_modules & virtualenvs", "dev"),
                       ("iPhone/iPad backups", "backups")):
        if w[key]:
            print("  %-28s %10s" % (label, fmt_size(w[key])))
    print("\nLargest files")
    for it in o["large"]:
        print("  %10s  %s/%s" % (fmt_size(it["size"]), it["loc"], it["name"]))
    print("\nRun `macsafe` to clean up interactively (scanned %s)." % fmt_ago(engine.idx.scanned_at))


# ───────────────────────────── updates ──────────────────────────────

def update(force):
    """Install a newer MacSafe if there is one: "updated", "current" or "failed".
    The check is the same one the Mac app's Update button uses (engine.update_status)."""
    st = E.update_status(force=force, timeout=6 if force else 3)
    if not st["current"]:
        if force:
            print("Updates only work for an installed MacSafe; this copy runs from source.")
        return "current"
    if not st["available"]:
        if force:
            print(st["error"] or "MacSafe %s is the latest version." % st["current"])
        return "failed" if st["error"] else "current"
    print("MacSafe %s is available (you have %s). Installing it now…" % (st["latest"], st["current"]))
    if E.install_update(wait=True) != 0:
        print("\nThe update didn't install, so this is still MacSafe %s. Try again with `macsafe --update`."
              % st["current"])
        if not force:
            input("Press Return to open the dashboard. ")
        return "failed"
    return "updated"


def main():
    ap = argparse.ArgumentParser(description="MacSafe — terminal dashboard")
    ap.add_argument("--report", action="store_true", help="print a summary and exit")
    ap.add_argument("--app", action="store_true", help="open the Mac app")
    ap.add_argument("--rescan", action="store_true", help="always start a fresh scan")
    theme = ap.add_mutually_exclusive_group()
    theme.add_argument("--light", action="store_true", help="colours for a light terminal background")
    theme.add_argument("--dark", action="store_true", help="colours for a dark terminal background")
    ap.add_argument("--no-mouse", action="store_true", help="leave the mouse to the terminal (for selecting text)")
    ap.add_argument("--update", action="store_true", help="install the latest version now, then exit")
    ap.add_argument("--no-update", action="store_true", help="don't check for a newer version this time")
    args = ap.parse_args()
    if args.app:
        sys.exit(subprocess.call(["open", "-a", "MacSafe"]))
    if args.update:
        sys.exit(1 if update(force=True) == "failed" else 0)
    auto = not (args.report or args.no_update or os.environ.get("MACSAFE_NO_UPDATE")) and sys.stdout.isatty()
    if auto and update(force=False) == "updated":
        # install.sh replaced this script: start over on the new version, without checking again.
        os.execv(sys.executable, [sys.executable, os.path.realpath(__file__)] + sys.argv[1:] + ["--no-update"])
    ensure_utf8()
    sys.setrecursionlimit(20000)
    engine = E.Engine()
    if args.report:
        return report(engine)
    light = args.light or (not args.dark and light_background())
    if args.rescan or engine.idx is None or engine.age > RESCAN_AFTER:
        engine.start_scan()
    os.environ.setdefault("ESCDELAY", "25")
    dash = []
    curses.wrapper(lambda scr: (dash.append(Dashboard(scr, engine, light, not args.no_mouse)), dash[0].loop()))
    if dash and dash[0].want_update and update(force=True) == "updated":
        os.execv(sys.executable, [sys.executable, os.path.realpath(__file__)] + sys.argv[1:] + ["--no-update"])


if __name__ == "__main__":
    main()
