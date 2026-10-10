import SwiftUI

struct OverviewView: View {
    @Environment(Store.self) private var store
    @State private var width: CGFloat = 1000

    var body: some View {
        ScrollView {
            if let o = store.overview {
                let selection = store.overviewSelection
                VStack(alignment: .leading, spacing: 22) {
                    DiskHero(overview: o)
                    if store.status?.fda == false { FullDiskAccessBanner() }
                    FreeUpSpace(wins: o.wins, selection: selection)
                    // Side by side when there's room (file paths would make ViewThatFits stack them too early).
                    if width >= 820 {
                        HStack(alignment: .top, spacing: 16) {
                            BiggestFolders(items: o.top, home: o.home, selection: selection, showsCategory: true)
                            VStack(spacing: 16) {
                                LargestFiles(items: o.large, wins: o.wins, selection: selection)
                                if !o.outside.isEmpty { OutsideHome(items: o.outside, snapshots: o.snapshots) }
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            BiggestFolders(items: o.top, home: o.home, selection: selection, showsCategory: true)
                            LargestFiles(items: o.large, wins: o.wins, selection: selection)
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
        // Escape shows the whole disk again. Only present while something is selected, so it never eats other Escapes.
        .background {
            if store.overviewSelection != nil {
                Button("Show Whole Disk") { store.overviewSelection = nil }
                    .keyboardShortcut(.escape, modifiers: [])
                    .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
            }
        }
        .onDisappear { store.overviewSelection = nil }
    }
}

// MARK: - Categories

/// The colour a breakdown category wears everywhere on the Overview. Free space is never a hue.
private func categoryTint(_ key: String) -> Tint {
    switch key {
    case "apps": return Tint.categories[0]
    case "files": return Tint.categories[1]
    case "appdata": return Tint.categories[2]
    case "system": return Tint.categories[3]
    default: return .gray
    }
}

// MARK: - Hero: the cross-section, what you could free, and the breakdown

/// Things worth cleaning, in the order the Overview and the first-launch results list them.
struct Find: Identifiable {
    /// How much to trust clearing it, shown by how its bar is filled.
    enum State {
        case safe    // solid: safe to clear
        case review  // hatched: review first
        case asks    // dashed outline: asks before deleting

        var label: String {
            switch self {
            case .safe: return "Safe to clear"
            case .review: return "Review first"
            case .asks: return "Asks before deleting"
            }
        }
    }

    let title: String
    let symbol: String
    let tint: Tint
    let size: Int64
    let detail: String
    /// How the hero sums it up when this is the biggest find ("Most of it is …").
    let gist: String
    let button: String
    /// The breakdown category it lives in, following engine.py: Library and hidden folders (caches, device backups, the
    /// Trash) are "appdata"; installers, old downloads and developer leftovers are "files".
    let category: String
    let state: State
    /// Its bar stays grey instead of wearing the category hue (the Trash asks first, so it is never a "clear it" colour).
    var neutral = false
    let action: () -> Void
    var id: String { title }

    @MainActor
    static func all(_ w: Wins, store: Store) -> [Find] {
        [
            Find(title: "Caches", symbol: "archivebox.fill", tint: .green, size: w.caches,
                 detail: "Safe to clear. Apps rebuild them as needed.", gist: "caches that apps rebuild on their own",
                 button: "Review", category: "appdata", state: .safe) { store.pane = .caches },
            Find(title: "Device backups", symbol: "iphone", tint: .purple, size: w.backups,
                 detail: "Local iPhone and iPad backups.", gist: "old iPhone and iPad backups",
                 button: "Review", category: "appdata", state: .review) { store.pane = .clutter },
            Find(title: "Installers", symbol: "shippingbox.fill", tint: .teal, size: w.installers,
                 detail: "Disk images and packages you've probably already installed.", gist: "installers you've already used",
                 button: "Review", category: "files", state: .review) { store.pane = .clutter },
            Find(title: "Developer leftovers", symbol: "hammer.fill", tint: .orange, size: w.dev,
                 detail: "node_modules and virtualenvs you can reinstall.", gist: "developer dependencies you can reinstall",
                 button: "Review", category: "files", state: .review) { store.pane = .clutter },
            Find(title: "Old downloads", symbol: "arrow.down", tint: .blue, size: w.downloads,
                 detail: "Downloads you haven't touched in 3+ months.", gist: "downloads you haven't touched in months",
                 button: "Review", category: "files", state: .review) { store.pane = .clutter },
            Find(title: "Trash", symbol: "trash.fill", tint: .pink, size: w.trash,
                 detail: "Deleted files still take space until you empty the Trash.", gist: "already in the Trash",
                 button: "Empty Trash…", category: "appdata", state: .asks, neutral: true) { store.askEmptyTrash() },
        ]
    }
}

private let diskName = "Macintosh HD"

private struct DiskHero: View {
    @Environment(Store.self) private var store
    let overview: Overview

    var body: some View {
        let all = Find.all(overview.wins, store: store)
        let finds = all.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        let total = overview.wins.total ?? finds.reduce(Int64(0)) { $0 + $1.size }
        let meaningful = total >= 500_000_000 && !finds.isEmpty
        let model = FigureModel(overview)
        let figure = CrossSectionFigure(model: model, diskName: diskName,
                                        selection: Binding(get: { store.overviewSelection }, set: { store.overviewSelection = $0 }))
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 30) {
                figure
                column(model: model, finds: finds, total: total, meaningful: meaningful)
                    .frame(minWidth: 420, idealWidth: 460, maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .center, spacing: 18) {
                figure
                column(model: model, finds: finds, total: total, meaningful: meaningful)
            }
        }
    }

    private func column(model: FigureModel, finds: [Find], total: Int64, meaningful: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            headline(finds: finds, total: total, meaningful: meaningful)
            legend(model: model)
            caption(model: model, finds: all)
        }
    }

    private var all: [Find] { Find.all(overview.wins, store: store) }

    private func headline(finds: [Find], total: Int64, meaningful: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if meaningful {
                (Text("You could free up ") + Text(Fmt.size(total)).foregroundColor(Palette.freeable))
                    .font(.system(size: 28, weight: .bold))
                Text("Most of it is \(finds[0].gist).")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Review & Clean", action: finds[0].action)
                    .buttonStyle(GlossyButtonStyle(large: true))
                    .padding(.top, 6)
            } else {
                Text("Your Mac is in good shape").font(.system(size: 28, weight: .bold))
                Text("Nothing big to clean up right now. \(Fmt.size(overview.disk.free)) is free.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func legend(model: FigureModel) -> some View {
        VStack(spacing: 1) {
            ForEach(model.cats) { cat in
                LegendRow(cat: cat, selected: store.overviewSelection == cat.key) {
                    store.overviewSelection = store.overviewSelection == cat.key ? nil : cat.key
                }
            }
        }
        .padding(6)
        .background(Palette.glass, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.glassEdge))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Disk breakdown")
    }

    /// One plain sentence about what is focused, with the way out (and the way in) beside it.
    private func caption(model: FigureModel, finds: [Find]) -> some View {
        let key = store.overviewSelection
        let (lead, rest) = captionText(key: key, model: model, finds: finds)
        return HStack(alignment: .top, spacing: 14) {
            (Text(lead).fontWeight(.semibold).foregroundColor(.primary) + Text(rest))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if key != nil {
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Show Whole Disk") { store.overviewSelection = nil }
                        .buttonStyle(PillButtonStyle(compact: true))
                    if let open = destination(key) {
                        Button(open.title, action: open.action).buttonStyle(.link).font(.caption)
                    }
                }
            }
        }
        .frame(minHeight: 36, alignment: .top)
    }

    /// Where a category leads. macOS & other and free space have nowhere to go.
    private func destination(_ key: String?) -> (title: String, action: () -> Void)? {
        switch key {
        case "apps": return ("Open Applications", { store.pane = .apps })
        case "files": return ("Open Home in Explorer", { store.explore(store.home) })
        case "appdata": return ("Open Library in Explorer", { store.explore(store.home + "/Library") })
        default: return nil
        }
    }

    private func captionText(key: String?, model: FigureModel, finds: [Find]) -> (String, String) {
        guard let key, let cat = model.cat(key) else {
            return ("\(diskName), \(Fmt.size(overview.disk.total)).",
                    " Inner ring: categories. Outer ring: biggest folders in your home. Bars: largest files.")
        }
        let lead = "\(cat.label), \(Fmt.size(cat.size))."
        switch key {
        case "apps":
            return (lead, " Open Applications to see when you last used each app and uninstall the ones you don't.")
        case "system":
            return (lead, " macOS itself, snapshots and shared tools. Managed by macOS, so MacSafe only shows them.")
        case "free":
            let total = overview.wins.total ?? 0
            return (lead, total > 0 ? " Clearing everything found would bring it to \(Fmt.size(overview.disk.free + total))." : " Available space.")
        default:
            var parts: [String] = []
            let folders = model.folders.filter { $0.cat == key }.prefix(3).map { "\($0.name) \(Fmt.size($0.size))" }
            var text = folders.isEmpty ? "" : " " + folders.joined(separator: ", ") + "."
            let here = finds.filter { $0.category == key && $0.size > 0 }
            let safe = here.filter { $0.state == .safe }.reduce(Int64(0)) { $0 + $1.size }
            let review = here.filter { $0.state == .review }.reduce(Int64(0)) { $0 + $1.size }
            let asks = here.filter { $0.state == .asks }.reduce(Int64(0)) { $0 + $1.size }
            if safe > 0 { parts.append("\(Fmt.size(safe)) is safe to clear") }
            if review > 0 { parts.append("\(Fmt.size(review)) to review first") }
            if asks > 0 { parts.append("\(Fmt.size(asks)) is in the Trash") }
            if !parts.isEmpty { text += " " + parts.joined(separator: "; ") + "." }
            return (lead, text)
        }
    }
}

/// A row of the breakdown: dot, label, value with a smaller unit, share. A button, so it is reachable by keyboard
/// and VoiceOver; choosing it focuses that category on the figure.
private struct LegendRow: View {
    let cat: FigureModel.Cat
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    private static let what: [String: String] = [
        "apps": "Your Applications folder", "files": "Documents and downloads",
        "appdata": "Library, hidden folders", "system": "Managed by macOS", "free": "Available space",
    ]

    var body: some View {
        let parts = Fmt.parts(cat.size)
        let share = cat.share.formatted(.percent.precision(.fractionLength(0)))
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                row(parts: parts, share: share, showsWhat: true)
                row(parts: parts, share: share, showsWhat: false)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.09 : hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cat.label), \(Fmt.size(cat.size)), \(share)")
        .accessibilityHint(selected ? "Selected. Press to show the whole disk." : "Focus this category.")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(cat.key == "system" ? "macOS itself, snapshots and shared tools. Managed by macOS, so MacSafe only shows them." : "")
    }

    private func row(parts: (num: String, unit: String), share: String, showsWhat: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cat.tint?.gradient ?? Tint.gray.gradient)
                .frame(width: 9, height: 9)
                .frame(width: 16)
            Text(cat.label).lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                Text(parts.num).fontWeight(.medium).monospacedDigit()
                Text(parts.unit).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
            }
            Text(share).monospacedDigit().foregroundStyle(.tertiary).frame(width: 40, alignment: .trailing)
            if showsWhat {
                Text(Self.what[cat.key] ?? "")
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    .frame(width: 150, alignment: .leading).padding(.leading, 8)
            }
        }
        .font(.callout)
    }
}

// MARK: - Free up space

private struct FreeUpSpace: View {
    @Environment(Store.self) private var store
    let wins: Wins
    let selection: String?

    var body: some View {
        let all = Find.all(wins, store: store)
        let found = all.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        let finds = found.filter { selection == nil || $0.category == selection }
        let clear = all.filter { $0.size == 0 }.map(\.title)
        let top = Double(max(found.first?.size ?? 1, 1))
        let total = selection == nil ? (wins.total ?? finds.reduce(Int64(0)) { $0 + $1.size })
                                     : finds.reduce(Int64(0)) { $0 + $1.size }
        Card(title: "Free up space",
             trailing: finds.isEmpty ? nil : "\(Fmt.size(total)) in \(Fmt.count(finds.count, "place"))",
             titleAccessory: selection.map { AnyView(FilterToken(key: $0)) }) {
            VStack(spacing: 0) {
                ForEach(Array(finds.enumerated()), id: \.element.id) { i, find in
                    if i > 0 { Divider().padding(.leading, 44) }
                    FindRow(find: find, fraction: Double(find.size) / top)
                }
            }
            if let selection, finds.isEmpty {
                Text(Self.empty(selection)).font(.callout).foregroundStyle(.secondary)
            } else if selection == nil, !clear.isEmpty {
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

    private static func empty(_ key: String) -> String {
        switch key {
        case "apps": return "Nothing to clear here. Open Applications to uninstall apps you don't use."
        case "system": return "Nothing to clear here. macOS manages this space itself."
        case "free": return "Free space has nothing to clear. Everything above adds to it."
        default: return "Nothing to clear here."
        }
    }
}

/// Says which category the lists are filtered to, and undoes it.
private struct FilterToken: View {
    @Environment(Store.self) private var store
    let key: String

    var body: some View {
        HStack(spacing: 8) {
            Text(store.overview?.breakdown.first { $0.key == key }?.label ?? "Free")
                .font(.caption).padding(.horizontal, 8).padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: Capsule())
            Button("Show All") { store.overviewSelection = nil }.buttonStyle(.link).font(.caption)
        }
        .accessibilityElement(children: .combine)
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
            StateBar(fraction: fraction, tint: find.neutral ? .gray : categoryTint(find.category), state: find.state).frame(width: 170)
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

/// A size bar in its category's hue. How much to trust clearing it is in the fill: solid = safe to clear,
/// hatched = review first, dashed outline = asks before deleting.
private struct StateBar: View {
    let fraction: Double
    let tint: Tint
    let state: Find.State

    var body: some View {
        Canvas { ctx, size in
            let w = max(8, size.width * min(1, max(0, fraction)))
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 2, width: size.width, height: 6), cornerRadius: 3), with: .color(Palette.track))
            switch state {
            case .safe:
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: 2, width: w, height: 6), cornerRadius: 3),
                         with: .linearGradient(Gradient(colors: [tint.bottom, tint.top]),
                                               startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
            case .review:
                let r = Path(roundedRect: CGRect(x: 0.5, y: 1, width: w - 1, height: 8), cornerRadius: 3)
                ctx.fill(r, with: .color(tint.top.opacity(0.22)))
                var inside = ctx
                inside.clip(to: r)
                var hatch = Path()
                var x = -10.0
                while x < w + 10 {
                    hatch.move(to: CGPoint(x: x, y: 10))
                    hatch.addLine(to: CGPoint(x: x + 10, y: 0))
                    x += 5.66
                }
                inside.stroke(hatch, with: .color(tint.top), lineWidth: 1.6)
                ctx.stroke(r, with: .color(tint.top), lineWidth: 1)
            case .asks:
                ctx.stroke(Path(roundedRect: CGRect(x: 0.6, y: 1.1, width: w - 1.2, height: 7.8), cornerRadius: 3),
                           with: .color(tint.top), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.4]))
            }
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.label)
        .help(state.label)
    }
}

// MARK: - Folders and files

/// What a sortable table is sorted by.
private enum SortKey { case name, size }

private func sorted(_ items: [Item], by key: SortKey, ascending: Bool) -> [Item] {
    items.sorted { a, b in
        switch key {
        case .size: return ascending ? a.size < b.size : a.size > b.size
        case .name:
            // Hidden folders sort by the name after the dot, as Finder does.
            let x = a.name.hasPrefix(".") ? String(a.name.dropFirst()) : a.name
            let y = b.name.hasPrefix(".") ? String(b.name.dropFirst()) : b.name
            let order = x.localizedStandardCompare(y)
            return order == .orderedSame ? a.size > b.size : (ascending ? order == .orderedAscending : order == .orderedDescending)
        }
    }
}

/// A table column header: a button with a sort chevron, announced with its sort state.
private struct SortHeader: View {
    let title: String
    let key: SortKey
    @Binding var sortKey: SortKey
    @Binding var ascending: Bool
    var trailing = false

    var body: some View {
        let active = sortKey == key
        Button {
            if active { ascending.toggle() } else { sortKey = key; ascending = key == .name }
        } label: {
            HStack(spacing: 4) {
                if trailing { Spacer(minLength: 0) }
                Text(title)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(active && ascending ? 180 : 0))
                    .opacity(active ? 1 : 0)
                if !trailing { Spacer(minLength: 0) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .foregroundStyle(active ? Color.primary : Color.secondary)
        .accessibilityLabel(title)
        .accessibilityValue(active ? (ascending ? "Sorted ascending" : "Sorted descending") : "Not sorted")
        .accessibilityHint("Sorts by \(title.lowercased())")
    }
}

private struct BiggestFolders: View {
    @Environment(Store.self) private var store
    let items: [Item]
    let home: Int64
    let selection: String?
    /// The Category column only helps on the whole disk.
    let showsCategory: Bool
    @State private var sortKey = SortKey.size
    @State private var ascending = false

    var body: some View {
        // Library and hidden folders are app data; every other home folder is your files (engine.py, item()).
        let filtered = items.filter { item in
            switch selection {
            case nil: return true
            case "appdata": return item.appdata == true
            case "files": return item.appdata != true
            default: return false
            }
        }
        let shown = sorted(filtered, by: sortKey, ascending: ascending)
        let sum = shown.reduce(Int64(0)) { $0 + $1.size }
        let category = showsCategory && selection == nil
        Card(title: "Biggest folders in your home",
             subtitle: selection == nil ? "\(Fmt.size(home)) in total" : (shown.isEmpty ? nil : "\(Fmt.size(sum)) shown")) {
            if shown.isEmpty {
                Text(selection == "system" ? "macOS & other sits outside your home. MacSafe only shows it."
                     : selection == "apps" ? "Apps live in /Applications, outside your home folders."
                     : "No folders here.")
                    .foregroundStyle(.secondary)
            } else {
                let top = Double(max(items.map(\.size).max() ?? 1, 1))
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        SortHeader(title: "Name", key: .name, sortKey: $sortKey, ascending: $ascending)
                            .padding(.leading, 24)
                        if category {
                            Text("Category").frame(width: 76, alignment: .leading)
                        }
                        SortHeader(title: "Size", key: .size, sortKey: $sortKey, ascending: $ascending, trailing: true)
                            .frame(width: 130)
                        Color.clear.frame(width: 12, height: 1)
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .padding(.bottom, 6)
                    .overlay(alignment: .bottom) { Divider() }
                    ForEach(shown) { item in
                        FolderRow(item: item, fraction: Double(item.size) / top,
                                  tint: categoryTint(item.appdata == true ? "appdata" : "files"),
                                  showsCategory: category)
                    }
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
    let showsCategory: Bool
    @State private var hovering = false

    var body: some View {
        Button { store.explore(item.path) } label: {
            HStack(spacing: 12) {
                FileIcon(path: item.path, size: 20)
                Text(item.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                if showsCategory {
                    Text(item.appdata == true ? "App data" : "Your files")
                        .foregroundStyle(.secondary).lineLimit(1).frame(width: 76, alignment: .leading)
                }
                HStack(spacing: 10) {
                    SizeBar(fraction: fraction, tint: tint).frame(width: 48)
                    Text(Fmt.size(item.size)).monospacedDigit().frame(width: 72, alignment: .trailing)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .opacity(hovering ? 1 : 0)
                    .frame(width: 12)
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
    let wins: Wins
    let selection: String?
    @State private var sortKey = SortKey.size
    @State private var ascending = false

    var body: some View {
        // large() leaves out Library and hidden folders (engine.py), so every file listed is "Your files".
        let shown = sorted(selection == nil || selection == "files" ? items : [], by: sortKey, ascending: ascending)
        Card(title: "Largest files", subtitle: "200 MB and up, outside app data") {
            if shown.isEmpty {
                Text(emptyText).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        SortHeader(title: "Name", key: .name, sortKey: $sortKey, ascending: $ascending)
                            .padding(.leading, 36)
                        SortHeader(title: "Size", key: .size, sortKey: $sortKey, ascending: $ascending, trailing: true)
                            .frame(width: 90)
                        Color.clear.frame(width: 50, height: 1).accessibilityHidden(true)
                    }
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) { Divider() }
                    ForEach(shown) { item in
                        HStack(spacing: 10) {
                            FileIcon(path: item.path, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).lineLimit(1).truncationMode(.middle)
                                Text(item.loc ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(Fmt.size(item.size)).monospacedDigit().frame(width: 90, alignment: .trailing)
                            RowActions(item: item, actions: [.reveal, .trash]).frame(width: 50, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                        .contextMenu { ItemMenu(items: [item]) }
                    }
                }
            }
        } accessory: {
            Button("See All") { store.pane = .large }.buttonStyle(.link)
        }
    }

    private var emptyText: String {
        guard let selection else { return "No files over 200 MB in your folders." }
        if selection == "appdata" {
            let biggest = Find.all(wins, store: store).filter { $0.category == "appdata" && $0.size > 0 }.max { $0.size < $1.size }
            return "Largest files leaves out app data." + (biggest.map { " Its biggest find is \(Fmt.size($0.size)) in \($0.title.lowercased())." } ?? "")
        }
        return "No files of 200 MB or more here."
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
