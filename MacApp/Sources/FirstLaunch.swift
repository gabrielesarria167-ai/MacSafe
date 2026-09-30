import AppKit
import SwiftUI

/// Shown until the first scan exists: Full Disk Access first, then a Scan button, the scan itself and
/// a summary of what it found. After that the window switches to the normal sidebar layout.
struct FirstLaunchView: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The storage ring is one object that moves from the Scan button to the scan and on to the results.
    @Namespace private var flow
    /// The Scan screen replays the move from step 1 to 2 when it was just reached from step 1.
    @State private var cameFromAccess = false

    var body: some View {
        ZStack {
            Glows(green: false)
            current
        }
        .animation(stepAnimation, value: step.key)
        .onChange(of: step.key) { (old: String, new: String) in
            cameFromAccess = (old == "access") && (new == "ready")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .toolbar { VersionToolbarItem() }
    }

    private var stepAnimation: Animation {
        reduceMotion ? Animation.easeInOut(duration: 0.2) : Motion.settle
    }

    @ViewBuilder private var current: some View {
        switch step {
        case .access:
            AccessStep().transition(slide(out: -1))
        case .ready:
            ReadyStep(flow: flow, advanced: cameFromAccess).transition(slide(out: 1))
        case .scanning:
            ScanningStep(flow: flow).transition(.opacity)
        case .results(let o):
            ResultsStep(flow: flow, overview: o).transition(.opacity)
        }
    }

    private enum Step {
        case access, ready, scanning, results(Overview)
        var key: String {
            switch self {
            case .access: return "access"
            case .ready: return "ready"
            case .scanning: return "scanning"
            case .results: return "results"
            }
        }
    }

    private var step: Step {
        // Stays on the scanning step until the first scan's results are loaded, so it never flashes back.
        if store.isScanning || store.firstScanRunning { return .scanning }
        if store.firstScanResults, let o = store.overview { return .results(o) }
        return store.status?.fda == false && !store.accessSkipped ? .access : .ready
    }

    /// Access and Ready slide past each other sideways; the side a step leaves by is the one it came from.
    private func slide(out edge: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .offset(x: edge * 48).combined(with: .opacity),
                                              removal: .offset(x: edge * 48).combined(with: .opacity))
    }
}

enum Motion {
    /// The site's exponential ease-out (cubic-bezier(.16, 1, .3, 1)).
    static let settle = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.6)
}

// MARK: - pieces

/// The shield icon's storage colours, brighter than the in-app category palette.
enum Brand {
    static let storage: [Color] = Tint.categories.map(\.top)
    static let blue = Color(nsColor: NSColor(hex: 0x3566e8))
}

/// Four arcs in the storage colours, filled clockwise from 12 o'clock up to `progress`.
struct StorageRing: View {
    var progress: Double = 1
    var lineWidth: CGFloat = 12
    var glow = true
    private let bounds: [(Double, Double)] = [(0, 0.25), (0.25, 0.45), (0.45, 0.72), (0.72, 1)]

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            ForEach(0..<4, id: \.self) { i in
                let gap = progress > 0.05 ? 0.006 : 0
                let from = bounds[i].0 * progress + gap, to = bounds[i].1 * progress - gap
                if to > from {
                    Circle().trim(from: from, to: to)
                        .stroke(Brand.storage[i], style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .padding(lineWidth / 2)
        .shadow(color: glow ? Brand.blue.opacity(0.35) : .clear, radius: 16)
    }
}

private struct StepDots: View {
    let step: Int
    /// Arrive showing the previous step, then advance: the pill slides along in place.
    var advanced = false
    @State private var shown: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let current = shown ?? step
        HStack(spacing: 6) {
            ForEach(1...2, id: \.self) { i in
                Capsule().fill(i == current ? Palette.accent : Color.primary.opacity(0.18))
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
            Text("Step \(current) of 2").font(.caption).foregroundStyle(.secondary).padding(.leading, 6)
                .contentTransition(.numericText())
        }
        .onAppear {
            guard advanced, !reduceMotion else { return }
            shown = step - 1
            withAnimation(Motion.settle.delay(0.35)) { shown = step }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step) of 2")
    }
}

private struct CheckLine: View {
    let text: String
    var color: Color = .green

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(color)
        }
        .font(.callout)
    }
}

private struct Chip: View {
    let text: String

    var body: some View {
        CheckLine(text: text)
            .font(.caption)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
            .foregroundStyle(.secondary)
    }
}

private struct AppIcon: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: Brand.blue.opacity(0.45), radius: 18)
            .accessibilityHidden(true)
    }
}

// MARK: - 1 · Full Disk Access

private struct AccessStep: View {
    @Environment(Store.self) private var store

    var body: some View {
        HStack(alignment: .center, spacing: 56) {
            VStack(alignment: .leading, spacing: 18) {
                StepDots(step: 1)
                AppIcon(size: 64)
                Text("Let MacSafe see your whole disk")
                    .font(.system(size: 30, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("macOS keeps Mail, Messages, Safari and parts of your Library private until you allow it. Without Full Disk Access, MacSafe can't measure them and your totals come up short.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    CheckLine(text: "MacSafe only reads sizes and dates")
                    CheckLine(text: "Nothing leaves your Mac")
                    CheckLine(text: "Turn it off any time in System Settings")
                }
                HStack(spacing: 10) {
                    Button("Open System Settings") { store.openFullDiskAccessSettings() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Button("Skip for Now") { store.accessSkipped = true }
                        .help("MacSafe still works, but its totals leave out the private folders.")
                }
                .controlSize(.large)
                .padding(.top, 6)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for access. MacSafe continues on its own once it's on.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if store.openedAccessSettings {
                    HStack(spacing: 6) {
                        Text("Turned it on but nothing happens?")
                        Button("Quit & Reopen MacSafe") { store.relaunch() }
                            .buttonStyle(.link)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)

            SettingsHint()
                .frame(maxWidth: 380)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A simplified picture of the Full Disk Access list, so people know what to look for.
private struct SettingsHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("IN SYSTEM SETTINGS › PRIVACY & SECURITY")
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Full Disk Access").font(.headline).padding(.horizontal, 4).padding(.bottom, 6)
                Divider().padding(.bottom, 4)
                row(icon: NSApp.applicationIconImage, name: "MacSafe", on: true, highlighted: true)
                row(icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app"),
                    name: "Terminal", on: false, highlighted: false)
                HStack(spacing: 4) {
                    ForEach(["plus", "minus"], id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.caption.weight(.semibold))
                            .frame(width: 24, height: 20)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            }
            .padding(16)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            Text("Turn MacSafe on. Not in the list? Click **+** and choose MacSafe from Applications.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func row(icon: NSImage, name: String, on: Bool, highlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: icon).resizable().frame(width: 26, height: 26)
            Text(name)
            Spacer()
            Capsule().fill(on ? Color.green : Color.primary.opacity(0.2))
                .frame(width: 38, height: 22)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(.white).padding(2).shadow(radius: 1)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(highlighted ? Palette.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(highlighted ? Palette.accent : .clear, lineWidth: 2))
    }
}

// MARK: - 2 · Ready to scan

private struct ReadyStep: View {
    @Environment(Store.self) private var store
    let flow: Namespace.ID
    let advanced: Bool

    var body: some View {
        VStack(spacing: 26) {
            StepDots(step: 2, advanced: advanced)
            Text(store.status?.scan.state == "stopped" ? "Scan stopped" : "Ready when you are")
                .font(.system(size: 28, weight: .bold))
            ScanButton { Task { await store.startFirstScan() } }
                .matchedGeometryEffect(id: "ring", in: flow)
            if let disk = store.status?.disk {
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(LinearGradient(colors: [Brand.blue, Palette.accent], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * Double(disk.used) / Double(max(disk.total, 1)))
                        }
                    }
                    .frame(width: 320, height: 8)
                    (Text("\(Fmt.size(disk.used)) used · ") + Text("\(Fmt.size(disk.free)) free").bold().foregroundColor(.primary)
                        + Text(" of \(Fmt.size(disk.total))"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if store.status?.fda == true {
                Chip(text: "Full Disk Access on")
            } else {
                Button { store.accessSkipped = false } label: {
                    Label("Give Full Disk Access…", systemImage: "lock.shield")
                }
                .buttonStyle(PillButtonStyle())
                .help("Without it, MacSafe leaves Mail, Messages, Safari and parts of your Library out of its totals.")
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The first scan's one big control: a lit glass disc inside the storage ring. The ring turns slowly
/// and its colours bleed into a halo; hovering lifts the disc and brightens the halo.
private struct ScanButton: View {
    let action: () -> Void
    @State private var hovering = false
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Halo: the ring's own colours, blurred.
            StorageRing(lineWidth: 14, glow: false)
                .blur(radius: hovering ? 26 : 18)
                .opacity(hovering ? 0.75 : 0.45)
                .rotationEffect(.degrees(turning ? 360 : 0))
            StorageRing(lineWidth: 5, glow: false)
                .rotationEffect(.degrees(turning ? 360 : 0))
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .semibold)).opacity(0.85)
                    Text("Scan").font(.system(size: 32, weight: .bold))
                    Text("Macintosh HD").font(.caption.weight(.medium)).opacity(0.7)
                }
            }
            .buttonStyle(ScanDiscStyle(hovering: hovering))
            .keyboardShortcut(.defaultAction)
            .onHover { hovering = $0 }
        }
        .frame(width: 236, height: 236)
        .animation(.easeOut(duration: 0.25), value: hovering)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 48).repeatForever(autoreverses: false)) { turning = true }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ScanDiscStyle: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(.white)
            .frame(width: 184, height: 184)
            .background {
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(nsColor: NSColor(hex: 0x5a82f5)), Color(nsColor: NSColor(hex: 0x2743c0)),
                                                          Color(nsColor: NSColor(hex: 0x131a48))],
                                                 center: UnitPoint(x: 0.5, y: 0.12), startRadius: 4, endRadius: 190))
                    // Specular sheen across the top, like the icon's glass.
                    Ellipse().fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 136, height: 70)
                        .offset(y: -50)
                        .blur(radius: 1)
                    // Shade pooling at the bottom edge.
                    Circle().strokeBorder(Color.black.opacity(0.28), lineWidth: 10).blur(radius: 8).clipShape(Circle())
                    Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                                          lineWidth: 1.2)
                    Circle().fill(Color.black.opacity(pressed ? 0.14 : 0))
                }
            }
            .shadow(color: Brand.blue.opacity(hovering ? 0.55 : 0.4), radius: hovering ? 30 : 22, y: hovering ? 18 : 14)
            .scaleEffect(pressed ? 0.97 : hovering ? 1.03 : 1)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// Quiet secondary actions (first launch, Overview rows): a capsule that brightens as a whole on hover.
struct PillButtonStyle: ButtonStyle {
    /// Smaller, for buttons at the end of a list row.
    var compact = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 4 : 8)
            .background(Capsule().fill(Color.primary.opacity(pressed ? 0.18 : hovering ? 0.13 : 0.07)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(hovering ? 0.24 : 0.12)))
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - 3 · Scanning

private struct ScanningStep: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let flow: Namespace.ID
    @State private var spin = false

    var body: some View {
        let scan = store.status?.scan
        VStack(spacing: 22) {
            Text("Looking through your Mac…").font(.title2.weight(.semibold))
            ZStack {
                if let f = scan?.fraction {
                    StorageRing(progress: f, lineWidth: 10)
                    Text("\(Int(f * 100))%")
                        .font(.system(size: 44, weight: .bold))
                        .monospacedDigit()
                } else {
                    // The first scan has nothing to compare against, so there's no percentage: a light runs round
                    // the dimmed ring, taking on the colour of each segment it passes.
                    StorageRing(lineWidth: 10, glow: false).opacity(0.25)
                    StorageRing(lineWidth: 18, glow: false).blur(radius: 10).mask(comet)
                    StorageRing(lineWidth: 10, glow: false).mask(comet)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { spin = true }
                        }
                    Image(systemName: "magnifyingglass").font(.system(size: 34, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 236, height: 236)
            .matchedGeometryEffect(id: "ring", in: flow)
            Text(scan?.phase ?? "Starting…").foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: scan?.phase)
            HStack(spacing: 36) {
                stat((scan?.files ?? 0).formatted(), "files")
                stat(Fmt.size(scan?.bytes ?? 0), "measured")
            }
            Text(scan?.current ?? " ")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
            Button { Task { await store.stopScan() } } label: {
                if store.stoppingScan {
                    Label { Text("Stopping…") } icon: { ProgressView().controlSize(.mini) }
                } else {
                    Label("Stop", systemImage: "stop.fill")
                }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(store.stoppingScan)
            .keyboardShortcut(.cancelAction)
            .help("Stop scanning. Nothing is saved until a scan finishes.")
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A tail that fades in over a quarter turn to a bright head, turning with `spin`.
    private var comet: some View {
        AngularGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.7),
                                .init(color: .white.opacity(0.9), location: 0.985), .init(color: .clear, location: 1)],
                        center: .center)
            .rotationEffect(.degrees(spin ? 270 : -90))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 4 · Results

private struct ResultsStep: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let flow: Namespace.ID
    let overview: Overview
    @State private var shown = false

    private struct Find: Identifiable {
        let title: String
        let icon: String
        let size: Int64
        let detail: String
        let pane: Pane
        var id: String { title }
    }

    private var finds: [Find] {
        let w = overview.wins
        return [
            Find(title: "Device backups", icon: "iphone", size: w.backups, detail: "Local iPhone and iPad backups.", pane: .clutter),
            Find(title: "Caches", icon: "archivebox", size: w.caches, detail: "Safe to clear; apps rebuild them.", pane: .caches),
            Find(title: "Installers", icon: "externaldrive", size: w.installers, detail: "Disk images and packages you've probably installed.", pane: .clutter),
            Find(title: "Old downloads", icon: "arrow.down.circle", size: w.downloads, detail: "Downloads untouched for 3+ months.", pane: .clutter),
            Find(title: "Developer leftovers", icon: "hammer", size: w.dev, detail: "node_modules and virtualenvs.", pane: .clutter),
            Find(title: "Trash", icon: "trash", size: w.trash, detail: "Deleted files still taking space.", pane: .overview),
        ].filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    var body: some View {
        let finds = self.finds
        let total = overview.wins.total ?? finds.reduce(Int64(0)) { $0 + $1.size }
        let meaningful = total >= 500_000_000
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 22) {
                StorageRing(lineWidth: 12).frame(width: 110, height: 110)
                    .matchedGeometryEffect(id: "ring", in: flow)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Scan complete", systemImage: "checkmark").font(.callout).foregroundStyle(.secondary)
                    if meaningful {
                        (Text("You could free up ") + Text(Fmt.size(total)).foregroundColor(Brand.storage[0]))
                            .font(.system(size: 34, weight: .bold))
                    } else {
                        Text("Your Mac is in good shape").font(.system(size: 34, weight: .bold))
                    }
                    Text("\(Fmt.size(overview.disk.free)) free now. Review each group before anything is removed.")
                        .foregroundStyle(.secondary)
                }
                .arrive(shown, order: 0, still: reduceMotion)
            }
            if !finds.isEmpty {
                Grid(horizontalSpacing: 12) {
                    GridRow {
                        ForEach(Array(finds.prefix(4).enumerated()), id: \.element.id) { i, find in
                            Button { store.finishFirstLaunch(showing: find.pane) } label: { card(find) }
                                .buttonStyle(FindCardStyle())
                                .arrive(shown, order: 1 + i, still: reduceMotion)
                        }
                    }
                }
            }
            Breakdown(overview: overview)
                .arrive(shown, order: 5, still: reduceMotion)
            HStack(spacing: 10) {
                Button(meaningful ? "Review & Clean" : "Go to Overview") {
                    store.finishFirstLaunch(showing: meaningful ? finds[0].pane : .overview)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                if meaningful {
                    Button("See Full Breakdown") { store.finishFirstLaunch(showing: .overview) }
                }
            }
            .controlSize(.large)
            .padding(.top, 8)
            .arrive(shown, order: 6, still: reduceMotion)
        }
        .onAppear { shown = true }
        .padding(.horizontal, 64)
        .padding(.vertical, 44)
        .frame(maxWidth: 1000, maxHeight: .infinity, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func card(_ find: Find) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(find.title, systemImage: find.icon).font(.callout.weight(.semibold))
            Text(Fmt.size(find.size)).font(.system(size: 24, weight: .bold)).monospacedDigit()
            Text(find.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Open \(find.pane.title)")
    }
}

/// A result card is a button: the whole card answers hover and press.
private struct FindCardStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .background(Palette.card, in: shape)
            .overlay(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.08 : hovering ? 0.04 : 0)))
            .overlay(shape.strokeBorder(hovering ? Palette.accent.opacity(0.7) : Color(nsColor: .separatorColor)))
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private extension View {
    /// Fades and settles into place after the ring lands, one element after another.
    func arrive(_ shown: Bool, order: Int, still: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || still ? 0 : 14)
            .animation(Motion.settle.delay(still ? 0 : 0.28 + Double(order) * 0.06), value: shown)
    }
}

/// The disk split into the app's categories, as on the Overview.
private struct Breakdown: View {
    let overview: Overview

    var body: some View {
        let total = Double(max(overview.disk.total, 1))
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let width = max(0, geo.size.width - CGFloat(overview.breakdown.count) * 2)
                HStack(spacing: 2) {
                    ForEach(Array(overview.breakdown.enumerated()), id: \.element.id) { i, seg in
                        Capsule().fill(Palette.series[i % Palette.series.count])
                            .frame(width: max(2, width * Double(seg.size) / total))
                    }
                    Capsule().fill(Palette.track)
                }
            }
            .frame(height: 8)
            HStack(spacing: 18) {
                ForEach(Array(overview.breakdown.enumerated()), id: \.element.id) { i, seg in
                    legend(Palette.series[i % Palette.series.count], seg.label)
                }
                legend(Palette.track, "Free")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}
