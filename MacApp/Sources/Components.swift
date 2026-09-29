import SwiftUI

enum RowAction: Hashable {
    case drill, reveal, trash, delete, clear, uninstall
}

/// The little buttons at the end of every row.
struct RowActions: View {
    private var store: Store { .shared }
    let item: Item
    var actions: [RowAction] = [.reveal, .trash, .delete]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(actions, id: \.self) { action in
                button(for: action)
            }
        }
        .buttonStyle(.borderless)
        .disabled(store.busy)
    }

    @ViewBuilder
    private func button(for action: RowAction) -> some View {
        switch action {
        case .drill:
            Button { store.explore(item.path) } label: { RowIcon(name: "chevron.right.circle") }
                .help("Open in Explorer")
        case .reveal:
            Button { store.reveal(item) } label: { RowIcon(name: "magnifyingglass") }
                .help("Show in Finder")
        case .trash:
            Button { store.trash([item]) } label: { RowIcon(name: "trash") }
                .help("Move to Trash (⌘⌫)")
        case .delete:
            Button { store.askDelete([item]) } label: { RowIcon(name: "xmark.bin", hoverColor: Palette.critical) }
                .help("Delete Permanently…")
        case .clear:
            Button("Clear") { store.askClear([item]) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Erase what's inside; the app rebuilds it")
        case .uninstall:
            Button("Uninstall…") { store.askUninstall([item]) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

/// A row action glyph: quiet at rest so a long list doesn't shout, full strength under the pointer.
/// Destructive actions only turn red on hover.
private struct RowIcon: View {
    let name: String
    var hoverColor: Color = .primary
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: name)
            .foregroundStyle(hovering && isEnabled ? hoverColor : Color.secondary)
            .frame(width: 24, height: 22)
            .background(hovering && isEnabled ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// Right-click menu shared by every list.
struct ItemMenu: View {
    private var store: Store { .shared }
    let items: [Item]
    var allowDelete = true

    var body: some View {
        if let first = items.first {
            if items.count == 1 {
                if first.canDrill { Button("Open in Explorer") { store.explore(first.path) } }
                Button("Open") { store.openFile(first) }
            }
            Button("Show in Finder") { items.forEach(store.reveal) }
            Button(items.count == 1 ? "Copy Path" : "Copy Paths") { store.copyPath(items) }
            Divider()
            if items.contains(where: \.isClearable) {
                Button("Clear…") { store.askClear(items) }
            }
            if items.contains(where: { $0.kind == "app" && $0.bid != nil }) {
                Button("Uninstall…") { store.askUninstall(items) }
            } else {
                Button("Move to Trash") { store.trash(items) }
            }
            if allowDelete {
                Button("Delete Permanently…", role: .destructive) { store.askDelete(items) }
            }
        }
    }
}

enum BulkMode { case trash, delete, clear, uninstall }

/// Appears at the bottom of a list when rows are selected.
struct BulkBar: View {
    private var store: Store { .shared }
    let items: [Item]
    var modes: [BulkMode] = [.trash, .delete]
    let deselect: () -> Void

    var body: some View {
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        HStack(spacing: 10) {
            Text("\(Fmt.count(items.count, "item")) selected")
                .fontWeight(.medium)
            Text(Fmt.size(total)).monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            Button("Deselect", action: deselect).keyboardShortcut(.escape, modifiers: [])
            ForEach(Array(modes.enumerated()), id: \.offset) { _, mode in
                switch mode {
                case .trash:
                    Button { store.trash(items); deselect() } label: { Label("Move to Trash", systemImage: "trash") }
                        .keyboardShortcut(.delete, modifiers: .command)
                case .delete:
                    Button(role: .destructive) { store.askDelete(items) } label: { Label("Delete…", systemImage: "xmark.bin") }
                case .clear:
                    Button { store.askClear(items) } label: { Label("Clear…", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent)
                        .disabled(!items.contains(where: \.isClearable))
                case .uninstall:
                    Button { store.askUninstall(items) } label: { Label("Uninstall…", systemImage: "trash") }
                        .keyboardShortcut(.delete, modifiers: .command)
                }
            }
        }
        .disabled(store.busy)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Name + location cell used by tables.
struct NameCell: View {
    let item: Item
    var title: String?
    var subtitle: String?

    var body: some View {
        HStack(spacing: 8) {
            FileIcon(path: item.path, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title ?? item.name).lineLimit(1).truncationMode(.middle)
                    if item.appdata == true { Tag(text: "App data") }
                    if item.inStaleFolder == true { Tag(text: "In an unused folder") }
                }
                if let sub = subtitle ?? item.loc {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
            }
        }
        .padding(.vertical, 2)
        .help(item.path)
    }
}

/// Sortable, multi-select table of files/folders with per-row and bulk actions.
struct ItemsTable: View {
    private var store: Store { .shared }
    let items: [Item]
    var dateTitle = "Last Opened"
    @State private var selection = Set<Item.ID>()
    @State private var sortOrder = [KeyPathComparator(\Item.size, order: .reverse)]

    private var selected: [Item] { items.filter { selection.contains($0.id) } }

    var body: some View {
        Table(items.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in NameCell(item: item) }
                .width(min: 220, ideal: 420)
            TableColumn("Size", value: \.size) { item in
                Text(Fmt.size(item.size)).monospacedDigit().fontWeight(.medium)
            }
            .width(min: 70, ideal: 86, max: 110)
            TableColumn(dateTitle, value: \.activitySort) { item in
                Text(Fmt.ago(item.activity)).foregroundStyle(.secondary).help(Fmt.date(item.activity))
            }
            .width(min: 110, ideal: 150, max: 190)
            TableColumn("") { item in
                RowActions(item: item, actions: item.canDrill ? [.drill, .reveal, .trash, .delete] : [.reveal, .trash, .delete])
            }
            .width(min: 76, ideal: 100, max: 110)
        }
        .contextMenu(forSelectionType: Item.ID.self) { ids in
            ItemMenu(items: items.filter { ids.contains($0.id) })
        } primaryAction: { ids in
            if let first = items.first(where: { ids.contains($0.id) }) { store.open(first) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selection.isEmpty { BulkBar(items: selected) { selection = [] } }
        }
        .onChange(of: items) { _, new in
            selection = selection.intersection(new.map(\.id))
        }
    }
}

/// Row used by the grouped lists (caches, clutter, duplicates, explorer).
struct ItemRow: View {
    let item: Item
    var title: String?
    var subtitle: String?
    var note: String?
    var detail: String?
    var fraction: Double?
    var badge: String?
    var badgeColor: Color = .secondary
    var actions: [RowAction] = [.reveal, .trash, .delete]

    var body: some View {
        HStack(spacing: 10) {
            FileIcon(path: item.path, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title ?? item.name).lineLimit(1).truncationMode(.middle)
                    if let badge { Tag(text: badge, color: badgeColor) }
                }
                if let sub = subtitle ?? item.loc, !sub.isEmpty, sub != (title ?? item.name) {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                if let note {
                    Text(note).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                }
                if let fraction {
                    SizeBar(fraction: fraction).frame(maxWidth: 260).padding(.top, 2)
                }
            }
            Spacer(minLength: 12)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: 150, alignment: .trailing)
            }
            Text(Fmt.size(item.size)).monospacedDigit().fontWeight(.medium)
                .frame(width: 76, alignment: .trailing)
            RowActions(item: item, actions: actions)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .help(item.path)
    }
}

struct SafetyLabel: View {
    let safety: String?

    var body: some View {
        if safety == "safe" {
            Label("Safe to clear", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.good)
                .font(.caption.weight(.medium))
        } else {
            Label("Review first", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.warning)
                .font(.caption.weight(.medium))
        }
    }
}

struct FilterBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 16) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
    }
}

struct ToastView: View {
    private var store: Store { .shared }

    var body: some View {
        if let t = store.toast {
            HStack(spacing: 12) {
                Image(systemName: t.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(t.isError ? Palette.critical : Palette.good)
                Text(t.text).lineLimit(3)
                if let undo = t.undo {
                    Button("Undo") {
                        store.toast = nil
                        Task { await store.undo(undo) }
                    }
                    .keyboardShortcut("z", modifiers: .command)
                }
                if t.offerEmptyTrash {
                    Button("Empty Trash…") { store.askEmptyTrash() }
                }
                Button { store.toast = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.bottom, 64)
            .padding(.horizontal, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: t.id) {
                try? await Task.sleep(for: .seconds(t.undo == nil ? 6 : 12))
                if store.toast?.id == t.id { withAnimation { store.toast = nil } }
            }
        }
    }
}

struct FullDiskAccessBanner: View {
    private var store: Store { .shared }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(Palette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some folders couldn't be read").fontWeight(.semibold)
                Text("Give MacSafe Full Disk Access so it can measure Mail, Messages, Safari and other protected data. Rescan afterwards.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { store.openFullDiskAccessSettings() }
        }
        .padding(14)
        .background(Palette.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}
