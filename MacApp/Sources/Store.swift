import AppKit
import SwiftUI

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case overview, explorer, large, unused, duplicates, caches, clutter, apps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .explorer: return "Explorer"
        case .large: return "Large Files"
        case .unused: return "Unused"
        case .duplicates: return "Duplicates"
        case .caches: return "Caches"
        case .clutter: return "Clutter"
        case .apps: return "Applications"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "chart.bar.xaxis"
        case .explorer: return "folder"
        case .large: return "arrow.up.doc"
        case .unused: return "clock.arrow.circlepath"
        case .duplicates: return "doc.on.doc"
        case .caches: return "archivebox"
        case .clutter: return "tray.full"
        case .apps: return "square.grid.2x2"
        }
    }
}

struct Toast: Identifiable {
    let id = UUID()
    let text: String
    var isError = false
    var undo: [[String: String]]?
    var offerEmptyTrash = false
}

struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let button: String
    /// Deleting for good: the alert warns loudly and Cancel is the default button, so Return never erases.
    var permanent = false
    /// False for a confirmation that isn't about removing anything (installing an update): a normal default button.
    var destructive = true
    let action: () async -> Void
}

@MainActor
@Observable
final class Store {
    /// The single app state. Row-level views (table cells, context menus) use this directly because
    /// SwiftUI doesn't always hand them the environment when it builds them outside the view tree.
    static let shared = Store()

    enum Phase: Equatable {
        case starting
        case ready
        case failed(String)
    }

    let engine = EngineClient()
    var phase: Phase = .starting
    var status: EngineStatus?
    var overview: Overview?
    var pane: Pane = .overview
    var explorePath: String?
    var toast: Toast?
    var confirm: ConfirmRequest?
    var uninstallTarget: Item?
    var dataVersion = 0
    var busy = false
    var needsPython = false
    var update: UpdateInfo?
    private var started = false

    // First launch: Full Disk Access, then Scan, then the results of that first scan.
    /// Remembered so a later launch without a scan goes straight to the Scan button.
    var accessSkipped = UserDefaults.standard.bool(forKey: "accessSkipped") {
        didSet { UserDefaults.standard.set(accessSkipped, forKey: "accessSkipped") }
    }
    var openedAccessSettings = false
    /// The first scan just finished: show its summary before the normal window.
    var firstScanResults = false
    private(set) var firstScanRunning = false
    /// Stop was pressed and the engine is winding the scan down.
    private(set) var stoppingScan = false

    var home: String { status?.home ?? NSHomeDirectory() }
    var trashPath: String { home + "/.Trash" }
    var isScanning: Bool { status?.scan.state == "scanning" }
    var hasData: Bool { status?.hasData == true }
    /// Until there is a first scan (and while its summary is up), the window shows the first-launch flow.
    var showsFirstLaunch: Bool { status != nil && (!hasData || firstScanResults) }

    // MARK: lifecycle

    func start() async {
        guard !started else { return }
        started = true
        phase = .starting
        do {
            try await engine.launch()
            phase = .ready
            needsPython = false
        } catch {
            started = false             // allow "Try Again"
            if case EngineError.noPython = error { needsPython = true }
            phase = .failed(error.localizedDescription)
            return
        }
        await refreshStatus()
        if hasData { await loadOverview() }
        Task { await pollLoop() }
        Task { await checkForUpdates(userInitiated: false) }
    }

    private func pollLoop() async {
        var wasScanning = isScanning
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(wasScanning || firstScanRunning ? 400 : 2000))
            await refreshStatus()
            let scanning = isScanning
            // A small first scan can finish between two checks, so it counts as ended without being seen running.
            if !scanning && (wasScanning || firstScanRunning) {
                let firstScanDone = firstScanRunning && status?.scan.state == "done"
                if status?.scan.state == "error" {
                    show("The scan failed. Details are in \(EngineClient.logURL.path).", error: true)
                }
                await dataChanged()
                if firstScanRunning {
                    // Together, once the overview is loaded: the view goes from scanning straight to results.
                    firstScanResults = firstScanDone
                    firstScanRunning = false
                }
            }
            if !scanning { stoppingScan = false }
            wasScanning = scanning
        }
    }

    func refreshStatus() async {
        if let s: EngineStatus = try? await engine.get("status") {
            if s != status { status = s }
        }
    }

    func loadOverview() async {
        if let o: Overview = try? await engine.get("overview") { overview = o }
    }

    /// Something changed on disk: every view reloads (they key their `.task` on dataVersion).
    func dataChanged() async {
        dataVersion += 1
        await loadOverview()
        await refreshStatus()
    }

    func rescan() async {
        let _: OKResponse? = try? await engine.post("scan")
        await refreshStatus()
    }

    // MARK: first launch

    func startFirstScan() async {
        firstScanRunning = true
        await rescan()
    }

    func stopScan() async {
        stoppingScan = true
        let _: OKResponse? = try? await engine.post("stop_scan")
        firstScanRunning = false
        await refreshStatus()
        if !isScanning { stoppingScan = false }
    }

    /// Leaves the first-scan summary for the normal window, on the given view.
    func finishFirstLaunch(showing pane: Pane) {
        self.pane = pane
        firstScanResults = false
    }

    /// Full Disk Access sometimes only applies after the app restarts: reopen once this copy has quit.
    func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: navigation

    func open(_ item: Item) {
        if item.canDrill {
            explore(item.path)
        } else {
            reveal(item)
        }
    }

    func explore(_ path: String) {
        explorePath = path
        pane = .explorer
    }

    func reveal(_ item: Item) { reveal(path: item.path) }

    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFile(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    func copyPath(_ items: [Item]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(items.map(\.path).joined(separator: "\n"), forType: .string)
    }

    // MARK: cleaning up

    func trash(_ items: [Item]) {
        let paths = items.filter { $0.action != "none" }.map(\.path)
        Task { await perform(paths: paths, mode: "trash") }
    }

    func trash(paths: [String]) async {
        await perform(paths: paths, mode: "trash")
    }

    func askDelete(_ items: [Item]) {
        let items = items.filter { $0.action != "none" }
        guard !items.isEmpty else { return }
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        let what = items.count == 1 ? "“\(items[0].name)”" : Fmt.count(items.count, "item")
        confirm = ConfirmRequest(
            title: "Are you sure? This is permanent",
            message: "\(what) (\(Fmt.size(total))) will be erased right away. It won't go to the Trash and can't be undone. Use Move to Trash if you might want it back.",
            button: "Delete Permanently", permanent: true) { [weak self] in
                await self?.perform(paths: items.map(\.path), mode: "delete")
            }
    }

    func askClear(_ items: [Item]) {
        let items = items.filter(\.isClearable)
        guard !items.isEmpty else { return }
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        let onlyTrash = items.count == 1 && items[0].path == trashPath
        confirm = ConfirmRequest(
            title: "Are you sure? This is permanent",
            message: onlyTrash
                ? "Everything in the Trash (\(Fmt.size(total))) will be erased. This can't be undone."
                : "\(Fmt.count(items.count, "cache")) (\(Fmt.size(total))) will be erased. This can't be undone. Apps re-create what they need; quit them first for best results.",
            button: onlyTrash ? "Empty Trash" : "Clear Permanently", permanent: true) { [weak self] in
                await self?.perform(paths: items.map(\.path), mode: "clear")
            }
    }

    func askEmptyTrash() {
        let size = overview?.wins.trash ?? 0
        confirm = ConfirmRequest(
            title: "Are you sure? This is permanent",
            message: "Everything in the Trash (\(Fmt.size(size))) will be erased. This can't be undone.",
            button: "Empty Trash", permanent: true) { [weak self] in
                guard let self else { return }
                await self.perform(paths: [self.trashPath], mode: "clear")
            }
    }

    func askUninstall(_ apps: [Item]) {
        if apps.count == 1 {
            uninstallTarget = apps[0]
            return
        }
        let total = apps.reduce(Int64(0)) { $0 + $1.size }
        confirm = ConfirmRequest(
            title: "Move \(Fmt.count(apps.count, "app")) to the Trash?",
            message: "\(Fmt.size(total)) of apps will be moved to the Trash. Their settings stay in your Library.",
            button: "Move to Trash") { [weak self] in
                await self?.perform(paths: apps.map(\.path), mode: "trash")
            }
    }

    func perform(paths: [String], mode: String) async {
        guard !paths.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let r: DeleteResponse = try await engine.post("delete", ["paths": paths, "mode": mode])
            if let err = r.error {
                show(err, error: true)
                return
            }
            let results = r.results ?? []
            let ok = results.filter(\.ok)
            let bad = results.filter { !$0.ok }
            let amount = ok.reduce(Int64(0)) { $0 + ($1.freed ?? 0) }
            var text: String
            var undo: [[String: String]]?
            switch mode {
            case "trash":
                undo = ok.compactMap { r in r.to.map { ["from": $0, "to": r.path] } }
                text = "Moved \(Fmt.count(ok.count, "item")) (\(Fmt.size(amount))) to the Trash"
            case "clear":
                text = "Cleared \(Fmt.size(r.freed ?? amount))"
            default:
                text = "Deleted \(Fmt.count(ok.count, "item")) · freed \(Fmt.size(r.freed ?? amount))"
            }
            if !bad.isEmpty {
                text += ok.isEmpty ? "" : " — "
                text += "\(Fmt.count(bad.count, "item")) couldn't be removed: \(bad[0].error ?? "unknown error")"
            }
            if ok.contains(where: { $0.partial == true }) {
                text += " (a few files were in use and stayed)"
            }
            toast = Toast(text: text, isError: ok.isEmpty, undo: (undo?.isEmpty ?? true) ? nil : undo,
                          offerEmptyTrash: mode == "trash" && !ok.isEmpty)
            await dataChanged()
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    func undo(_ items: [[String: String]]) async {
        do {
            let r: RestoreResponse = try await engine.post("restore", ["items": items])
            let ok = r.results.filter(\.ok).count
            if ok == r.results.count {
                show("Put back \(Fmt.count(ok, "item"))")
            } else {
                show("Put back \(ok) of \(r.results.count) items: \(r.results.first { !$0.ok }?.error ?? "")", error: ok == 0)
            }
            await dataChanged()
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    // MARK: updates

    /// Asks the engine, which asks GitHub (at most every 12 hours unless the user asked).
    func checkForUpdates(userInitiated: Bool) async {
        do {
            let info: UpdateInfo = try await engine.get("update", userInitiated ? ["force": "1"] : [:])
            update = info
            guard userInitiated else { return }
            if info.available {
                askInstallUpdate()
            } else if let error = info.error {
                show(error, error: true)
            } else {
                show("You're up to date: MacSafe \(info.current ?? "") is the latest version.")
            }
        } catch {
            if userInitiated { show("Couldn't check for updates: \(error.localizedDescription)", error: true) }
        }
    }

    func askInstallUpdate() {
        guard let info = update, info.available, let latest = info.latest else { return }
        confirm = ConfirmRequest(
            title: "Update to MacSafe \(latest)?",
            message: "You have \(info.current ?? "an older version"). MacSafe quits, installs the update and opens again in a few seconds. Your settings and last scan are kept.",
            button: "Update",
            destructive: false
        ) { [weak self] in await self?.installUpdate() }
    }

    /// Starts install.sh --update. When it succeeds the installer quits this app and reopens the new
    /// version, so only a failure ever comes back here.
    func installUpdate() async {
        do {
            let _: OKResponse = try await engine.post("update")
            update = try? await engine.get("update")
            while update?.state == "installing" {
                try? await Task.sleep(for: .seconds(1))
                if let info: UpdateInfo = try? await engine.get("update") { update = info }
            }
            if update?.state == "failed" {
                show("The update didn't install: \(update?.error ?? "unknown error"). Details are in ~/Library/Logs/MacSafe/update.log.",
                     error: true)
            }
        } catch {
            show("Couldn't start the update: \(error.localizedDescription)", error: true)
        }
    }

    func show(_ text: String, error: Bool = false) {
        toast = Toast(text: text, isError: error)
    }

    func openPythonDownload() {
        if let url = URL(string: "https://www.python.org/downloads/macos/") {
            NSWorkspace.shared.open(url)
        }
    }

    func openFullDiskAccessSettings() {
        openedAccessSettings = true
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func openTerminalDashboard() {
        guard let cmd = Bundle.main.path(forResource: "macsafe", ofType: "command") else { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([URL(fileURLWithPath: cmd)], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}
