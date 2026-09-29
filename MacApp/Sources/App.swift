import AppKit
import SwiftUI

@main
struct MacSafeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = Store.shared

    var body: some Scene {
        Window("MacSafe", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 960, minHeight: 620)
                .task {
                    await store.start()
                    await DebugShots.runIfRequested(store: store)
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await store.checkForUpdates(userInitiated: true) } }
                    .disabled(store.phase != .ready || store.update?.state == "installing")
            }
            CommandMenu("Storage") {
                Button("Rescan") { Task { await store.rescan() } }
                    .keyboardShortcut("r")
                    .disabled(store.isScanning || store.phase != .ready)
                Button("Empty Trash…") { store.askEmptyTrash() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                    .disabled(!store.hasData)
                Divider()
                ForEach(Array(Pane.allCases.enumerated()), id: \.element) { i, pane in
                    Button(pane.title) { store.pane = pane }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
                Divider()
                Button("Open Terminal Dashboard") { store.openTerminalDashboard() }
                Button("Full Disk Access Settings…") { store.openFullDiskAccessSettings() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
