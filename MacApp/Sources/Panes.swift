import SwiftUI

// MARK: - Large files

struct LargeFilesView: View {
    @Environment(Store.self) private var store
    @State private var items: [Item] = []
    @State private var loaded = false
    @AppStorage("large.min") private var minMB = 100
    @AppStorage("large.kind") private var kind = ""
    @AppStorage("large.appdata") private var appData = true
    @State private var query = ""

    private let kinds: [(String, String)] = [
        ("", "All kinds"), ("video", "Videos"), ("image", "Images"), ("audio", "Audio"), ("archive", "Archives"),
        ("installer", "Installers"), ("app", "Apps"), ("package", "Packages & bundles"), ("3d", "3D & design"),
        ("vm", "Virtual machines"), ("data", "Data & models"), ("document", "Documents"), ("other", "Other"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            FilterBar {
                Picker("Bigger than", selection: $minMB) {
                    Text("50 MB").tag(50); Text("100 MB").tag(100); Text("500 MB").tag(500); Text("1 GB").tag(1000)
                }
                .pickerStyle(.segmented).fixedSize()
                Picker("Kind", selection: $kind) {
                    ForEach(kinds, id: \.0) { Text($0.1).tag($0.0) }
                }
                .fixedSize()
                Toggle("Include app data", isOn: $appData).toggleStyle(.checkbox)
                    .help("Also show big files inside ~/Library and hidden folders")
                Spacer()
                Text("\(Fmt.count(items.count, "item")) · \(Fmt.size(items.reduce(0) { $0 + $1.size }))")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            ItemsTable(items: items)
                .overlay {
                    if loaded && items.isEmpty {
                        ContentUnavailableView("Nothing that big", systemImage: "doc",
                                               description: Text("Try a smaller size or another kind."))
                    }
                }
        }
        .searchable(text: $query, prompt: "Filter by name or folder")
        .navigationTitle("Large Files")
        .task(id: "\(store.dataVersion)|\(minMB)|\(kind)|\(appData)|\(query)") {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }
            let r: ItemsResponse? = try? await store.engine.get("large", [
                "min": "\(minMB)", "kind": kind, "appdata": appData ? "1" : "0", "q": query,
            ])
            if let r { items = r.items; loaded = true }
        }
    }
}

// MARK: - Unused

struct UnusedView: View {
    @Environment(Store.self) private var store
    @State private var data: UnusedResponse?
    @AppStorage("unused.days") private var days = 90
    @AppStorage("unused.min") private var minMB = 10
    @AppStorage("unused.appdata") private var appData = false
    @State private var showFolders = false

    var body: some View {
        let items = showFolders ? (data?.folders ?? []) : (data?.files ?? [])
        VStack(spacing: 0) {
            FilterBar {
                Picker("Show", selection: $showFolders) {
                    Text("Files (\(data?.files.count ?? 0))").tag(false)
                    Text("Folders (\(data?.folders.count ?? 0))").tag(true)
                }
                .pickerStyle(.segmented).fixedSize().labelsHidden()
                Picker("Not opened in", selection: $days) {
                    Text("1 month").tag(30); Text("3 months").tag(90); Text("6 months").tag(180)
                    Text("1 year").tag(365); Text("2 years").tag(730)
                }
                .fixedSize()
                Picker("Bigger than", selection: $minMB) {
                    Text("10 MB").tag(10); Text("50 MB").tag(50); Text("100 MB").tag(100); Text("500 MB").tag(500)
                }
                .fixedSize()
                Toggle("Include app data", isOn: $appData).toggleStyle(.checkbox)
                Spacer()
                Text(Fmt.size(items.reduce(0) { $0 + $1.size })).foregroundStyle(.secondary).monospacedDigit()
            }
            ItemsTable(items: items, dateTitle: "Last Activity")
                .overlay {
                    if data != nil && items.isEmpty {
                        ContentUnavailableView("Nothing forgotten", systemImage: "clock",
                                               description: Text("Everything this big was opened or changed recently. Try a shorter period or a smaller size."))
                    }
                }
        }
        .navigationTitle("Unused")
        .navigationSubtitle("Not opened, changed or added in \(periodName)")
        .task(id: "\(store.dataVersion)|\(days)|\(minMB)|\(appData)") {
            data = try? await store.engine.get("unused", ["days": "\(days)", "min": "\(minMB)", "appdata": appData ? "1" : "0"])
        }
    }

    private var periodName: String {
        [30: "a month", 90: "3 months", 180: "6 months", 365: "a year", 730: "2 years"][days] ?? "\(days) days"
    }
}

// MARK: - Caches

struct CachesView: View {
    @Environment(Store.self) private var store
    @State private var items: [Item] = []
    @State private var loaded = false
    @State private var selection = Set<String>()
    private let order = ["Trash", "App caches", "Developer", "macOS caches", "System"]

    var body: some View {
        let safe = items.filter { $0.safety == "safe" && $0.isClearable && $0.path != store.trashPath }
        let safeTotal = safe.reduce(Int64(0)) { $0 + $1.size }
        let groups = Dictionary(grouping: items) { $0.group ?? "Other" }
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Fmt.size(safeTotal)) can be cleared safely").font(.title3.weight(.semibold))
                    Text("Caches are temporary copies apps keep to go faster. They're rebuilt on demand; quit an app before clearing its cache.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.askClear(safe) } label: { Label("Clear All Safe Caches…", systemImage: "sparkles") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(safe.isEmpty || store.busy)
            }
            .padding(16)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }

            List(selection: $selection) {
                ForEach(order.filter { groups[$0] != nil }, id: \.self) { g in
                    let rows = groups[g] ?? []
                    Section {
                        ForEach(rows) { c in
                            ItemRow(item: c, title: c.name, subtitle: c.sub, note: c.note,
                                    detail: nil, badge: c.safety == "safe" ? "Safe to clear" : "Review first",
                                    badgeColor: c.safety == "safe" ? Palette.good : Palette.warning,
                                    actions: actions(for: c))
                                .tag(c.id)
                                .selectionDisabled(c.action == "none")
                        }
                    } header: {
                        HStack {
                            Text(g)
                            Spacer()
                            Text(Fmt.size(rows.reduce(0) { $0 + $1.size })).monospacedDigit()
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                ItemMenu(items: items.filter { ids.contains($0.id) }, allowDelete: false)
            } primaryAction: { ids in
                ids.first.map { store.reveal(path: $0) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                let sel = items.filter { selection.contains($0.id) }
                if !sel.isEmpty {
                    BulkBar(items: sel, modes: sel.allSatisfy(\.isClearable) ? [.clear] : [.clear, .trash]) { selection = [] }
                }
            }
            .overlay {
                if !loaded {
                    ProgressView()
                } else if items.isEmpty {
                    ContentUnavailableView("No big caches", systemImage: "archivebox",
                                           description: Text("Nothing over 5 MB right now. Caches grow back as you use your apps."))
                }
            }
        }
        .navigationTitle("Caches")
        .task(id: store.dataVersion) {
            if let r: ItemsResponse = try? await store.engine.get("caches") {
                items = r.items
                loaded = true
                selection = selection.intersection(r.items.map(\.id))
            }
        }
    }

    private func actions(for c: Item) -> [RowAction] {
        switch c.action {
        case "clear": return [.reveal, .clear]
        case "trash": return [.reveal, .trash]
        default: return [.reveal]
        }
    }
}

// MARK: - Clutter

struct ClutterView: View {
    @Environment(Store.self) private var store
    @State private var data: ClutterResponse?
    @State private var selection = Set<String>()
    @AppStorage("clutter.age") private var age = 90

    var body: some View {
        let cutoff = Date().timeIntervalSince1970 - Double(age) * 86400
        let downloads = (data?.downloads ?? []).filter { age == 0 || ($0.activity ?? 0) < cutoff }
        let all = downloads + (data?.installers ?? []) + (data?.dev ?? []) + (data?.backups ?? [])
        List(selection: $selection) {
            section("Downloads", icon: "arrow.down.circle", items: downloads,
                    caption: "Files in your Downloads folder\(age == 0 ? "" : " you haven't touched in \(ageName)").") { item in
                ItemRow(item: item, subtitle: nil, detail: Fmt.ago(item.activity))
            } accessory: {
                Picker("Age", selection: $age) {
                    Text("Any age").tag(0); Text("1+ month").tag(30); Text("3+ months").tag(90); Text("1+ year").tag(365)
                }
                .labelsHidden().fixedSize().controlSize(.small)
            }
            section("Installers & disk images", icon: "externaldrive", items: data?.installers ?? [],
                    caption: "Once an app is installed, its .dmg or .pkg is no longer needed.") { item in
                ItemRow(item: item, detail: Fmt.ago(item.activity))
            }
            section("node_modules & virtualenvs", icon: "hammer", items: data?.dev ?? [],
                    caption: "Dependencies you can reinstall with npm install / pip install. The date is the project's last activity.") { item in
                ItemRow(item: item, title: item.project ?? item.name, subtitle: "\(item.label ?? "") · \(item.loc ?? "")",
                        detail: "Active \(Fmt.ago(item.activity).lowercased())")
            }
            section("iPhone & iPad backups", icon: "iphone", items: data?.backups ?? [],
                    caption: "Local device backups. Remove old ones for devices you no longer use.") { item in
                ItemRow(item: item, title: item.label ?? item.name, subtitle: item.product,
                        detail: "Backed up \(Fmt.ago(item.activity).lowercased())")
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            ItemMenu(items: all.filter { ids.contains($0.id) })
        } primaryAction: { ids in
            ids.first.map { store.reveal(path: $0) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let sel = all.filter { selection.contains($0.id) }
            if !sel.isEmpty { BulkBar(items: sel) { selection = [] } }
        }
        .navigationTitle("Clutter")
        .navigationSubtitle("\(Fmt.size(all.reduce(0) { $0 + $1.size })) of leftovers")
        .task(id: store.dataVersion) {
            data = try? await store.engine.get("clutter")
            selection = selection.intersection(all.map(\.id))
        }
    }

    private var ageName: String { [30: "a month", 90: "3 months", 365: "a year"][age] ?? "\(age) days" }

    @ViewBuilder
    private func section<Row: View, Accessory: View>(
        _ title: String, icon: String, items: [Item], caption: String,
        @ViewBuilder row: @escaping (Item) -> Row,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        Section {
            if items.isEmpty {
                Text("Nothing here").foregroundStyle(.tertiary).selectionDisabled()
            }
            ForEach(items) { item in row(item).tag(item.id) }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label(title, systemImage: icon)
                    accessory()
                    Spacer()
                    if !items.isEmpty {
                        Text("\(Fmt.count(items.count, "item")) · \(Fmt.size(items.reduce(0) { $0 + $1.size }))").monospacedDigit()
                    }
                }
                Text(caption).font(.caption).foregroundStyle(.secondary).textCase(nil)
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - Duplicates

struct DuplicatesView: View {
    @Environment(Store.self) private var store
    @State private var data: DupResponse?
    @State private var selection = Set<String>()

    var body: some View {
        let groups = data?.groups ?? []
        let all = groups.flatMap(\.items)
        Group {
            switch data?.state {
            case "running":
                VStack(spacing: 14) {
                    ProgressView(value: data?.fraction ?? 0).frame(width: 320)
                    Text("Comparing files… \((data?.fraction ?? 0).formatted(.percent.precision(.fractionLength(0))))")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case "done":
                if groups.isEmpty {
                    ContentUnavailableView("No duplicates", systemImage: "checkmark.circle",
                                           description: Text("No identical files of 5 MB or more in your folders."))
                } else {
                    List(selection: $selection) {
                        ForEach(groups) { g in
                            Section {
                                ForEach(Array(g.items.enumerated()), id: \.element.id) { i, item in
                                    ItemRow(item: item, detail: Fmt.ago(item.activity),
                                            badge: i == 0 ? "Newest" : nil, badgeColor: Palette.accent)
                                        .tag(item.id)
                                }
                            } header: {
                                HStack {
                                    Text("\(g.items.count) identical copies · \(Fmt.size(g.size)) each")
                                    Spacer()
                                    Button("Keep Newest, Trash Others") { store.trash(Array(g.items.dropFirst())) }
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                    .contextMenu(forSelectionType: String.self) { ids in
                        ItemMenu(items: all.filter { ids.contains($0.id) })
                    } primaryAction: { ids in
                        ids.first.map { store.reveal(path: $0) }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        let sel = all.filter { selection.contains($0.id) }
                        if !sel.isEmpty { BulkBar(items: sel) { selection = [] } }
                    }
                }
            case "error":
                ContentUnavailableView("The search failed", systemImage: "exclamationmark.triangle",
                                       description: Text(data?.error?.split(separator: "\n").last.map(String.init) ?? ""))
            default:
                ContentUnavailableView {
                    Label("Find duplicate files", systemImage: "doc.on.doc")
                } description: {
                    Text("Compares files of 5 MB or more in your folders byte for byte. It reads those files, so it can take a few minutes.")
                } actions: {
                    Button("Find Duplicates") { Task { await start() } }.buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Duplicates")
        .navigationSubtitle(data?.wasted.map { "\(Fmt.size($0)) in extra copies" } ?? "")
        .toolbar {
            if data?.state == "done" && !groups.isEmpty {
                Button("Select Extra Copies") {
                    selection = Set(groups.flatMap { $0.items.dropFirst().map(\.id) })
                }
                .help("Selects every copy except the newest in each set")
            }
            if data?.state == "done" || data?.state == "error" {
                Button { Task { await start() } } label: { Label("Search Again", systemImage: "arrow.clockwise") }
            }
        }
        .task(id: store.dataVersion) { await load() }
    }

    private func start() async {
        let _: OKResponse? = try? await store.engine.post("duplicates")
        await load()
    }

    private func load() async {
        data = try? await store.engine.get("duplicates")
        while data?.state == "running", !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            data = try? await store.engine.get("duplicates")
        }
    }
}

// MARK: - Applications

struct AppsView: View {
    @Environment(Store.self) private var store
    @State private var apps: [Item] = []
    @State private var selection = Set<String>()
    @State private var sortOrder = [KeyPathComparator(\Item.size, order: .reverse)]
    @AppStorage("apps.days") private var days = 0

    var body: some View {
        let cutoff = Date().timeIntervalSince1970 - Double(days) * 86400
        let shown = apps.filter { days == 0 || ($0.used ?? 0) < cutoff }.sorted(using: sortOrder)
        VStack(spacing: 0) {
            FilterBar {
                Picker("Not opened in", selection: $days) {
                    Text("Any time").tag(0); Text("3 months").tag(90); Text("6 months").tag(180); Text("1 year").tag(365)
                }
                .fixedSize()
                Spacer()
                Text("\(Fmt.count(shown.count, "app")) · \(Fmt.size(shown.reduce(0) { $0 + $1.size }))")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Table(shown, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Application", value: \.name) { app in
                    HStack(spacing: 8) {
                        FileIcon(path: app.path, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(app.name).lineLimit(1)
                                if app.store == true { Tag(text: "App Store") }
                            }
                            Text([app.version, app.loc].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .width(min: 220, ideal: 320)
                TableColumn("Size", value: \.size) { app in Text(Fmt.size(app.size)).monospacedDigit().fontWeight(.medium) }
                    .width(min: 70, ideal: 86)
                TableColumn("Leftovers", value: \.leftoverSort) { app in
                    Text(app.leftoverSort > 0 ? Fmt.size(app.leftoverSort) : "—").monospacedDigit().foregroundStyle(.secondary)
                        .help("Data this app keeps in ~/Library")
                }
                .width(min: 70, ideal: 86)
                TableColumn("Last Opened", value: \.usedSort) { app in
                    Text(Fmt.ago(app.used)).foregroundStyle(.secondary).help(Fmt.date(app.used))
                }
                .width(min: 110, ideal: 150)
                TableColumn("") { app in RowActions(item: app, actions: [.reveal, .uninstall]) }
                    .width(min: 110, ideal: 120)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                ItemMenu(items: apps.filter { ids.contains($0.id) }, allowDelete: false)
            } primaryAction: { ids in
                ids.first.map { store.reveal(path: $0) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                let sel = apps.filter { selection.contains($0.id) }
                if !sel.isEmpty { BulkBar(items: sel, modes: [.uninstall]) { selection = [] } }
            }
        }
        .navigationTitle("Applications")
        .task(id: store.dataVersion) {
            if let r: ItemsResponse = try? await store.engine.get("apps") {
                apps = r.items
                selection = selection.intersection(r.items.map(\.id))
            }
        }
    }
}

// MARK: - Explorer

struct ExplorerView: View {
    @Environment(Store.self) private var store
    @State private var data: ExploreResponse?
    @State private var selection = Set<String>()

    var body: some View {
        VStack(spacing: 0) {
            if let data {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(data.crumbs.enumerated()), id: \.element) { i, c in
                            if i > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                            Button { store.explorePath = c.path } label: {
                                HStack(spacing: 4) {
                                    if i == 0 { Image(systemName: "house") }
                                    Text(c.name)
                                }
                            }
                            .buttonStyle(.borderless)
                            .fontWeight(i == data.crumbs.count - 1 ? .semibold : .regular)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }

                let top = Double(max(data.items.first?.size ?? 1, 1))
                List(selection: $selection) {
                    ForEach(data.items) { item in
                        ItemRow(item: item, subtitle: item.dir == true ? "" : (item.kind ?? "").capitalizedFirst,
                                detail: Fmt.ago(item.activity), fraction: Double(item.size) / top,
                                actions: item.canDrill ? [.drill, .reveal, .trash, .delete] : [.reveal, .trash, .delete])
                            .tag(item.id)
                    }
                    if data.other > 0 {
                        HStack {
                            Image(systemName: "ellipsis.circle").font(.title2).foregroundStyle(.tertiary).frame(width: 30)
                            Text("Smaller items")
                            Spacer()
                            Text(Fmt.size(data.other)).monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                    }
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    ItemMenu(items: data.items.filter { ids.contains($0.id) })
                } primaryAction: { ids in
                    if let item = data.items.first(where: { ids.contains($0.id) }) { store.open(item) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    let sel = data.items.filter { selection.contains($0.id) }
                    if !sel.isEmpty { BulkBar(items: sel) { selection = [] } }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(data?.crumbs.last?.name ?? "Explorer")
        .navigationSubtitle(data.map { "\(Fmt.size($0.size)) · \($0.files.formatted()) files" } ?? "")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    if let p = data?.path { store.explorePath = (p as NSString).deletingLastPathComponent }
                } label: { Image(systemName: "chevron.left") }
                .help("Enclosing folder")
                .disabled(data == nil || data?.crumbs.count ?? 0 <= 1)
            }
        }
        .task(id: "\(store.dataVersion)|\(store.explorePath ?? "")") {
            if let r: ExploreResponse = try? await store.engine.get("explore", ["path": store.explorePath ?? store.home]) {
                if r.path != data?.path { selection = [] }
                data = r
            }
        }
    }
}
