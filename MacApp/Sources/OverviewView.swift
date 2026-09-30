import SwiftUI

struct OverviewView: View {
    @Environment(Store.self) private var store
    @State private var width: CGFloat = 1000

    var body: some View {
        ScrollView {
            if let o = store.overview {
                VStack(alignment: .leading, spacing: 22) {
                    DiskHero(overview: o)
                    if store.status?.fda == false { FullDiskAccessBanner() }
                    FreeUpSpace(wins: o.wins)
                    // Side by side when there's room (file paths would make ViewThatFits stack them too early).
                    if width >= 820 {
                        HStack(alignment: .top, spacing: 16) {
                            BiggestFolders(items: o.top, home: o.home)
                            VStack(spacing: 16) {
                                LargestFiles(items: o.large)
                                if !o.outside.isEmpty { OutsideHome(items: o.outside, snapshots: o.snapshots) }
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            BiggestFolders(items: o.top, home: o.home)
                            LargestFiles(items: o.large)
                            if !o.outside.isEmpty { OutsideHome(items: o.outside, snapshots: o.snapshots) }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 1200, alignment: .leading)
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { width = geo.size.width - 64 }
                        .onChange(of: geo.size.width) { _, new in width = new - 64 }
                })
                .frame(maxWidth: .infinity)
            } else {
                ProgressView().padding(60)
            }
        }
        .navigationTitle("Overview")
        .task(id: store.dataVersion) { await store.loadOverview() }
    }
}

// MARK: - Hero: the ring, what you could free, and the breakdown

/// Things worth cleaning, in the order the Overview and the first-launch results list them.
struct Find: Identifiable {
    let title: String
    let symbol: String
    let tint: Tint
    let size: Int64
    let detail: String
    /// How the hero sums it up when this is the biggest find ("Most of it is …").
    let gist: String
    let button: String
    let action: () -> Void
    var id: String { title }

    @MainActor
    static func all(_ w: Wins, store: Store) -> [Find] {
        [
            Find(title: "Caches", symbol: "archivebox.fill", tint: .green, size: w.caches,
                 detail: "Safe to clear. Apps rebuild them as needed.", gist: "caches that apps rebuild on their own",
                 button: "Review") { store.pane = .caches },
            Find(title: "Device backups", symbol: "iphone", tint: .purple, size: w.backups,
                 detail: "Local iPhone and iPad backups.", gist: "old iPhone and iPad backups",
                 button: "Review") { store.pane = .clutter },
            Find(title: "Installers", symbol: "shippingbox.fill", tint: .teal, size: w.installers,
                 detail: "Disk images and packages you've probably already installed.", gist: "installers you've already used",
                 button: "Review") { store.pane = .clutter },
            Find(title: "Developer leftovers", symbol: "hammer.fill", tint: .orange, size: w.dev,
                 detail: "node_modules and virtualenvs you can reinstall.", gist: "developer dependencies you can reinstall",
                 button: "Review") { store.pane = .clutter },
            Find(title: "Old downloads", symbol: "arrow.down", tint: .blue, size: w.downloads,
                 detail: "Downloads you haven't touched in 3+ months.", gist: "downloads you haven't touched in months",
                 button: "Review") { store.pane = .clutter },
            Find(title: "Trash", symbol: "trash.fill", tint: .pink, size: w.trash,
                 detail: "Deleted files still take space until you empty the Trash.", gist: "already in the Trash",
                 button: "Empty Trash…") { store.askEmptyTrash() },
        ]
    }
}

private struct DiskHero: View {
    @Environment(Store.self) private var store
    let overview: Overview
    @State private var hovered: String?

    var body: some View {
        let finds = Find.all(overview.wins, store: store).filter { $0.size > 0 }.sorted { $0.size > $1.size }
        let total = overview.wins.total ?? finds.reduce(Int64(0)) { $0 + $1.size }
        let meaningful = total >= 500_000_000 && !finds.isEmpty
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 36) {
                ring
                // An ideal width, so the headline wraps instead of pushing the legend below.
                headline(finds: finds, total: total, meaningful: meaningful)
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: .infinity, alignment: .leading)
                legend.frame(width: 322)
            }
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 28) {
                    ring
                    headline(finds: finds, total: total, meaningful: meaningful)
                }
                legend
            }
        }
    }

    private var ring: some View {
        BreakdownRing(overview: overview, hovered: hovered)
            .frame(width: 188, height: 188)
            .background {
                Circle()
                    .fill(RadialGradient(colors: [Brand.blue.opacity(0.35), Color.purple.opacity(0.12), .clear],
                                         center: .center, startRadius: 40, endRadius: 130))
                    .frame(width: 260, height: 260)
                    .accessibilityHidden(true)
            }
    }

    private func headline(finds: [Find], total: Int64, meaningful: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if meaningful {
                (Text("You could free up ") + Text(Fmt.size(total)).foregroundColor(Palette.freeable))
                    .font(.system(size: 32, weight: .bold))
                Text("Most of it is \(finds[0].gist).")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Review & Clean", action: finds[0].action)
                    .buttonStyle(GlossyButtonStyle(large: true))
                    .padding(.top, 6)
            } else {
                Text("Your Mac is in good shape").font(.system(size: 32, weight: .bold))
                Text("Nothing big to clean up right now. \(Fmt.size(overview.disk.free)) is free.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var legend: some View {
        let total = Double(max(overview.disk.total, 1))
        return VStack(spacing: 1) {
            ForEach(Array(overview.breakdown.enumerated()), id: \.element.id) { i, seg in
                LegendRow(color: Palette.series[i % Palette.series.count], label: seg.label, size: seg.size,
                          share: Double(seg.size) / total, destination: destination(seg.key), hovered: $hovered, key: seg.key)
            }
            LegendRow(color: Color.primary.opacity(0.2), label: "Free", size: overview.disk.free,
                      share: Double(overview.disk.free) / total, destination: nil, hovered: $hovered, key: "free")
        }
        .padding(6)
        .background(Palette.glass, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.glassEdge))
    }

    /// Where clicking a category goes. macOS & other and free space have nowhere to go.
    private func destination(_ key: String) -> (() -> Void)? {
        switch key {
        case "apps": return { store.pane = .apps }
        case "files": return { store.explore(store.home) }
        case "appdata": return { store.explore(store.home + "/Library") }
        default: return nil
        }
    }
}

private struct LegendRow: View {
    let color: Color
    let label: String
    let size: Int64
    let share: Double
    let destination: (() -> Void)?
    @Binding var hovered: String?
    let key: String

    var body: some View {
        let lit = hovered == key
        let row = HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.6), radius: 4, y: 1)
            Text(label).lineLimit(1)
            Spacer(minLength: 8)
            Text(Fmt.size(size)).monospacedDigit()
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit().font(.caption).foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            Image(systemName: destination == nil ? "info.circle" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .opacity(lit || destination == nil && key != "free" ? 1 : 0)
                .frame(width: 12)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(lit ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? key : (hovered == key ? nil : hovered) }
        .animation(.easeOut(duration: 0.12), value: lit)

        if let destination {
            Button(action: destination) { row }
                .buttonStyle(.plain)
                .help(key == "apps" ? "Open Applications" : "Open in Explorer")
        } else if key == "system" {
            row.help("macOS itself, snapshots and shared tools. Managed by macOS, so MacSafe only shows them.")
        } else {
            row
        }
    }
}

/// The disk as a ring: one arc per category, free space as the empty track. Hovering a legend row lights
/// its arc and dims the rest. The arcs draw in once when the Overview first appears.
private struct BreakdownRing: View {
    let overview: Overview
    let hovered: String?
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let lineWidth: CGFloat = 13

    var body: some View {
        let total = Double(max(overview.disk.total, 1))
        let progress = drawn || reduceMotion ? 1.0 : 0.0
        let arcs = spans(total: total)
        ZStack {
            Circle().stroke(Palette.track, lineWidth: lineWidth)
            ForEach(arcs, id: \.key) { arc in
                Circle().trim(from: arc.from * progress, to: max(arc.from, arc.to) * progress)
                    .stroke(Palette.series[arc.index % Palette.series.count], style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .opacity(hovered == nil || hovered == arc.key || hovered == "free" ? 1 : 0.3)
            }
            VStack(spacing: 1) {
                Text(Fmt.size(overview.disk.free))
                    .font(.system(size: 26, weight: .bold)).monospacedDigit()
                    .contentTransition(.numericText())
                Text("free of \(Fmt.size(overview.disk.total))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(lineWidth / 2)
        .shadow(color: Brand.blue.opacity(0.35), radius: 16)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .onAppear {
            guard !drawn else { return }
            withAnimation(reduceMotion ? nil : Motion.settle.speed(0.6)) { drawn = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Fmt.size(overview.disk.free)) free of \(Fmt.size(overview.disk.total))")
    }

    private struct Arc { let key: String; let index: Int; let from: Double; let to: Double }

    private func spans(total: Double) -> [Arc] {
        var start = 0.0
        return overview.breakdown.enumerated().map { i, seg in
            let share = Double(seg.size) / total
            defer { start += share }
            let gap = share > 0.012 ? 0.003 : 0
            return Arc(key: seg.key, index: i, from: start + gap, to: start + share - gap)
        }
    }
}

// MARK: - Free up space

private struct FreeUpSpace: View {
    @Environment(Store.self) private var store
    let wins: Wins

    var body: some View {
        let all = Find.all(wins, store: store)
        let finds = all.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        let clear = all.filter { $0.size == 0 }.map(\.title)
        let top = Double(max(finds.first?.size ?? 1, 1))
        let total = wins.total ?? finds.reduce(Int64(0)) { $0 + $1.size }
        Card(title: "Free up space",
             trailing: finds.isEmpty ? nil : "\(Fmt.size(total)) in \(Fmt.count(finds.count, "place"))") {
            VStack(spacing: 0) {
                ForEach(Array(finds.enumerated()), id: \.element.id) { i, find in
                    if i > 0 { Divider().padding(.leading, 44) }
                    FindRow(find: find, fraction: Double(find.size) / top)
                }
            }
            if !clear.isEmpty {
                Label {
                    Text(finds.isEmpty ? "Nothing to clean up right now." : "Nothing to remove in \(ListFormatter.localizedString(byJoining: clear.map { $0.lowercased() })).")
                } icon: {
                    Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(Palette.freeable)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FindRow: View {
    let find: Find
    let fraction: Double
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            ColorTile(tint: find.tint, symbol: find.symbol, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(find.title).fontWeight(.medium)
                Text(find.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SizeBar(fraction: fraction, tint: find.tint).frame(width: 170)
            Text(Fmt.size(find.size)).fontWeight(.semibold).monospacedDigit()
                .frame(width: 76, alignment: .trailing)
            Button(find.button, action: find.action)
                .buttonStyle(PillButtonStyle(compact: true))
                .frame(width: 112, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(hovering ? 0.04 : 0)))
        .padding(.horizontal, -8)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Folders and files

private struct BiggestFolders: View {
    @Environment(Store.self) private var store
    let items: [Item]
    let home: Int64

    var body: some View {
        Card(title: "Biggest folders in your home", subtitle: "\(Fmt.size(home)) in total") {
            let top = Double(max(items.first?.size ?? 1, 1))
            VStack(spacing: 0) {
                ForEach(items) { item in
                    FolderRow(item: item, fraction: Double(item.size) / top,
                              tint: item.path == store.home + "/Library" || item.name.hasPrefix(".") ? .green : .orange)
                }
            }
        }
    }
}

/// A folder in the home breakdown: the whole row opens it in Explorer. App data (Library and hidden
/// folders) is green, your own files orange, as in the breakdown.
private struct FolderRow: View {
    @Environment(Store.self) private var store
    let item: Item
    let fraction: Double
    let tint: Tint
    @State private var hovering = false

    var body: some View {
        Button { store.explore(item.path) } label: {
            HStack(spacing: 12) {
                FileIcon(path: item.path, size: 20)
                Text(item.name).lineLimit(1).frame(width: 130, alignment: .leading)
                SizeBar(fraction: fraction, tint: tint)
                Text(Fmt.size(item.size)).monospacedDigit().frame(width: 72, alignment: .trailing)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Open \(item.name) in Explorer")
        .contextMenu { ItemMenu(items: [item], allowDelete: false) }
    }
}

private struct LargestFiles: View {
    @Environment(Store.self) private var store
    let items: [Item]

    var body: some View {
        Card(title: "Largest files", subtitle: "200 MB and up, outside app data") {
            if items.isEmpty {
                Text("No files over 200 MB in your folders.").foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        FileIcon(path: item.path, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Text(item.loc ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Text(Fmt.size(item.size)).monospacedDigit()
                        RowActions(item: item, actions: [.reveal, .trash])
                    }
                    .padding(.vertical, 2)
                    .contextMenu { ItemMenu(items: [item]) }
                }
            }
        } accessory: {
            Button("See All") { store.pane = .large }.buttonStyle(.link)
        }
    }
}

private struct OutsideHome: View {
    @Environment(Store.self) private var store
    let items: [Outside]
    let snapshots: Int

    var body: some View {
        Card(title: "Outside your home", subtitle: "Part of macOS & other. Managed by macOS or other tools, so MacSafe only shows them.") {
            VStack(spacing: 10) {
                ForEach(items) { x in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(x.name)
                            Text(x.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Text(Fmt.size(x.size)).monospacedDigit()
                        Button { store.reveal(path: x.path) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless).help("Show in Finder")
                    }
                }
                if snapshots > 0 {
                    Text("\(Fmt.count(snapshots, "local Time Machine snapshot")). macOS removes them automatically when it needs space.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
