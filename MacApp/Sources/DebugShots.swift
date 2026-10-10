import AppKit
import SwiftUI

/// Development aid: `SM_SHOTS=/some/dir` makes the app save a PNG of its window for every pane, then quit.
/// `SM_HOLD=1` keeps the app open for `screencapture`; `SM_OVERVIEW_JSON`/`SM_STATUS_JSON` load fixtures.
/// `SM_APPEARANCE=light` and `SM_SELECT=appdata` pick the look and the Overview's focused category.
/// `SM_FIRST_SHOTS=/some/dir` does the same for each first-launch step (run it with a HOME that has no scan).
enum DebugShots {
    @MainActor
    static func runIfRequested(store: Store) async {
        if let out = ProcessInfo.processInfo.environment["SM_CLICKTEST"] {
            await clickTest(store: store, out: out)
            return
        }
        if let dir = ProcessInfo.processInfo.environment["SM_FIRST_SHOTS"] {
            await firstLaunchShots(store: store, dir: dir)
            return
        }
        guard let dir = ProcessInfo.processInfo.environment["SM_SHOTS"] else { return }
        while !store.hasData { try? await Task.sleep(for: .milliseconds(300)) }
        loadFixtures(store: store)
        let panes = (ProcessInfo.processInfo.environment["SM_PANES"] ?? "")
            .split(separator: ",").compactMap { Pane(rawValue: String($0)) }
        // SM_APPEARANCE=light|dark forces this app's appearance (not the system's).
        switch ProcessInfo.processInfo.environment["SM_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        func capture(_ name: String) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        // SM_HOLD=1: set the first pane, selection and appearance, then keep the app open so the real composited
        // window can be grabbed with `screencapture -l <window id>` (cacheDisplay skips vibrancy and blurs).
        if ProcessInfo.processInfo.environment["SM_HOLD"] != nil {
            store.pane = panes.first ?? .overview
            store.overviewSelection = ProcessInfo.processInfo.environment["SM_SELECT"]
            NSApp.activate(ignoringOtherApps: true)
            while true { try? await Task.sleep(for: .seconds(3600)) }
        }
        for pane in panes.isEmpty ? Pane.allCases : panes {
            store.pane = pane
            try? await Task.sleep(for: .seconds(pane == .apps ? 3 : 2))
            capture(pane.rawValue)
            // SM_SELECT=<breakdown key> (apps, files, appdata, system, free) also shoots the Overview with that category focused.
            if pane == .overview, let key = ProcessInfo.processInfo.environment["SM_SELECT"] {
                store.overviewSelection = key
                try? await Task.sleep(for: .seconds(1))
                capture("overview-selected")
                store.overviewSelection = nil
            }
        }
        NSApp.terminate(nil)
    }

    /// SM_OVERVIEW_JSON=<file> (and optionally SM_STATUS_JSON=<file>) replace the engine's overview and status with
    /// fixtures, so states the real scan doesn't reach (something to clean, no Full Disk Access) can be shown.
    @MainActor
    static func loadFixtures(store: Store) {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SM_OVERVIEW_JSON"] else { return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        func read<T: Decodable>(_ p: String) -> T? {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: p)) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
        guard let overview: Overview = read(path) else {
            FileHandle.standardError.write("fixture: could not decode \(path)\n".data(using: .utf8)!)
            return
        }
        FileHandle.standardError.write("fixture: loaded \(path)\n".data(using: .utf8)!)
        store.useFixture(overview: overview, status: env["SM_STATUS_JSON"].flatMap { read($0) })
    }

    @MainActor
    static func firstLaunchShots(store: Store, dir: String) async {
        func shot(_ name: String) async {
            try? await Task.sleep(for: .seconds(1.2))
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        while store.status == nil { try? await Task.sleep(for: .milliseconds(200)) }
        let skipped = store.accessSkipped
        store.accessSkipped = false
        await shot("1-access")
        store.accessSkipped = true
        await shot("2-ready")
        await store.startFirstScan()
        await shot("3-scanning")
        while !store.firstScanResults { try? await Task.sleep(for: .milliseconds(300)) }
        await shot("4-results")
        store.accessSkipped = skipped  // shares the real app's settings: leave them as they were
        NSApp.terminate(nil)
    }

    /// Clicks every sidebar row with synthesized mouse events and records which pane ends up selected.
    @MainActor
    static func clickTest(store: Store, out: String) async {
        FileHandle.standardError.write("clicktest: start phase=\(store.phase) hasData=\(store.hasData)\n".data(using: .utf8)!)
        while !store.hasData { try? await Task.sleep(for: .milliseconds(300)) }
        FileHandle.standardError.write("clicktest: has data, windows=\(NSApp.windows.map { "\($0.title) visible=\($0.isVisible)" })\n".data(using: .utf8)!)
        try? await Task.sleep(for: .seconds(1.5))
        var log = ""
        guard let window = NSApp.windows.first(where: { $0.isVisible }), let root = window.contentView?.superview else { return }
        func tables(_ v: NSView) -> [NSTableView] {
            (v as? NSTableView).map { [$0] } ?? v.subviews.flatMap(tables)
        }
        let all = tables(root)
        log += "tables: \(all.map { "\(type(of: $0)) rows=\($0.numberOfRows) x=\(Int($0.convert($0.bounds, to: nil).minX))" })\n"
        guard let sidebar = all.min(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }) else { return }
        for row in 0..<sidebar.numberOfRows {
            let r = sidebar.rect(ofRow: row)
            let p = sidebar.convert(NSPoint(x: r.midX, y: r.midY), to: nil)
            func event(_ type: NSEvent.EventType) -> NSEvent? {
                NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            }
            // Queue the mouse-up first: mouse-down starts a tracking loop that waits for it.
            if let up = event(.leftMouseUp) { NSApp.postEvent(up, atStart: false) }
            if let down = event(.leftMouseDown) { window.sendEvent(down) }
            try? await Task.sleep(for: .milliseconds(700))
            log += "row \(row) -> pane=\(store.pane.rawValue) selectedRow=\(sidebar.selectedRow)\n"
        }
        try? log.write(toFile: out, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
