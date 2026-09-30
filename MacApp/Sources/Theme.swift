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

extension NSColor {
    /// A colour with separate light- and dark-mode values, alpha included.
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
}

/// The icon's colours. Each has a deeper partner, so fills can run top to bottom like the icon's glass.
struct Tint {
    let top: Color
    let bottom: Color

    private init(_ top: UInt32, _ bottom: UInt32) {
        self.top = Color(nsColor: NSColor(hex: top))
        self.bottom = Color(nsColor: NSColor(hex: bottom))
    }

    var gradient: LinearGradient { LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom) }
    /// For bars: deep at the start, bright at the end.
    var sweep: LinearGradient { LinearGradient(colors: [bottom, top], startPoint: .leading, endPoint: .trailing) }

    static let blue = Tint(0x4da3ff, 0x2f6fe8)
    static let orange = Tint(0xff7a45, 0xe8502a)
    static let green = Tint(0x2fd49a, 0x14a877)
    static let yellow = Tint(0xffc233, 0xf09a12)
    static let purple = Tint(0x9b7bff, 0x6a4ae0)
    static let pink = Tint(0xff5c8a, 0xe0346a)
    static let teal = Tint(0x3ccfe0, 0x1596b8)
    static let gray = Tint(0x9a9aa1, 0x66666d)
    /// Storage categories, in the engine's breakdown order: apps, your files, app data, macOS & other.
    static let categories: [Tint] = [.blue, .orange, .green, .yellow]
}

enum Palette {
    /// Categorical slots in fixed order: the icon's storage colours, as on the first-launch ring.
    static let series: [Color] = Tint.categories.map(\.top)
    static let accent = Color.dynamic(0x2a78d6, 0x3987e5)
    static let track = Color(nsColor: .dynamic(NSColor(white: 0, alpha: 0.08), NSColor(white: 1, alpha: 0.08)))
    static let good = Color(nsColor: NSColor(hex: 0x0ca30c))
    static let warning = Color(nsColor: NSColor(hex: 0xfab219))
    static let critical = Color(nsColor: NSColor(hex: 0xd03b3b))
    static let card = Color(nsColor: .controlBackgroundColor)
    /// A pane of frosted glass over the window's glows.
    static let glass = Color(nsColor: .dynamic(NSColor(white: 1, alpha: 0.62), NSColor(white: 1, alpha: 0.045)))
    static let glassEdge = Color(nsColor: .dynamic(NSColor(white: 0, alpha: 0.08), NSColor(white: 1, alpha: 0.09)))
    /// Text in the brand's green, readable on both grounds.
    static let freeable = Color.dynamic(0x0f8a61, 0x2fd49a)
}

/// Soft coloured light behind a screen, as on the first-launch steps. Dimmer in light mode.
struct Glows: View {
    /// A third, green light low on the right: the dashboard's, where cleanup lives.
    var green = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let k = scheme == .dark || !green ? 1.0 : 0.55  // first launch keeps its full strength
        GeometryReader { geo in
            ZStack {
                Circle().fill(Brand.blue.opacity(0.28 * k)).frame(width: 460, height: 460)
                    .position(x: geo.size.width * 0.18, y: geo.size.height * 0.85)
                Circle().fill(Color.purple.opacity(0.16 * k)).frame(width: 420, height: 420)
                    .position(x: geo.size.width * 0.85, y: geo.size.height * 0.1)
                if green {
                    Circle().fill(Tint.green.top.opacity(0.12 * k)).frame(width: 380, height: 380)
                        .position(x: geo.size.width * 0.9, y: geo.size.height * 0.8)
                }
            }
            .blur(radius: 110)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A colour tile with a white symbol, in the icon's glassy style. Used for sidebar rows and cleanup items.
struct ColorTile: View {
    let tint: Tint
    let symbol: String
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(tint.gradient)
            .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                              lineWidth: 0.75))
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .shadow(color: tint.bottom.opacity(0.35), radius: size * 0.2, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

/// The main action on a screen: a glossy blue capsule that brightens as a whole on hover.
struct GlossyButtonStyle: ButtonStyle {
    var large = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font((large ? Font.body : Font.callout).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 20 : 14)
            .padding(.vertical, large ? 9 : 6)
            .background(Capsule().fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x5b97ff)), Color(nsColor: NSColor(hex: 0x2f5fe0))],
                                                      startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().fill(Color.white.opacity(hovering && !pressed ? 0.12 : 0)))
            .overlay(Capsule().fill(Color.black.opacity(pressed ? 0.16 : 0)))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                                            lineWidth: 0.75))
            .shadow(color: Color(nsColor: NSColor(hex: 0x3264f0)).opacity(isEnabled ? (hovering ? 0.5 : 0.36) : 0), radius: hovering ? 14 : 10, y: 5)
            .saturation(isEnabled ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

enum Fmt {
    private static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file  // decimal units, like Finder
        f.allowsNonnumericFormatting = false  // "0 bytes", not "Zero KB"
        return f
    }()

    static func size(_ bytes: Int64) -> String {
        Self.bytes.string(fromByteCount: bytes)
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
    /// A brand colour, drawn as a gradient that brightens toward the end of the bar.
    var tint: Tint?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Group {
                    if let tint { Capsule().fill(tint.sweep) } else { Capsule().fill(color) }
                }
                .frame(width: max(4, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}

/// A frosted panel over the window's glows, with a title row that can carry a figure or a link.
struct Card<Content: View, Accessory: View>: View {
    var title: String?
    var subtitle: String?
    /// A figure at the right of the title row, such as a total.
    var trailing: String?
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 8)
                    if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                    accessory
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.glass, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.glassEdge))
    }
}

extension Card where Accessory == EmptyView {
    init(title: String? = nil, subtitle: String? = nil, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, trailing: trailing, content: content, accessory: { EmptyView() })
    }
}
