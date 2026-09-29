---
name: MacSafe
description: Download site for a free Mac disk-space app and terminal dashboard; graphite developer-tool chrome around the product's own data colours.
colors:
  data-blue: "#3987e5"
  data-orange: "#d95926"
  data-aqua: "#199e70"
  data-yellow: "#c98500"
  data-track: "#2c2c2a"
  status-good: "#3fb950"
  status-warn: "#e3a008"
  status-bad: "#f0645a"
  graphite-ground: "#0a0b0d"
  graphite-surface: "#111316"
  graphite-raise: "#16191d"
  hairline: "#22262c"
  ink: "#eceef1"
  ink-muted: "#8d939c"
  ink-faint: "#7c838e"
  terminal-ground: "#0e1014"
  terminal-rule: "#2a2f37"
  terminal-titlebar: "#1a1d22"
  window-ground: "#1f1f21"
  window-sidebar: "#2a292d"
  window-card: "#28282b"
  window-line: "#38383c"
typography:
  display:
    fontFamily: "Mona Sans, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(2.6rem, 6vw, 4.6rem)"
    fontWeight: 600
    lineHeight: 1.02
    letterSpacing: "-0.035em"
    fontVariation: "'wdth' 112"
  headline:
    fontFamily: "Mona Sans, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(1.6rem, 2.8vw, 2.1rem)"
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: "-0.025em"
    fontVariation: "'wdth' 106"
  title:
    fontFamily: "Mona Sans, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.1rem"
    fontWeight: 600
    lineHeight: 1.6
    letterSpacing: "-0.02em"
    fontVariation: "'wdth' 106"
  lede:
    fontFamily: "Mona Sans, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(1.05rem, 1.5vw, 1.2rem)"
    fontWeight: 400
    lineHeight: 1.55
  body:
    fontFamily: "Mona Sans, Helvetica Neue, Arial, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.6
  body-small:
    fontFamily: "Mona Sans, Helvetica Neue, Arial, sans-serif"
    fontSize: "0.93rem"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "Mona Sans, Helvetica Neue, Arial, sans-serif"
    fontSize: "0.88rem"
    fontWeight: 400
    lineHeight: 1.4
  caption:
    fontFamily: "Mona Sans, Helvetica Neue, Arial, sans-serif"
    fontSize: "0.82rem"
    fontWeight: 400
    lineHeight: 1.6
  code:
    fontFamily: "Fragment Mono, ui-monospace, Menlo, monospace"
    fontSize: "0.82rem"
    fontWeight: 400
    lineHeight: 1.5
rounded:
  xs: "5px"
  sm: "7px"
  md: "10px"
  lg: "12px"
spacing:
  gutter: "max(16px, 4vw)"
  container: "74rem"
  label-column: "17rem"
  section: "clamp(5.5rem, 10vw, 8.5rem)"
  panel: "1.5rem"
  row: "1.05rem"
components:
  button-copy:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.graphite-ground}"
    typography: "{typography.caption}"
    rounded: "{rounded.sm}"
    padding: "0.55rem 0.8rem"
  button-copy-hover:
    backgroundColor: "#ffffff"
    textColor: "{colors.graphite-ground}"
  button-copy-done:
    backgroundColor: "{colors.status-good}"
    textColor: "{colors.graphite-ground}"
  button-download:
    backgroundColor: "{colors.graphite-raise}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "8px"
    padding: "0.55rem 0.9rem"
  command-bar:
    backgroundColor: "{colors.graphite-surface}"
    textColor: "{colors.ink}"
    typography: "{typography.code}"
    rounded: "{rounded.md}"
    padding: "0.45rem 0.45rem 0.45rem 1rem"
  panel:
    backgroundColor: "{colors.graphite-surface}"
    textColor: "{colors.ink-muted}"
    rounded: "{rounded.lg}"
    padding: "{spacing.panel}"
  code-inline:
    backgroundColor: "{colors.graphite-raise}"
    textColor: "{colors.ink}"
    rounded: "{rounded.xs}"
    padding: "0.05rem 0.35rem"
  nav-link:
    textColor: "{colors.ink-muted}"
    typography: "{typography.label}"
  nav-link-hover:
    textColor: "{colors.ink}"
  terminal-window:
    backgroundColor: "{colors.terminal-ground}"
    textColor: "#d8dde6"
    rounded: "{rounded.md}"
    width: "520px"
---

# Design System: MacSafe

## Overview

**Creative North Star: "The Instrument Panel"**

The MacSafe site is a quiet graphite panel with the product mounted in it. The chrome is dark neutral, near-black, and has no hue of its own. It is drawn with 1px hairlines rather than fills or shadows, so the eye goes to the two real renders it frames: the Overview window of the Mac app and the `macsafe` terminal dashboard. The only saturated colour anywhere is the product's own data palette. When blue, orange, aqua or yellow appears, it is measuring a disk.

The register is serious and professional, at the level of Raycast, Linear, Tailscale and Apple's macOS pages. The user rejected playful and illustrative directions (cardboard boxes, food labels, sci-fi consoles) as childish. Density is moderate: a left label column carries each section title and a one-line gloss, and the right column carries the evidence as tables, hairline lists, numbered steps and command bars. Type does the hierarchy work. Mona Sans runs slightly wide on headings, and Fragment Mono appears only where something could be pasted or typed.

The page has no grid background, no gradient washes and no decorative art. It has one motion moment, when the disk bar in the app mock settles into its proportions on load.

**Key Characteristics:**
- Graphite ground (#0a0b0d) with hairline (#22262c) structure. Surfaces are separated by tone and rule, not by shadow.
- All colour comes from the app's data palette (blue, orange, aqua, yellow) plus three status dots.
- The primary action is an off-white button on graphite, not a coloured one.
- Mona Sans at 600 with its width axis opened to 106–112% on headings. Fragment Mono only for code and commands.
- The product renders are the only raised, shadowed objects on the page.
- One authored motion: the disk-bar segments settle on load.

## Colors

The palette is graphite neutrals plus the Mac app's categorical data colours. It is restrained everywhere except where data is being shown.

### Primary
- **Disk Blue** (data-blue): the app's first series slot (Applications) and its accent. On the page it also serves as the focus ring, the text-selection highlight, the selected sidebar row in the app mock, and the accent glyph and active tab in the terminal render. It is the only colour the chrome borrows.

### Secondary
- **Kiln Orange** (data-orange): series slot 2, "Your files". Data only.
- **Mint Aqua** (data-aqua): series slot 3, "App data & caches". Data only.
- **Amber Yellow** (data-yellow): series slot 4, "macOS & other". Data only.
- **Free-space Track** (data-track): the unfilled "Free" segment, and the rail under progress and size bars.

These are the dark-appearance values of `Palette.series`, `Palette.accent` and `Palette.track` in `MacApp/Sources/Theme.swift`. The page copies them. It does not define them. The brand mark and favicon use the light-appearance steps from the same file (#2a78d6, #eb6834, #1baf7a, #eda100), because the mark is drawn on its own navy tile (#171c29 to #29334a) rather than on a data surface.

### Tertiary
- **Status Green / Amber / Coral** (status-good, status-warn, status-bad): 0.5rem dots in the safety table meaning reversible, irreversible-with-warning and refused. Status Green also fills the Copy button for 1.8s after a successful copy. These are the web page's own values, tuned for the graphite ground. They are not the app's `good`/`warning`/`critical`.

### Neutral
- **Graphite Ground** (graphite-ground): page background and `theme-color`. Also the text colour on the off-white Copy button.
- **Graphite Surface** (graphite-surface): command bars, feature-comparison panels, install cards, table header row.
- **Graphite Raise** (graphite-raise): one step up, for inline `code`, `kbd` and the download button.
- **Hairline** (hairline): every border, divider and rule on the page (nav underline, list rows, table rows, panel edges, step spine, footer rule).
- **Ink** (ink): headings, body emphasis, command text. It is also the fill of the primary button.
- **Ink Muted** (ink-muted): ledes, section glosses, list descriptions, nav links at rest, footer.
- **Ink Faint** (ink-faint): captions, the `$ ` prompt, facts-row separators, link underlines at rest. It is the lowest-contrast text allowed. It measures about 5:1 on the ground, so don't go darker.
- **Terminal Ground / Rule / Titlebar**: the terminal render's own darker, slightly blue-shifted set, which keeps it reading as a separate app window.
- **Window Ground / Sidebar / Card / Line**: macOS dark-appearance approximations, used only inside the app-window mock.

### Named Rules
**The Data Is the Colour Rule.** Chromatic hues on this site mean data. Blue, orange, aqua and yellow appear only as disk categories, in their fixed series order (blue Applications, orange Your files, aqua App data & caches, yellow macOS & other). The one exception is Disk Blue as the interaction accent. No section tint, no brand gradient, no coloured headline.

**The Theme.swift Is the Source Rule.** The data colours and app-window colours are reproductions. If the app's palette changes, change `Theme.swift` first and then carry the values here. Never tune a mock colour away from the shipping app.

## Typography

**Display Font:** Mona Sans (with Helvetica Neue, Arial). It is loaded as a variable font over width 75–125 and weight 400–800.
**Body Font:** Mona Sans.
**Label/Mono Font:** Fragment Mono (with ui-monospace, Menlo).

**Character:** Mona Sans opened slightly wide on headings gives an engineered, confident voice without shouting, and at body sizes it stays neutral and readable. Fragment Mono is plain and slightly warm, and it marks things you can type.

### Hierarchy
- **Display** (600, clamp(2.6rem, 6vw, 4.6rem), 1.02, width 112%): the single hero headline, left-aligned and capped at 15ch so it breaks into two lines.
- **Headline** (600, clamp(1.6rem, 2.8vw, 2.1rem), 1.1, width 106%): section titles in the left label column. These are sentence-case statements that end with a full stop.
- **Title** (600, 1.1–1.15rem, width 106%): panel and card headings.
- **Lede** (400, clamp(1.05rem, 1.5vw, 1.2rem), 1.55): hero lede in Ink Muted, max 40rem, with one bold phrase lifted to Ink at weight 500.
- **Body** (400, 1rem, 1.6): running text. Inside panels, lists and cards it steps down to 0.92–0.95rem in Ink Muted, with the item name in Ink at weight 500.
- **Label** (400, 0.88rem): nav links, facts row, definition lists, download button.
- **Caption** (400, 0.82rem): figure captions and footer, in Ink Faint or Ink Muted.
- **Code** (Fragment Mono 400, 0.82rem, 1.5): install and uninstall commands (0.76rem inside cards), and inline `code` at 0.86em.

The weights in use are 400, 500 and 600. Weight 500 is emphasis inside muted text. Weight 600 is headings. Headings get `text-wrap: balance` and negative tracking (-0.02em to -0.035em) that tightens as size grows.

### Named Rules
**The Mono Means Code Rule.** Monospace marks something you could paste or type: commands, paths, flags, key names, and the terminal render. Facts, labels, headers and metadata are set in Mona Sans. The facts row under the hero is deliberately not mono.

**The Wide Headline Rule.** Headings are Mona Sans 600 with the width axis opened to 106%, and 112% for the hero. Body text stays at the default width. Don't use the width axis on running text.

## Layout

The page is a single left-aligned column system, with a container of max 74rem, centred, and gutters of max(16px, 4vw).

- **Hero:** stacked with a 1.6rem gap: headline, lede, command bar (max 48rem), facts row. Below them, the full-width app window starts clamp(3rem, 6vw, 4.5rem) down, with a caption under it. Nothing sits beside the headline.
- **Sections:** a two-column grid, with a label column (minmax(0, 17rem)) holding the h2 and a one-line gloss, and an evidence column. Column gap is clamp(2rem, 5vw, 4.5rem). Sections are separated by clamp(5.5rem, 10vw, 8.5rem) of empty space, with no rules or bands between them.
- **Evidence forms:** two-up panels sharing a single hairline border, a two-column hairline list, a bordered table, a numbered step spine, and two-up cards.
- **At 900px** the label column stacks above its evidence, and the nav drops to brand and GitHub.
- **At 640px** every two-up form becomes one column. The safety table becomes stacked rows (header hidden, action name on its own line). The facts row drops its middle-dot separators and wraps on gap alone.
- **The app mock** is its own container. It sizes its whole UI from one unit (`--u`, 13px at full width) scaled to the container, and below 620px of container width it drops the sidebar and shows traffic lights in the toolbar. The terminal render sizes its monospace font to fit 66 columns, and in the two-column section it is capped at 520px.

## Elevation & Depth

The page itself is flat. Depth comes from three tonal steps (Ground, Surface, Raise) and 1px Hairline borders. Only the two product renders cast shadows. They are the objects, and everything else is the panel they sit in.

### Shadow Vocabulary
- **App window** (`box-shadow: 0 2.4em 5em -1.8em rgba(0,0,0,.38), 0 0 0 1px rgba(255,255,255,.1)`): a long, soft drop plus a light edge ring, like a macOS window on a dark desktop.
- **Terminal window** (`box-shadow: 0 16px 32px -14px rgba(0,0,0,.75)`): shorter and denser, for the smaller window.
- **In-mock button** (`box-shadow: 0 1px 1px rgba(0,0,0,.06)`): part of the app reproduction, not a page token.

### Named Rules
**The Product Casts the Only Shadow Rule.** Panels, cards, tables, command bars and buttons have no shadow. They are defined by tone and hairline. A shadow on this page means "this is a real window from the product."

## Shapes

Corners are gently rounded and grow with the size of the container. Inline code and kbd use 5px. The Copy button uses 7px and the download button 8px. The command bar and terminal window use 10px. Panels, tables and cards use 12px. Status dots and step counters are full circles. The app mock uses its own macOS-scaled radii (0.85em window, 0.95em cards, 0.45em rows). Borders are always 1px Hairline and never heavier. Grouped panels share one outer border with internal hairline dividers rather than each being boxed separately.

## Components

### Buttons
Buttons here are quiet, and the only emphatic one is the Copy button.
- **Primary (Copy):** Ink fill with Graphite Ground text, 500 weight at 0.82rem, 7px radius, 0.55rem 0.8rem padding, min-width 5.4rem, with a line-stroke copy icon. It sits inside the right end of a command bar.
- **Hover / Focus:** hover lifts the fill to pure white. Focus is the page-wide 2px Disk Blue outline at 3px offset. After a copy, the label becomes "Copied" on Status Green for 1.8s. If clipboard access fails, the command text is selected and the label says "Press ⌘C".
- **Secondary (Download):** Graphite Raise fill, Hairline border, Ink text at 0.88rem/500, 8px radius, and a download icon. Hover brightens the border to Ink Faint.

### Command Bar (signature)
The command bar is how the page asks for action. It is a Graphite Surface bar with a Hairline border and 10px radius, containing the command in Fragment Mono with a faint `$ ` prompt, and a Copy button flush right. Commands wrap only at `<wbr>` points (`white-space: pre-wrap`, no word breaking). In the narrower install cards, the command takes the full width and the button drops below it, right-aligned.

### Cards / Containers
- **Corner Style:** 12px.
- **Background:** Graphite Surface.
- **Shadow Strategy:** none (see Elevation).
- **Border:** 1px Hairline. Two-up panels share one border with a hairline divider between them.
- **Internal Padding:** 1.5–1.6rem.

### Lists and Tables
- **Hairline list:** rows divided by Hairline top and bottom, with a 1.05rem vertical rhythm. Each row has a muted line icon, an Ink 500 name and a muted description.
- **Table:** bordered 12px wrapper, 0.85rem 1.1rem cells, hairline row dividers. Status is shown with a coloured dot plus a muted word, never colour alone. Key names sit in small raised `kbd` chips.
- **Step spine:** a vertical Hairline with circular numbered markers (Ground fill, Hairline ring, muted numeral). The bold step name is followed by a muted explanation.

### Navigation
A 3.6rem bar with a Hairline underline. The brand mark and "MacSafe" (600) sit left. Links are Label size in Ink Muted and turn Ink on hover, with no underline. Section links hide below 900px and GitHub stays.

### Icons
Line icons on a 24px grid with 1.7–1.8 stroke and round caps and joins, inlined as SVG symbols and coloured with `currentColor`. They are muted in lists and Disk Blue inside the app mock.

### App Window Mock (signature)
The app's Overview screen rebuilt in HTML, in the macOS dark appearance, using the system font stack (it is the app, not the site). It contains traffic lights, sidebar navigation with the selected row in Disk Blue with white text, the segmented disk bar, a legend with tabular figures, quick-win cards and size bars. The white-on-Disk-Blue selected row is deliberately faithful to the shipping app. That pairing belongs to product reproductions only. The whole mock is one `role="img"` with a full text description.

### Terminal Render
The `macsafe` dashboard as real preformatted text in a system monospace (chosen for accurate box-drawing metrics) inside a window with traffic lights and a Terminal Titlebar. The donut chart is made of background-coloured character cells in the series colours. Rules and borders use the dim terminal rule colour. It is also a single `role="img"` with a description.

### Motion
The single authored moment is the app mock's disk-bar segments, which grow from 45% to full width over 1.1s on `cubic-bezier(.16, 1, .3, 1)`, staggered 0.06s per segment. It is fully disabled under `prefers-reduced-motion`. State changes (hover colours) are instant, with no transitions.

## Do's and Don'ts

### Do:
- **Do** draw structure with 1px Hairline borders and the Ground / Surface / Raise tonal steps.
- **Do** keep the series colours in their fixed category order and pull them from `MacApp/Sources/Theme.swift`.
- **Do** make the single primary action an Ink-filled button on graphite, with a Copied state on Status Green.
- **Do** pair every status colour with a word, as in the dot-plus-label pattern in the safety table.
- **Do** set headings in Mona Sans 600 at width 106% (112% for the hero) with balanced wrapping and negative tracking.
- **Do** show the real product (the app window, the terminal output) as the page's imagery, labelled as example data.
- **Do** break long commands only at explicit `<wbr>` points.

### Don't:
- **Don't** add a grid, dot or noise background behind the page or hero.
- **Don't** set facts, labels, table headers or metadata in monospace. Mono is for code, commands and the terminal render.
- **Don't** introduce a brand colour, gradient or tinted section outside the app's data palette.
- **Don't** put shadows on page panels, cards or buttons. Only product renders are lifted.
- **Don't** add more motion than the disk-bar settle. No scroll reveals and no hover lifts.
- **Don't** use white small text on Disk Blue in page UI. That pairing belongs to the faithful app reproduction only.
- **Don't** use illustrative or playful metaphors (boxes, labels, consoles) or centred-column download-page tropes like checkmark feature lists.
- **Don't** use text lighter than Ink Faint on the graphite ground.

### Known debt (not rules)
- At 390px wide, the hero install command wraps after the hyphen in "gabrielesarria167-" instead of at a `<wbr>` point.
- The safety-table column headers are set in uppercase Fragment Mono with tracking, and the step counters use mono numerals. Both break the Mono Means Code Rule and should move to Mona Sans.
- Definition-list terms and `kbd` chips use `ui-monospace` instead of Fragment Mono. They should be unified onto Fragment Mono. The terminal render's system mono is intentional.
- The stylesheet's opening comment still describes a "hairline-grid hero". There is no grid, so the comment is stale.
