import AppKit
import SwiftUI

/// Development aid: `SM_SHOTS=/some/dir` makes the app save a PNG of its window for every pane, then quit.
enum DebugShots {
    @MainActor
    static func runIfRequested(store: Store) async {
        if let out = ProcessInfo.processInfo.environment["SM_CLICKTEST"] {
            await clickTest(store: store, out: out)
            return
        }
        guard let dir = ProcessInfo.processInfo.environment["SM_SHOTS"] else { return }
        while !store.hasData { try? await Task.sleep(for: .milliseconds(300)) }
        let panes = (ProcessInfo.processInfo.environment["SM_PANES"] ?? "")
            .split(separator: ",").compactMap { Pane(rawValue: String($0)) }
        for pane in panes.isEmpty ? Pane.allCases : panes {
            store.pane = pane
            try? await Task.sleep(for: .seconds(pane == .apps ? 3 : 2))
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(pane.rawValue).png"))
        }
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
