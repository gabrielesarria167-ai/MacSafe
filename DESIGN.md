---
name: MacSafe
description: A free Mac disk-space app and terminal dashboard, drawn as one scientific cross-section of the disk; journal-figure calm on deep navy, carried in the app's own vibrant category colours.
colors:
  apps-blue: "#4da3ff"
  apps-blue-deep: "#2f6fe8"
  files-orange: "#ff7a45"
  files-orange-deep: "#e8502a"
  appdata-green: "#2fd49a"
  appdata-green-deep: "#14a877"
  system-yellow: "#ffc233"
  system-yellow-deep: "#f09a12"
  track: "rgba(255,255,255,.09)"
  glossy-top: "#5b97ff"
  glossy-deep: "#2f5fe0"
  glossy-shadow: "#3264f0"
  glow-blue: "#3566e8"
  tile-purple: "#9b7bff"
  tile-purple-deep: "#6a4ae0"
  tile-pink: "#ff5c8a"
  tile-pink-deep: "#e0346a"
  tile-teal: "#3ccfe0"
  tile-teal-deep: "#1596b8"
  tile-gray: "#9a9aa1"
  tile-gray-deep: "#66666d"
  ground: "#0c1220"
  ground-2: "#111a2b"
  ground-3: "#162238"
  desk-ground: "#0a0f1b"
  terminal-ground: "#090e19"
  hair: "#1d2940"
  hair-2: "#2a3a58"
  steel: "#5b77a3"
  figure-hair: "rgba(160,176,205,.28)"
  leader: "rgba(190,200,218,.7)"
  ink: "#eef1f6"
  ink-2: "#b4bfd1"
  ink-3: "#97a3b8"
  focus: "#8cc2ff"
  app-accent: "#3987e5"
  app-accent-light: "#2a78d6"
  app-freeable: "#2fd49a"
  app-freeable-light: "#0f8a61"
  app-good: "#0ca30c"
  app-warning: "#fab219"
  app-critical: "#d03b3b"
  app-glass: "rgba(255,255,255,.045)"
  app-glass-light: "rgba(255,255,255,.62)"
  app-glass-edge: "rgba(255,255,255,.09)"
typography:
  display:
    fontFamily: "Hanken Grotesk, ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif"
    fontSize: "clamp(2.5rem, 4.1vw, 3.6rem)"
    fontWeight: 600
    lineHeight: 1.04
    letterSpacing: "-0.03em"
  headline:
    fontFamily: "Hanken Grotesk, ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif"
    fontSize: "clamp(1.85rem, 3vw, 2.5rem)"
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: "-0.025em"
  title:
    fontFamily: "Hanken Grotesk, ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif"
    fontSize: "19px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "-0.01em"
  lede:
    fontFamily: "Hanken Grotesk, ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif"
    fontSize: "19px"
    fontWeight: 400
    lineHeight: 1.5
  body:
    fontFamily: "Hanken Grotesk, ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.55
  caption:
    fontFamily: "Hanken Grotesk, ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.55
    fontFeature: "\"tnum\" 1"
  label:
    fontFamily: "Hanken Grotesk, ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
  button:
    fontFamily: "Hanken Grotesk, ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.2
  figure-name:
    fontFamily: "Hanken Grotesk, ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.2
    fontFeature: "\"tnum\" 1"
  figure-value:
    fontFamily: "Hanken Grotesk, ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif"
    fontSize: "18.5px"
    fontWeight: 400
    lineHeight: 1.2
    fontFeature: "\"tnum\" 1"
  code:
    fontFamily: "ui-monospace, SF Mono, SFMono-Regular, Menlo, Consolas, monospace"
    fontSize: "13.5px"
    fontWeight: 400
    lineHeight: 1.5
  app-headline:
    fontFamily: "-apple-system, SF Pro"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.15
  app-figure-total:
    fontFamily: "-apple-system, SF Pro"
    fontSize: "26px"
    fontWeight: 600
    lineHeight: 1.1
    fontFeature: "\"tnum\" 1"
  app-card-title:
    fontFamily: "-apple-system, SF Pro"
    fontSize: "13px"
    fontWeight: 700
    lineHeight: 1.3
  app-body:
    fontFamily: "-apple-system, SF Pro"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.35
  app-caption:
    fontFamily: "-apple-system, SF Pro"
    fontSize: "10px"
    fontWeight: 400
    lineHeight: 1.3
rounded:
  xs: "3px"
  sm: "4px"
  tile: "8px"
  term: "10px"
  md: "12px"
  lg: "16px"
  frame: "18px"
  full: "999px"
spacing:
  container: "1360px"
  gutter: "40px"
  gutter-mobile: "18px"
  section: "110px"
  section-mobile: "80px"
  sec-head: "640px"
  hero-lead: "minmax(320px, 420px)"
  ring-gap: "4px"
  app-card: "18px"
  app-stack: "22px"
  app-gap: "16px"
components:
  button-glossy:
    backgroundColor: "{colors.glossy-top}"
    textColor: "#ffffff"
    typography: "{typography.button}"
    rounded: "{rounded.full}"
    padding: "12px 24px"
  button-glossy-app:
    backgroundColor: "{colors.glossy-top}"
    textColor: "#ffffff"
    typography: "{typography.app-body}"
    rounded: "{rounded.full}"
    padding: "9px 20px"
  button-copy:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    padding: "0 16px"
  button-copy-hover:
    backgroundColor: "{colors.ground-3}"
    textColor: "{colors.ink}"
  command-bar:
    backgroundColor: "{colors.ground-2}"
    textColor: "{colors.ink}"
    typography: "{typography.code}"
    rounded: "{rounded.md}"
    padding: "13px 14px"
  figure-caption:
    textColor: "{colors.ink-2}"
    typography: "{typography.caption}"
  figure-key-row:
    textColor: "{colors.ink}"
    typography: "{typography.caption}"
    padding: "11px 2px"
  figure-key-row-selected:
    backgroundColor: "{colors.ground-2}"
    textColor: "{colors.ink}"
  nav-link:
    textColor: "{colors.ink-2}"
    typography: "{typography.label}"
  nav-link-hover:
    textColor: "{colors.ink}"
  terminal-window:
    backgroundColor: "{colors.terminal-ground}"
    textColor: "{colors.ink-2}"
    typography: "{typography.code}"
    rounded: "{rounded.term}"
  app-desktop:
    backgroundColor: "{colors.desk-ground}"
    rounded: "{rounded.frame}"
  glass-card:
    backgroundColor: "{colors.app-glass}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "{spacing.app-card}"
  color-tile:
    backgroundColor: "{colors.apps-blue}"
    textColor: "#ffffff"
    rounded: "{rounded.tile}"
    size: "30px"
  state-bar:
    backgroundColor: "{colors.track}"
    rounded: "{rounded.xs}"
    height: "6px"
---

# Design System: MacSafe

## Overview

**Creative North Star: "The Journal Figure"**

MacSafe draws the disk as one cross-section seen end-on, the way a scientific journal prints a figure: the categories form the inner ring, the biggest folders form the outer ring, and the largest files are radial bars. Selecting any part focuses it. The site sets this figure on flat deep navy, labels it with thin leader lines and sentence-case two-tier labels, and numbers every figure on the page as a real sequence (Fig. 1 to Fig. 4). The Mac app draws the same figure natively at the top of Overview. That shared figure is what makes the site and the app one system.

Colour comes only from the app's own vibrant category pairs: Applications blue, Your files orange, App data & caches green, macOS & other yellow. Each pair runs from a bright top to a deep partner along the arc. Free space is a neutral white track and never takes a hue. Around the figure the chrome stays quiet: hairlines, ink in three steps, tabular figures, and no ornament. The calm comes from the scientific figure and the energy from the app's palette. The one atmospheric device is the app's soft Glows (blue lower-left, purple upper-right, green lower-right), placed behind the figure and behind the app window and nowhere else.

The register is serious and professional. The owner rejected HUD chrome, ALL-CAPS tracked labels, sci-fi copy and DaisyDisk look-alikes for this world. Safety is drawn as line form rather than with badges: a solid line means you can undo, a dashed line means it asks first, and a struck line means MacSafe refuses. Hatching means review first, and space you got back is a labelled cut-out gap.

There are two surfaces. The site (docs/index.html) is set in Hanken Grotesk on #0c1220. The app (MacApp) uses the system font, sits on the native window background with Glows, supports both light and dark appearance, and takes its palette from `MacApp/Sources/Theme.swift`. That file is the palette source of truth for both surfaces.

**Key Characteristics:**
- One figure, end-on: inner ring categories, outer ring folders, radial bars for files, with a centre readout of the total.
- Category gradient pairs in a fixed order, and a neutral track for free and empty.
- Leader-line labels with a ground-colour halo, two tiers (semibold name, lighter value with a smaller unit).
- "Fig. n" captions as a sequence, in sentence case, with tabular figures.
- Safety in line form, hatch for review-first, and cleared space as a cut-out gap.
- Flat page and lifted product: only the drive, the app window, the glossy button and colour tiles carry depth.

## Colors

A deep-navy ground with neutral steel hairlines, lit only by the app's four category pairs and one glossy blue action.

### Primary
- **Applications Blue** (apps-blue → apps-blue-deep): the first category, in the inner ring, the legend dot, and bars for Applications. It is the hue of the Overview selection and of the site's text-selection tint.
- **Glossy Blue** (glossy-top → glossy-deep, glow glossy-shadow): used only for the single primary action on a screen ("Download for Mac", "Review & Clean"). The label is white semibold.

### Secondary
- **Your Files Orange** (files-orange → files-orange-deep): your files. Installers, old downloads and developer leftovers in Free up space take this hue.
- **App Data Green** (appdata-green → appdata-green-deep): app data & caches. Backups and caches take this hue. The same green is the "freeable" text colour and the third glow, low on the right where cleanup lives.
- **macOS Yellow** (system-yellow → system-yellow-deep): macOS & other. The largest category is usually yellow.
- **Free Track** (track): free space and every empty track. It is neutral white at about 8–9% over the ground (the app uses 8%, the site's free arc 9%; in light appearance black at 8%).

### Tertiary
- **Tile tints** (tile-purple, tile-pink, tile-teal, tile-gray, each with a deep partner): sidebar and cleanup ColorTiles only, as the app uses them. They are app chrome and never data. Purple is also the upper-right glow, and tile-gray marks Trash.

### Neutral
- **Deep Navy Ground** (ground): the site's flat page ground. The app equivalent is the native window background.
- **Raised Navy** (ground-2, ground-3): the selected legend row, the command bar fill (at 82%), copy-button hover, and inline code.
- **Desk** (desk-ground) and **Terminal** (terminal-ground): the macOS desktop frame around the app reproduction, and the terminal window. Both are slightly darker than the ground so the lit objects sit in them.
- **Hairlines** (hair, hair-2): every rule, row divider, caption top rule and border. hair-2 is used for stronger structure such as the command bar border, table heads and the steps rule.
- **Steel** (steel): link underlines.
- **Figure hairlines** (figure-hair, leader): ring guides, ticks and leader lines inside the figure.
- **Ink** (ink, ink-2, ink-3): primary text, secondary text (lede, captions, descriptions), and tertiary text (facts, units, credits, footer).
- **Focus** (focus): a 2px focus outline offset 3px. In the figure the focused category draws a #9cc4ff ring.

### App semantic colours
The app pairs each light and dark value: app-accent (links, plain bars), app-freeable (the "You could free up" figure), app-good, app-warning and app-critical (status), and app-glass / app-glass-edge (Card fill and stroke over the Glows).

### Named Rules
**The Category Order Rule.** The four categories always appear in engine order (Applications blue, Your files orange, App data & caches green, macOS & other yellow), always as their top → deep pair, and always from `Theme.swift`. No surface invents a fifth data hue.

**The Neutral Track Rule.** Free and empty space is neutral white at 8–9%, never a hue and never a hue at low alpha over navy, which reads as mud-brown. Dimming an unselected part mixes it toward grey at about 40% opacity, never toward a darker version of its own hue.

**The Tiles Are Chrome Rule.** Purple, pink, teal and gray belong to ColorTiles and the Glows. They never colour a ring, bar or legend dot.

## Typography

**Display Font:** Hanken Grotesk 400/500/600/700 (Google Fonts), falling back to ui-sans-serif and the system stack. Site only.
**App Font:** the system font (SF Pro), using SwiftUI text styles.
**Code Font:** ui-monospace, SF Mono, Menlo. Used for commands, paths and the terminal render only.

**Character:** a plain, slightly warm grotesk with tight negative tracking at size and sentence case everywhere, so the type reads like a journal's figure apparatus rather than product marketing.

### Hierarchy
- **Display** (600, clamp(2.5rem, 4.1vw, 3.6rem), 1.04, balanced wrap): the hero line only. It drops to 2.35rem at 720px and below.
- **Headline** (600, clamp(1.85rem, 3vw, 2.5rem), 1.1): section heads, written as full sentences with a period. The closing head steps up to clamp(2.1rem, 3.6vw, 3.1rem).
- **Title** (600, 19px): step names, front-end names, and the download/FDA/uninstall heads.
- **Lede** (400, 19px, 1.5, max 34ch): the hero paragraph.
- **Body** (400, 17px, 1.55): section intros (max 60ch) and running text.
- **Caption** (400, 15px, 1.55): "Fig. n" captions. The figure number is set in Ink 600 and the rest in Ink 2. Section captions use 14.5px.
- **Label** (400, 14px): nav (15px), command labels, the facts line, notes and the footer.
- **Figure name / Figure value** (600 20px / 400 18.5px in the figure's SVG units, with a 4px ground-colour stroke halo): the two tiers of every leader label. Units are set smaller (16.5px) and lighter.
- **App:** headline 28 bold ("You could free up 26.5 GB", with the figure in the freeable green), figure total 26 semibold tabular, card titles in `.headline`, body in `.callout`, captions in `.caption`, and units at 10.5 medium in secondary colour.

### Named Rules
**The Tabular Figures Rule.** Every number that can sit beside another number (legend values, percentages, sizes, captions, the centre readout) uses tabular figures, with the unit set smaller and lighter after the value.

**The Sentence Case Rule.** Labels, headings, buttons and captions use sentence case. No ALL-CAPS, no tracked-out labels, and no kicker above a heading.

**The Mono Means Code Rule.** Monospace appears only for what can be typed or pasted (the install command, `macsafe`, paths, key glyphs) and inside the terminal render.

## Layout

The site uses a 1360px container with 40px gutters (18px at 720px and below). The hero is a two-column grid: a lead column of minmax(320px, 420px) holds the headline, lede, glossy download, facts line and install command, and the figure takes the rest and bleeds 24px to the right. The download stack sits in the first viewport. Below 1060px everything stacks into one column. Below 720px the figure's leader labels, scale and tick labels hide, and a tappable key list (dot, name, tabular value, percent) replaces them.

Sections open at 110px (80px mobile) with a 640px head block (headline plus intro) and then one evidence grid: two-up asymmetric (1fr / 1.15–1.25fr, 56–64px gaps), a four-step row divided by hairlines (2 then 1 columns as it narrows), or a three-column download/FDA/uninstall row ruled off at the top. Lists and tables are hairline-ruled rows, not cards.

"The same picture, in the app" places the real Overview window (1280×800, scaled to fit) on a macOS desktop frame with a menubar, lit by the same three glows as the hero, with faint figure rings in the wallpaper. At phone width the window reflows as a narrow macOS window (sidebar behind a toggle, figure above legend, finds stacked) instead of shrinking.

The app's Overview is a vertical stack (22pt): the figure beside the headline column (headline, glossy action, glass legend, caption), then the Free up space card, then Biggest folders beside Largest files and Outside your home when the content is at least 820pt wide, and stacked below that. Cards are separated by 16pt.

The figure keeps 4px ground gaps between arcs (converted to degrees per radius) and square arc ends.

## Elevation & Depth

The page is flat. Panels, lists, tables, captions and the command bar sit on the ground with hairlines and no shadows. Depth is reserved for objects that are lifted in real life:

### Shadow Vocabulary
- **Glossy action** (`0 6px 14px -4px rgba(50,100,240,.36), 0 2px 10px rgba(50,100,240,.2)`; hover `.5`/`.3`): the blue glow under the primary button, matching the app's shadow (#3264f0 at 0.36, radius 10, y 5; 0.5 and radius 14 on hover).
- **ColorTile** (`0 1.6px 4px` deep tint at 35%): tiles cast their own colour.
- **App window** (`0 0 0 .5px rgba(255,255,255,.16), 0 30px 80px -12px rgba(0,0,0,.7), 0 10px 24px rgba(0,0,0,.35)`): the reproduction on the desktop frame only.
- **Selected arc** (`drop-shadow(0 0 16px <category hue>)` on the site; a 24pt glow at 0.9 in dark and 10pt at 0.4 in light in the app): at most one glow at a time, on the selected category.

**Glows** (blur 110px): blue #3566e8 at 0.28 lower-left, purple at 0.16 top-right, and green at 0.12 lower-right. In the app light appearance they drop to 55%.

**The drive** (hero, WebGL): a dark machined-aluminium HDD (casing #4b525c, matte) turns from a three-quarter view to end-on, and its platter becomes the SVG figure in one handoff. With no WebGL, a load failure or reduced motion, the SVG figure stands alone and nothing is left at opacity 0.

### Named Rules
**The Lifted Objects Rule.** Only physical things are lifted: the drive, the app window, the glossy action and the ColorTiles. Page structure never casts a shadow.

**The One Glow Rule.** At most one arc glows, and only the selected one.

## Shapes

The figure's arcs have square ends separated by ground gaps, and its hairline rings and ticks are 1px. Leader lines are 0.75px with an angled or radial stem and a short horizontal shoulder, ending in a small dot, with a 3.5px ground halo so they stay unbroken over the metal.

The site chrome uses soft but small corners: inline code 4px, terminal 10px, command bar and app window 12px, glass cards 16px, desktop frame 18px. Actions are capsules (full radius): the glossy button, pills and badges. Bars and state bars use 3px. App cards are continuous-corner 16pt rectangles, ColorTiles round at 0.27 of their size (8pt at 30pt), and row hovers use 8–10pt.

Line form carries meaning: solid 1.6px means reversible, dashed (5 4) means it warns first, a line with a slash and a struck label means refused, 45° hatching means review first, and a dashed outline means it asks before deleting.

## Components

### Buttons
- **Glossy primary:** a capsule with a vertical gradient (glossy-top → #3a6aec at 45% → glossy-deep), a 0.75px top-light border (white 45% → 8%) and a blue glow. The label is white 600. On the site the padding is 12px 24px (10px 20px in the download row) with a 17px download glyph. In the app it is `.body` semibold at 9×20pt (large) or `.callout` at 6×14pt. Hover brightens the whole button (filter 1.1 / white 12% veil) and lifts the glow; press darkens it to 0.88 / black 16%. Disabled is desaturated at 50% opacity. Use one per screen.
- **Copy:** a transparent segment fused to the command bar's right edge behind a hair-2 divider, with a 14px 500 "Copy" label and glyph. Hover fills it with ground-3. Success changes the note under the bar to green and the label to "Copied".
- **Pill (app):** a white 7% capsule with a white 12% border, used for row actions like "Review".

### Command bar
A 12px hair-2 bordered bar on ground-2 at 82%, holding the install command in code type. It breaks only at explicit `<wbr>` points, and the whole command is selectable. A label above ("Or install with Terminal") and a live note below sit with it.

### Figure caption
Below the figure, behind a top hairline: "**Fig. n**" in Ink 600, then one plain sentence in Ink 2 that states the subject, says "example data", and explains how to read the figure. The caption rewrites itself for the selected part. The drive credit sits directly below it, aligned to the caption's left edge, in Ink 3 13px, shown only when the drive rendered.

### Figure key (mobile)
Hairline-ruled rows of a 10px colour dot, name, tabular value with smaller unit, and right-aligned percent. The selected row fills with ground-2.

### Cards / Containers (app)
- **Corner Style:** 16pt continuous.
- **Background:** app-glass over the Glows, with an app-glass-edge stroke.
- **Shadow Strategy:** none (see Elevation).
- **Internal Padding:** 18pt, with a title row (headline, caption subtitle, trailing tabular total or link).

### ColorTile (app)
A rounded square in a tint's top → deep gradient, with a white SF Symbol at 46% of the tile size, a 0.75px white top-light edge, and a shadow in its own deep colour. Sidebar rows use 20–30pt tiles and cleanup items use 30pt.

### State bar (app and site)
A 6px neutral track with a fill in the item's category hue: a solid gradient sweep (deep → top) means safe to clear, 45° hatching over a 22% tint with a 1px outline means review first, and a dashed outline (3 2.4) means it asks before deleting. Trash uses tile-gray.

### Navigation
A 22px-padded bar with no underline: the brand mark plus "MacSafe" in 600 18px on the left, and links on the right in Ink 2 15px that turn Ink on hover, 28px apart. Optional links hide below 720px.

### Lists and Tables
Rows divided by hairlines, with 13–14px vertical padding, a bold name and an Ink 2 description. The safety table leads each row with its line-form glyph and strikes the refused row's label. App tables use caption-weight sortable headers with a chevron, tabular right-aligned sizes and hover tints.

### Terminal render
`macsafe` as real preformatted text in system monospace inside a terminal-ground window with three hair-2 dots in its bar, using the four category colours for the ring and Ink 3 for rules. It is captioned as Fig. 2.

### Cross-section figure (signature)
The disk at its true proportions: hairline ring guides and a tick scale, the inner category ring, the outer folder ring (category hue mixed 42% toward the ground, 10% when selected; unplaced space uses the neutral track), and radial bars for the largest files, one cell per gigabyte, with a "Bar length 1 GB" scale key. The centre readout shows the disk name, total and free space. Labels sit in one justified column per side and never on an arc. Selecting a category greys the others and updates the caption and, in the app, every list below. The hub resets the selection. Transitions run 0.25s on `cubic-bezier(.16,1,.3,1)` and are removed under reduced motion.

### Cut-out (Fig. 4)
Part of the ring with a dashed (2 3) sector outline where cleared space used to be, labelled with a leader ("6.4 GB freed / Caches cleared"), next to the remaining category label.

## Do's and Don'ts

### Do:
- **Do** take every data colour from `Theme.swift` Tint pairs, in category order, as a gradient along the arc or bar.
- **Do** draw free and empty space as the neutral track and dim unselected parts toward grey at about 40%.
- **Do** label the figure with 0.75px leader lines, a ground halo, and two tiers (semibold name; lighter value with a smaller unit).
- **Do** number figures as a real sequence with "Fig. n" captions that say "example data" when the data is illustrative.
- **Do** show safety as line form: solid for undo, dashed for warns first, struck for refused, hatched for review first.
- **Do** keep one glossy blue action per screen and keep its white label at 4.5:1 or better.
- **Do** keep the drive credit under Fig. 1 when the drive renders, and the full CC BY 4.0 attribution in the footer always.
- **Do** let the figure degrade to the SVG on no WebGL, a load failure or reduced motion, with nothing left invisible.

### Don't:
- **Don't** add HUD chrome, corner brackets, scanlines, or sci-fi copy around the figure.
- **Don't** set labels in ALL-CAPS with tracking, or put a kicker above a heading.
- **Don't** echo DaisyDisk: no rainbow hue rotation, no rings beyond the two plus file bars, no circled total badge as the hero, no royal-blue radial page gradient, no tilted stacked screenshots.
- **Don't** tint free space or empty tracks with a hue, or dim a part by lowering a hue's alpha over navy.
- **Don't** put labels on arcs, or fade or mask the drive model.
- **Don't** use the tile tints (purple, pink, teal) as data colours.
- **Don't** add shadows to page panels, lists or tables.
- **Don't** call MacSafe "open source"; say "The source is on GitHub".

### Known debt (not rules)
- Site stylesheet leftovers: an unused `.more .btn` rule, and the terminal's category colours declared twice (once by variable, once by literal hex).
