import Foundation

// Mirrors the JSON returned by engine.py (keys are converted from snake_case).

struct Disk: Decodable, Equatable {
    let total: Int64
    let free: Int64
    let used: Int64
}

struct ScanInfo: Decodable, Equatable {
    let state: String
    var phase: String?
    var files: Int?
    var bytes: Int64?
    var current: String?
    var elapsed: Double?
    var fraction: Double?
    var error: String?
}

struct EngineStatus: Decodable, Equatable {
    let scan: ScanInfo
    let hasData: Bool
    let scannedAt: Double?
    let denied: Int
    let disk: Disk
    let fda: Bool
    let home: String
}

struct Leftover: Decodable, Hashable {
    let path: String
    let size: Int64
    let loc: String
}

struct Item: Decodable, Identifiable, Hashable {
    let path: String
    let name: String
    let size: Int64
    var dir: Bool?
    var kind: String?
    var activity: Double?
    var used: Double?
    var mtime: Double?
    var loc: String?
    var drill: Bool?
    var appdata: Bool?
    // clutter
    var label: String?
    var project: String?
    var product: String?
    var inStaleFolder: Bool?
    // caches
    var group: String?
    var note: String?
    var safety: String?
    var action: String?
    var sub: String?
    // apps
    var bid: String?
    var version: String?
    var store: Bool?
    var leftovers: [Leftover]?
    var leftoverSize: Int64?

    var id: String { path }
    var activitySort: Double { activity ?? 0 }
    var usedSort: Double { used ?? 0 }
    var leftoverSort: Int64 { leftoverSize ?? 0 }
    var url: URL { URL(fileURLWithPath: path) }
    var canDrill: Bool { drill == true }
    var isClearable: Bool { action == "clear" }

    static func == (a: Item, b: Item) -> Bool { a.path == b.path && a.size == b.size && a.activity == b.activity }
    func hash(into h: inout Hasher) { h.combine(path) }
}

struct Segment: Decodable, Identifiable {
    let key: String
    let label: String
    let size: Int64
    var id: String { key }
}

struct Wins: Decodable {
    let trash: Int64
    let caches: Int64
    let downloads: Int64
    let installers: Int64
    let dev: Int64
    let backups: Int64
    var clutter: Int64 { downloads + installers + dev + backups }
}

struct Outside: Decodable, Identifiable {
    let path: String
    let name: String
    let note: String
    let size: Int64
    var id: String { path }
}

struct Overview: Decodable {
    let disk: Disk
    let breakdown: [Segment]
    let home: Int64
    let top: [Item]
    let wins: Wins
    let large: [Item]
    let outside: [Outside]
    let snapshots: Int
}

struct ItemsResponse: Decodable { let items: [Item] }
struct UnusedResponse: Decodable { let files: [Item]; let folders: [Item] }
struct ClutterResponse: Decodable { let downloads: [Item]; let installers: [Item]; let dev: [Item]; let backups: [Item] }

struct Crumb: Decodable, Hashable {
    let path: String
    let name: String
}

struct ExploreResponse: Decodable {
    let path: String
    let size: Int64
    let files: Int
    let items: [Item]
    let other: Int64
    let crumbs: [Crumb]
}

struct DupGroup: Decodable, Identifiable {
    let size: Int64
    let wasted: Int64
    let items: [Item]
    var id: String { items.first?.path ?? "" }
}

struct DupResponse: Decodable {
    let state: String
    var fraction: Double?
    var groups: [DupGroup]?
    var wasted: Int64?
    var error: String?
}

struct ActionResult: Decodable {
    let path: String
    let ok: Bool
    var error: String?
    var to: String?
    var freed: Int64?
    var partial: Bool?
}

struct DeleteResponse: Decodable {
    var results: [ActionResult]?
    var freed: Int64?
    var mode: String?
    var disk: Disk?
    var error: String?
}

struct RestoreResponse: Decodable {
    let results: [ActionResult]
    let disk: Disk
}

struct OKResponse: Decodable { var ok: Bool? }
