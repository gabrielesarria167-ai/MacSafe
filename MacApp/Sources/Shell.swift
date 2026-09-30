import SwiftUI

struct ContentView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            if store.phase == .ready && store.showsFirstLaunch {
                FirstLaunchView()
            } else {
                NavigationSplitView {
                    Sidebar()
                } detail: {
                    detail
                        .frame(minWidth: 680, minHeight: 480)
                        .background { Glows() }
                        .toolbar { VersionToolbarItem() }
                }
            }
        }
        .overlay(alignment: .bottom) { ToastView().animation(.snappy, value: store.toast?.id) }
        .alert(store.confirm?.title ?? "",
               isPresented: Binding(get: { store.confirm != nil }, set: { if !$0 { store.confirm = nil } }),
               presenting: store.confirm) { req in
            if req.destructive {
                Button(req.button, role: .destructive) { Task { await req.action() } }
            } else {
                Button(req.button) { Task { await req.action() } }.keyboardShortcut(.defaultAction)
            }
            if req.permanent {
                Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel", role: .cancel) {}
            }
        } message: { req in
            Text(req.message)
        }
        .sheet(item: $store.uninstallTarget) { app in UninstallSheet(app: app) }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.phase {
        case .starting:
            ProgressView("Starting…")
        case .failed(let message):
            ContentUnavailableView {
                Label(store.needsPython ? "Python 3 is needed" : "Couldn't start the scanner",
                      systemImage: "exclamationmark.triangle")
            } description: {
                Text(store.needsPython
                     ? "MacSafe's scanner runs on Python 3. Install it from python.org (a free, official installer), then try again."
                     : message)
            } actions: {
                if store.needsPython {
                    Button("Download Python…") { store.openPythonDownload() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Try Again") { Task { await store.start() } }
            }
        case .ready:
            if !store.hasData {
                ProgressView()  // only until the first status arrives; FirstLaunchView covers "no scan yet"
            } else {
                switch store.pane {
                case .overview: OverviewView()
                case .explorer: ExplorerView()
                case .large: LargeFilesView()
                case .unused: UnusedView()
                case .duplicates: DuplicatesView()
                case .caches: CachesView()
                case .clutter: ClutterView()
                case .apps: AppsView()
                }
            }
        }
    }
}

struct Sidebar: View {
    private var store: Store { .shared }

    var body: some View {
        let wins = store.overview?.wins
        List {
            Section("Storage") {
                SidebarRow(pane: .overview)
                SidebarRow(pane: .explorer)
            }
            Section("Find") {
                SidebarRow(pane: .large)
                SidebarRow(pane: .unused)
                SidebarRow(pane: .duplicates)
            }
            Section("Clean Up") {
                SidebarRow(pane: .caches, badge: wins?.caches)
                SidebarRow(pane: .clutter, badge: wins?.clutter)
                SidebarRow(pane: .apps)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        .safeAreaInset(edge: .bottom, spacing: 0) { DiskFooter() }
    }
}

extension Pane {
    /// Each section's tile colour in the sidebar.
    var tint: Tint {
        switch self {
        case .overview: return .blue
        case .explorer: return .teal
        case .large: return .orange
        case .unused: return .yellow
        case .duplicates: return .pink
        case .caches: return .green
        case .clutter: return .purple
        case .apps: return .blue
        }
    }

    /// The filled symbol drawn on that tile.
    var tileSymbol: String {
        switch self {
        case .overview: return "chart.pie.fill"
        case .explorer: return "folder.fill"
        case .large: return "doc.fill"
        case .unused: return "clock.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .caches: return "archivebox.fill"
        case .clutter: return "tray.full.fill"
        case .apps: return "square.grid.2x2.fill"
        }
    }
}

/// A sidebar entry. It's a plain button (not list selection) so a click always switches the pane.
struct SidebarRow: View {
    private var store: Store { .shared }
    let pane: Pane
    var badge: Int64?
    @State private var hovering = false

    var body: some View {
        let selected = store.pane == pane
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button {
            store.pane = pane
        } label: {
            HStack(spacing: 9) {
                ColorTile(tint: pane.tint, symbol: pane.tileSymbol, size: 20)
                Text(pane.title)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 4)
                if let badge, badge >= 1_000_000 {
                    Text(Fmt.size(badge))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.freeable)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Tint.green.top.opacity(0.16), in: Capsule())
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    shape.fill(LinearGradient(colors: [Tint.blue.top.opacity(0.32), Tint.blue.top.opacity(0.14)],
                                              startPoint: .leading, endPoint: .trailing))
                        .overlay(shape.strokeBorder(Tint.blue.top.opacity(0.4)))
                } else {
                    shape.fill(Color.primary.opacity(hovering ? 0.06 : 0))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct DiskFooter: View {
    private var store: Store { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let disk = store.status?.disk {
                let low = Double(disk.free) / Double(max(disk.total, 1)) < 0.1
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive").foregroundStyle(.secondary)
                    Text("Macintosh HD").fontWeight(.medium)
                }
                .font(.callout)
                StorageStrip(disk: disk, breakdown: store.overview?.breakdown ?? [])
                    .frame(height: 6)
                Text("\(Fmt.size(disk.free)) free of \(Fmt.size(disk.total))")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(low ? Palette.critical : .secondary)
            }
            if store.isScanning, let scan = store.status?.scan {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(scan.phase ?? "Scanning…").lineLimit(1)
                        if let files = scan.files {
                            Text("\(files.formatted()) files").foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption)
            } else {
                HStack {
                    Text("Scanned \(Fmt.ago(store.status?.scannedAt).lowercased())")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Button { Task { await store.rescan() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Rescan (⌘R)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

/// The disk in one thin bar: the storage categories in their colours, free space as the track.
/// Before the breakdown has loaded it shows used space in one colour.
struct StorageStrip: View {
    let disk: Disk
    let breakdown: [Segment]

    var body: some View {
        let total = Double(max(disk.total, 1))
        GeometryReader { geo in
            let parts = breakdown.isEmpty ? [disk.used] : breakdown.map(\.size)
            let width = max(0, geo.size.width - CGFloat(parts.count) * 1.5)
            HStack(spacing: 1.5) {
                ForEach(parts.indices, id: \.self) { i in
                    Capsule().fill(Tint.categories[i % Tint.categories.count].gradient)
                        .frame(width: max(2, width * CGFloat(Double(parts[i]) / total)))
                }
                Capsule().fill(Palette.track)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Top right of the window: "MacSafe 1.2", which turns into an Update button when GitHub has a newer
/// version, and into a progress indicator while it installs.
struct VersionToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        // The badge draws its own capsule, so the toolbar's glass bubble would only double it up.
        if #available(macOS 26, *) {
            ToolbarItem(placement: .primaryAction) { VersionBadge() }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) { VersionBadge() }
        }
    }
}

/// One accent capsule that highlights as a whole on hover (the toolbar's own button styling only
/// highlights the title).
struct UpdatePillStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Palette.accent))
            .overlay(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0 : hovering ? 0.16 : 0)))
            .overlay(Capsule().fill(Color.black.opacity(configuration.isPressed ? 0.18 : 0)))
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct VersionBadge: View {
    private var store: Store { .shared }
    private static let bundled = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    var body: some View {
        let u = store.update
        if let u, let latest = u.latest, u.state == "installing" {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing MacSafe \(latest)…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("MacSafe reopens when it's done.")
        } else if let u, let latest = u.latest, u.available {
            Button { store.askInstallUpdate() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Update to \(latest)")
                }
            }
            .buttonStyle(UpdatePillStyle())
            .help("You have MacSafe \(u.current ?? "an older version"). MacSafe \(latest) is available.")
        } else if let version = u?.current ?? Self.bundled {
            Text("MacSafe \(version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help("Check for Updates… is in the MacSafe menu.")
        }
    }
}

struct UninstallSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let app: Item
    @State private var chosen = Set<String>()

    var body: some View {
        let leftovers = app.leftovers ?? []
        let extra = leftovers.filter { chosen.contains($0.path) }.reduce(Int64(0)) { $0 + $1.size }
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                FileIcon(path: app.path, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uninstall \(app.name)?").font(.title3.weight(.semibold))
                    Text("The app (\(Fmt.size(app.size))) moves to the Trash, so you can still put it back.")
                        .foregroundStyle(.secondary)
                }
            }
            if !leftovers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Also remove its data from your Library").font(.headline)
                    ForEach(leftovers, id: \.path) { l in
                        Toggle(isOn: Binding(get: { chosen.contains(l.path) },
                                             set: { if $0 { chosen.insert(l.path) } else { chosen.remove(l.path) } })) {
                            HStack {
                                Text(l.loc).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Fmt.size(l.size)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    Text("These folders hold the app's settings, caches and documents. Keep them if you might reinstall it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Text("Total: \(Fmt.size(app.size + extra))").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    let paths = [app.path] + chosen.sorted()
                    dismiss()
                    Task { await store.trash(paths: paths) }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear { chosen = Set(leftovers.map(\.path)) }
    }
}
