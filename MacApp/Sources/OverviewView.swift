import SwiftUI

struct OverviewView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ScrollView {
            if let o = store.overview {
                VStack(alignment: .leading, spacing: 20) {
                    DiskHeader(overview: o)
                    if store.status?.fda == false { FullDiskAccessBanner() }
                    QuickWins(wins: o.wins)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            BiggestFolders(items: o.top, home: o.home)
                            LargestFiles(items: o.large)
                        }
                        .frame(minWidth: 820)
                        VStack(spacing: 16) {
                            BiggestFolders(items: o.top, home: o.home)
                            LargestFiles(items: o.large)
                        }
                    }
                    if !o.outside.isEmpty { OutsideHome(items: o.outside, snapshots: o.snapshots) }
                }
                .padding(24)
                .frame(maxWidth: 1200, alignment: .leading)
                .frame(maxWidth: .infinity)
            } else {
                ProgressView().padding(60)
            }
        }
        .navigationTitle("Overview")
        .task(id: store.dataVersion) { await store.loadOverview() }
    }
}

private struct DiskHeader: View {
    let overview: Overview
    @State private var hovered: String?

    var body: some View {
        let disk = overview.disk
        let total = Double(max(disk.total, 1))
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Fmt.size(disk.free)).font(.system(size: 38, weight: .semibold)).monospacedDigit()
                Text("available").font(.title3).foregroundStyle(.secondary)
                Spacer()
                Text("\(Fmt.size(disk.used)) of \(Fmt.size(disk.total)) used").foregroundStyle(.secondary)
            }
            // Stacked bar: 2px gaps between segments, free space as a neutral track.
            GeometryReader { geo in
                let gaps = CGFloat(overview.breakdown.count) * 2
                let width = max(0, geo.size.width - gaps)
                HStack(spacing: 2) {
                    ForEach(Array(overview.breakdown.enumerated()), id: \.element.id) { i, seg in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Palette.series[i % Palette.series.count])
                            .opacity(hovered == nil || hovered == seg.key ? 1 : 0.35)
                            .frame(width: max(2, width * CGFloat(Double(seg.size) / total)))
                            .onHover { hovered = $0 ? seg.key : nil }
                            .help("\(seg.label): \(Fmt.size(seg.size)) (\(percent(seg.size, total)))")
                    }
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Palette.track)
                        .help("Free: \(Fmt.size(disk.free))")
                }
            }
            .frame(height: 24)
            .animation(.easeOut(duration: 0.15), value: hovered)
            // Legend doubles as the value table.
            HStack(spacing: 18) {
                ForEach(Array(overview.breakdown.enumerated()), id: \.element.id) { i, seg in
                    legend(color: Palette.series[i % Palette.series.count], label: seg.label, size: seg.size, key: seg.key)
                }
                legend(color: Palette.track, label: "Free", size: disk.free, key: "free")
            }
            .font(.callout)
        }
    }

    private func legend(color: Color, label: String, size: Int64, key: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
            Text(Fmt.size(size)).monospacedDigit().foregroundStyle(.secondary)
        }
        .onHover { hovered = $0 && key != "free" ? key : nil }
    }

    private func percent(_ v: Int64, _ total: Double) -> String {
        (Double(v) / total).formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct QuickWins: View {
    @Environment(Store.self) private var store
    let wins: Wins

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick wins").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                WinCard(icon: "trash", title: "Trash", size: wins.trash,
                        detail: "Deleted files still take space until you empty the Trash.",
                        button: "Empty Trash…", enabled: wins.trash > 0) { store.askEmptyTrash() }
                WinCard(icon: "archivebox", title: "Caches", size: wins.caches,
                        detail: "Safe to clear; apps rebuild them as needed.",
                        button: "Review Caches") { store.pane = .caches }
                if wins.downloads > 0 {
                    WinCard(icon: "arrow.down.circle", title: "Old downloads", size: wins.downloads,
                            detail: "Downloads you haven't touched in 3+ months.", button: "Review") { store.pane = .clutter }
                }
                if wins.installers > 0 {
                    WinCard(icon: "externaldrive", title: "Installers", size: wins.installers,
                            detail: "Disk images and packages you've probably already installed.", button: "Review") { store.pane = .clutter }
                }
                if wins.dev > 0 {
                    WinCard(icon: "hammer", title: "Developer leftovers", size: wins.dev,
                            detail: "node_modules and virtualenvs; reinstall them any time.", button: "Review") { store.pane = .clutter }
                }
                if wins.backups > 0 {
                    WinCard(icon: "iphone", title: "Device backups", size: wins.backups,
                            detail: "Local iPhone and iPad backups.", button: "Review") { store.pane = .clutter }
                }
            }
        }
    }
}

private struct WinCard: View {
    let icon: String
    let title: String
    let size: Int64
    let detail: String
    let button: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(Palette.accent)
                Text(title).fontWeight(.medium)
                Spacer()
            }
            Text(Fmt.size(size)).font(.title2.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(button, action: action).controlSize(.small).disabled(!enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

private struct BiggestFolders: View {
    @Environment(Store.self) private var store
    let items: [Item]
    let home: Int64

    var body: some View {
        Card(title: "Biggest folders in your home", subtitle: "\(Fmt.size(home)) in total · click to explore") {
            let top = Double(max(items.first?.size ?? 1, 1))
            VStack(spacing: 2) {
                ForEach(items) { item in
                    Button { store.explore(item.path) } label: {
                        HStack(spacing: 10) {
                            FileIcon(path: item.path, size: 20)
                            Text(item.name).lineLimit(1).frame(width: 130, alignment: .leading)
                            SizeBar(fraction: Double(item.size) / top)
                            Text(Fmt.size(item.size)).monospacedDigit().frame(width: 72, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { ItemMenu(items: [item], allowDelete: false) }
                }
            }
        }
    }
}

private struct LargestFiles: View {
    @Environment(Store.self) private var store
    let items: [Item]

    var body: some View {
        Card(title: "Largest files", subtitle: "Outside app data · 200 MB and up") {
            if items.isEmpty {
                Text("No files over 200 MB in your folders.").foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        FileIcon(path: item.path, size: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Text(item.loc ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Text(Fmt.size(item.size)).monospacedDigit()
                        RowActions(item: item, actions: [.reveal, .trash])
                    }
                    .padding(.vertical, 3)
                    .contextMenu { ItemMenu(items: [item]) }
                }
            }
            Button("See all large files") { store.pane = .large }.buttonStyle(.link)
        }
    }
}

private struct OutsideHome: View {
    @Environment(Store.self) private var store
    let items: [Outside]
    let snapshots: Int

    var body: some View {
        Card(title: "Outside your home folder",
             subtitle: "Part of “macOS & other”. Managed by macOS or other tools, so Storage Monitor only shows them.") {
            VStack(spacing: 6) {
                ForEach(items) { x in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(x.name).frame(width: 170, alignment: .leading)
                        Text(x.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        Text(Fmt.size(x.size)).monospacedDigit()
                        Button { store.reveal(path: x.path) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless).help("Show in Finder")
                    }
                }
                if snapshots > 0 {
                    Text("\(Fmt.count(snapshots, "local Time Machine snapshot")) — macOS removes them automatically when it needs space.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
