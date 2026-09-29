import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

extension Color {
    /// A color with separate light- and dark-mode values.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

enum Palette {
    /// Categorical slots in fixed order (validated palette; dark steps chosen for dark surfaces).
    static let series: [Color] = [
        .dynamic(0x2a78d6, 0x3987e5),  // blue
        .dynamic(0xeb6834, 0xd95926),  // orange
        .dynamic(0x1baf7a, 0x199e70),  // aqua
        .dynamic(0xeda100, 0xc98500),  // yellow
    ]
    static let accent = Color.dynamic(0x2a78d6, 0x3987e5)
    static let track = Color.dynamic(0xe1e0d9, 0x2c2c2a)
    static let good = Color(nsColor: NSColor(hex: 0x0ca30c))
    static let warning = Color(nsColor: NSColor(hex: 0xfab219))
    static let critical = Color(nsColor: NSColor(hex: 0xd03b3b))
    static let card = Color(nsColor: .controlBackgroundColor)
}

enum Fmt {
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)  // decimal units, like Finder
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func ago(_ ts: Double?) -> String {
        guard let ts, ts > 0 else { return "Never" }
        let date = Date(timeIntervalSince1970: ts)
        if Date().timeIntervalSince(date) < 60 { return "Just now" }
        return relative.localizedString(for: date, relativeTo: Date()).capitalizedFirst
    }

    static func date(_ ts: Double?) -> String {
        guard let ts, ts > 0 else { return "—" }
        return Date(timeIntervalSince1970: ts).formatted(date: .abbreviated, time: .shortened)
    }

    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Finder's own icon for any path, cached.
enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

struct FileIcon: View {
    let path: String
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: IconCache.icon(for: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct Tag: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct SizeBar: View {
    let fraction: Double
    var color: Color = Palette.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(color).frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
    }
}

struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}
