import AppKit
import SwiftUI

// The Overview's figure: the disk as a cross-section. One scale, 360 degrees = the whole disk, clockwise from
// 12 o'clock. Inner ring: the categories (free space last, as the neutral track). Outer ring: the biggest
// folders in your home, inside the span of the category they belong to. Radial bars: the largest files.

// MARK: - Colour helpers (the palette stays in Theme.swift; this only mixes it)

struct RGB {
    var r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        self.init(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
    /// Luminance-only version: what an unselected category falls back to.
    var grey: RGB { let y = 0.299 * r + 0.587 * g + 0.114 * b; return RGB(r: y, g: y, b: y) }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    /// The window's own ground in the given appearance.
    static func ground(_ scheme: ColorScheme) -> RGB {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        var out = RGB(r: 0.1, g: 0.1, b: 0.1)
        appearance?.performAsCurrentDrawingAppearance {
            if let c = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) {
                out = RGB(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
            }
        }
        return out
    }
}

extension Fmt {
    /// "43.7 GB" as ("43.7", "GB"), so a unit can be drawn smaller.
    static func parts(_ bytes: Int64) -> (num: String, unit: String) {
        let s = size(bytes)
        guard let i = s.lastIndex(of: " ") else { return (s, "") }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }
}

// MARK: - Layout: where every arc and bar goes

struct FigureModel {
    struct Cat: Identifiable {
        let key: String
        let label: String
        let size: Int64
        let share: Double
        let d0: Double
        let d1: Double
        /// nil for free space, which is never a hue.
        let tint: Tint?
        var id: String { key }
    }

    struct Folder: Identifiable {
        let path: String
        let name: String
        let size: Int64
        let cat: String
        let d0: Double
        let d1: Double
        var id: String { path }
    }

    struct Bar: Identifiable {
        let path: String
        let name: String
        let size: Int64
        let cat: String
        let b0: Double
        let b1: Double
        let tip: Double
        var id: String { path }
    }

    // Geometry in a 680 x 680 space (centre 340, 340), as in the approved sketch.
    static let side = 680.0
    static let centre = 340.0
    static let tick0 = 128.0, tick1 = 137.0
    static let cat0 = 148.0, cat1 = 214.0
    static let fold0 = 222.0, fold1 = 254.0
    static let bar0 = 262.0
    static let hub = 102.0
    static let barRoom = 76.0
    static let barPerGB = 30.0
    static let barWidth = 2.8, barGap = 2.6

    let cats: [Cat]
    let folders: [Folder]
    let bars: [Bar]
    let perGB: Double
    let totalBytes: Double
    let disk: Disk

    func cat(_ key: String) -> Cat? { cats.first { $0.key == key } }

    /// Degrees covered by `bytes`.
    func degrees(_ bytes: Int64) -> Double { Double(bytes) / totalBytes * 360 }

    init(_ o: Overview) {
        disk = o.disk
        let used = o.breakdown.reduce(Int64(0)) { $0 + $1.size }
        let total = Double(max(o.disk.total, used + o.disk.free, 1))
        totalBytes = total
        let dpb = 360 / total

        // Categories in the engine's order (engine.py, overview(): apps, files, appdata, system), free last.
        var cats: [Cat] = []
        var cursor = 0.0
        for (i, seg) in o.breakdown.enumerated() {
            let span = Double(seg.size) * dpb
            cats.append(Cat(key: seg.key, label: seg.label, size: seg.size, share: Double(seg.size) / total,
                            d0: cursor, d1: cursor + span, tint: Tint.categories[i % Tint.categories.count]))
            cursor += span
        }
        let freeSpan = Double(o.disk.free) * dpb
        cats.append(Cat(key: "free", label: "Free", size: o.disk.free, share: Double(o.disk.free) / total,
                        d0: cursor, d1: cursor + freeSpan, tint: nil))
        self.cats = cats

        // Folders: engine.py item() flags a home folder `appdata` when it is Library or hidden (F_LIB | F_HIDDEN),
        // and overview() counts exactly those in "App data & caches"; every other home folder is in "Your files".
        // Each is placed in turn from the start of its category. One that would spill past its category isn't drawn.
        var used0: [String: Double] = [:]
        var folders: [Folder] = []
        for item in o.top where item.size > 0 {
            let key = item.appdata == true ? "appdata" : "files"
            guard let c = cats.first(where: { $0.key == key }), c.size > 0 else { continue }
            let from = used0[key] ?? c.d0
            let to = from + Double(item.size) * dpb
            guard to <= c.d1 + 0.05, to - from >= 0.35 else { continue }
            folders.append(Folder(path: item.path, name: item.name, size: item.size, cat: key, d0: from, d1: min(to, c.d1)))
            used0[key] = to
        }
        self.folders = folders

        // Bars: the largest files (engine.py large(include_appdata=False)) that sit under a placed folder, each
        // at its own angle inside that folder, then spread so none is narrower than 2.8 or closer than 2.6 degrees.
        var inFolder: [String: Double] = [:]
        struct Placed { let item: Item; let cat: Cat; let mid: Double }
        var placed: [Placed] = []
        for item in o.large {
            guard let f = folders.first(where: { item.path.hasPrefix($0.path + "/") }),
                  let c = cats.first(where: { $0.key == f.cat }) else { continue }
            let from = inFolder[f.path] ?? f.d0
            let to = from + Double(item.size) * dpb
            guard to <= f.d1 + 0.2 else { continue }
            inFolder[f.path] = to
            placed.append(Placed(item: item, cat: c, mid: (from + to) / 2))
        }
        let maxGB = placed.map { Double($0.item.size) / 1e9 }.max() ?? 1
        let perGB = min(Self.barPerGB, Self.barRoom / max(maxGB, 0.01))
        self.perGB = perGB
        var bars: [Bar] = []
        var prev = -999.0
        for p in placed.sorted(by: { $0.mid < $1.mid }) {
            let b0 = max(p.mid - Self.barWidth / 2, prev + Self.barGap, p.cat.d0)
            let b1 = b0 + Self.barWidth
            guard b1 <= p.cat.d1 + 0.01 else { continue }
            prev = b1
            let gb = Double(p.item.size) / 1e9
            bars.append(Bar(path: p.item.path, name: p.item.name, size: p.item.size, cat: p.cat.key,
                            b0: b0, b1: b1, tip: Self.bar0 + max(gb * perGB, 5)))
        }
        self.bars = bars
    }

    /// Which category a point in figure space belongs to (nil for the hub, the gaps and empty corners).
    func category(atX x: Double, y: Double) -> String? {
        let dx = x - Self.centre, dy = y - Self.centre
        let r = (dx * dx + dy * dy).squareRoot()
        var a = atan2(dx, -dy) * 180 / .pi
        if a < 0 { a += 360 }
        if r >= Self.cat0 - 4 && r <= Self.fold1 + 6 {
            return cats.first { a >= $0.d0 && a < $0.d1 }?.key
        }
        if r > Self.fold1 + 6 {
            return bars.first { a >= $0.b0 - 1 && a <= $0.b1 + 1 && r <= $0.tip + 4 }?.cat
        }
        return nil
    }

    func isHub(atX x: Double, y: Double) -> Bool {
        let dx = x - Self.centre, dy = y - Self.centre
        return (dx * dx + dy * dy).squareRoot() < Self.hub
    }
}

// MARK: - The figure

struct CrossSectionFigure: View {
    let model: FigureModel
    let diskName: String
    @Binding var selection: String?
    @State private var reveal = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 340

    var body: some View {
        let s = size / FigureModel.side
        ZStack {
            FigureCanvas(model: model, selection: selection, reveal: reveal)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .onTapGesture { p in
                    let x = p.x / s, y = p.y / s
                    if model.isHub(atX: x, y: y) { selection = nil; return }
                    guard let key = model.category(atX: x, y: y) else { return }
                    selection = selection == key ? nil : key
                }
            centre
                .frame(width: 118)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion { reveal = 1 } else { withAnimation(Motion.settle.speed(0.55)) { reveal = 1 } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cross-section of \(diskName): \(Fmt.size(model.disk.free)) free of \(Fmt.size(model.disk.total)). Use the breakdown list to focus a category.")
    }

    private var centre: some View {
        let sel = selection.flatMap { model.cat($0) }
        return VStack(spacing: 1) {
            Text(sel?.label ?? diskName).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(Fmt.size(sel?.size ?? model.disk.free))
                .font(.system(size: 26, weight: .semibold)).monospacedDigit().foregroundStyle(.primary)
            Text(sel.map { "\($0.share.formatted(.percent.precision(.fractionLength(0)))) of \(Fmt.size(model.disk.total))" }
                 ?? "free of \(Fmt.size(model.disk.total))")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// The drawing itself. `reveal` animates the rings outward on first appearance.
private struct FigureCanvas: View, Animatable {
    let model: FigureModel
    let selection: String?
    var reveal: Double
    @Environment(\.colorScheme) private var scheme

    var animatableData: Double {
        get { reveal }
        set { reveal = newValue }
    }

    private typealias M = FigureModel

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / M.side
            var ctx = context
            ctx.scaleBy(x: s, y: s)
            draw(&ctx, px: 1 / s)
        }
    }

    private func pt(_ r: Double, _ deg: Double) -> CGPoint {
        let a = deg * .pi / 180
        return CGPoint(x: M.centre + r * sin(a), y: M.centre - r * cos(a))
    }

    /// A ring segment with square ends. Arcs are short straight steps, fine enough that they read as curves.
    private func sector(_ r0: Double, _ r1: Double, _ d0: Double, _ d1: Double) -> Path {
        var p = Path()
        let steps = max(2, Int(ceil((d1 - d0) / 0.4)))
        p.move(to: pt(r1, d0))
        for i in 1...steps { p.addLine(to: pt(r1, d0 + (d1 - d0) * Double(i) / Double(steps))) }
        for i in 0...steps { p.addLine(to: pt(r0, d1 - (d1 - d0) * Double(i) / Double(steps))) }
        p.closeSubpath()
        return p
    }

    private func gapDegrees(_ units: Double, at r: Double) -> Double { units / r * 180 / .pi }

    /// Colour running along the sweep, from `a` at the start of the span to `b` at its end.
    private func sweep(_ a: Color, _ b: Color, from d0: Double, to d1: Double) -> GraphicsContext.Shading {
        let f = max((d1 - d0) / 360, 0.0005)
        return .conicGradient(Gradient(stops: [.init(color: a, location: 0), .init(color: b, location: f),
                                               .init(color: b, location: 1)]),
                              center: CGPoint(x: M.centre, y: M.centre), angle: .degrees(d0 - 90))
    }

    private func draw(_ ctx: inout GraphicsContext, px: Double) {
        let ground = RGB.ground(scheme)
        let gap = 4.0
        let hairline = Color.primary.opacity(scheme == .dark ? 0.2 : 0.22)

        // Scale: a tick every 10 GB, heavier every 50, inside the inner ring.
        ctx.stroke(Path(ellipseIn: CGRect(x: M.centre - M.tick1, y: M.centre - M.tick1, width: M.tick1 * 2, height: M.tick1 * 2)),
                   with: .color(hairline), lineWidth: px)
        var g = 0.0
        while g * 1e9 < model.totalBytes {
            let major = Int(g) % 50 == 0
            let deg = g * 1e9 / model.totalBytes * 360
            var t = Path()
            t.move(to: pt(M.tick1, deg))
            t.addLine(to: pt(major ? M.tick0 - 2 : M.tick0 + 3, deg))
            ctx.stroke(t, with: .color(Color.primary.opacity(major ? 0.5 : 0.3)), lineWidth: px)
            g += 10
        }

        // Everything below reveals outward from the scale.
        var c = ctx
        if reveal < 1 {
            let r = M.tick0 + (M.side / 2 - M.tick0) * max(0, reveal)
            c.clip(to: Path(ellipseIn: CGRect(x: M.centre - r, y: M.centre - r, width: r * 2, height: r * 2)))
        }

        for cat in model.cats {
            let on = selection == cat.key
            let dim = selection != nil && !on
            // Unselected parts fall back toward grey at ~40%, never toward a darker version of their hue.
            let veil = dim ? 0.4 : 1.0

            let gi = gapDegrees(gap / 2, at: (M.cat0 + M.cat1) / 2)
            let span = cat.d1 - cat.d0
            let inset = span > gi * 2 + 0.4 ? gi : 0
            let inner = sector(M.cat0, M.cat1, cat.d0 + inset, cat.d1 - inset)

            guard let tint = cat.tint else {
                if span > 0.05 { c.fill(inner, with: .color(Palette.track.opacity(veil))) }
                continue
            }
            let top = RGB(tint.top), bottom = RGB(tint.bottom)
            func shade(_ x: RGB) -> Color { (dim ? x.grey : x).color.opacity(veil) }

            if on {
                c.drawLayer { l in
                    // Softer in light mode, so the hub stays clean behind its text.
                    l.addFilter(.shadow(color: tint.top.opacity(scheme == .dark ? 0.9 : 0.4), radius: scheme == .dark ? 24 : 10, x: 0, y: 0))
                    l.fill(inner, with: sweep(shade(top), shade(bottom), from: cat.d0, to: cat.d1))
                }
            } else {
                c.fill(inner, with: sweep(shade(top), shade(bottom), from: cat.d0, to: cat.d1))
            }

            // Outer ring: placed folders in the category hue mixed toward the ground; the rest is the neutral track.
            let mixAmount = on ? 0.1 : 0.42
            let gf = gapDegrees(gap / 2, at: (M.fold0 + M.fold1) / 2)
            var covered = cat.d0
            for f in model.folders where f.cat == cat.key {
                let narrow = f.d1 - f.d0 > gf * 2 + 0.3
                let a = narrow ? f.d0 + gf : f.d0, b = narrow ? f.d1 - gf : f.d1
                c.fill(sector(M.fold0, M.fold1, a, b),
                       with: sweep(shade(top.mixed(with: ground, mixAmount)), shade(bottom.mixed(with: ground, mixAmount)),
                                   from: f.d0, to: f.d1))
                covered = f.d1
            }
            if cat.d1 - covered > 0.3 {
                c.fill(sector(M.fold0, M.fold1, covered + gf, cat.d1 - gf), with: .color(Palette.track.opacity(veil)))
            }

            // Radial bars: 1 GB cells, a little deeper at the root and brightening outward.
            let cell = model.perGB >= 14
            for bar in model.bars where bar.cat == cat.key {
                let gb = Double(bar.size) / 1e9
                for k in 0..<max(1, Int(ceil(gb))) {
                    let r0 = M.bar0 + Double(k) * model.perGB + (k > 0 && cell ? 2 : 0)
                    let r1 = min(bar.tip, M.bar0 + Double(k + 1) * model.perGB)
                    guard r1 > r0 else { continue }
                    let mix = bottom.mixed(with: top, min(1, Double(k + 1) / 3))
                    c.fill(sector(r0, r1, bar.b0, bar.b1), with: .color(shade(mix)))
                }
            }
        }
    }
}
