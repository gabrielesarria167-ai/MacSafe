// Renders the app icon: a glass shield whose outline is the storage breakdown. Usage: swift make_icon.swift out.png
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}
func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
}

// macOS icon grid: 824pt body centred in the 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.3))
ctx.addPath(squircle)
ctx.setFillColor(rgb(0x000000))
ctx.fillPath()
ctx.restoreGState()

// From here on, draw in a 100×100 top-left-origin space mapped onto the body.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)
ctx.translateBy(x: body.minX, y: body.minY)
ctx.scaleBy(x: body.width / 100, y: body.height / 100)
let unit = body.width / 100  // shadow blur is in device pixels, not user space

// Background: blue to deep indigo, a soft highlight top-left, and a faint inner rim.
let tile = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100), cornerWidth: 22.5, cornerHeight: 22.5, transform: nil)
ctx.saveGState()
ctx.addPath(tile)
ctx.clip()
ctx.drawLinearGradient(gradient([(rgb(0x2d4fd6), 0), (rgb(0x0d1450), 1)]),
                       start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), options: [])
ctx.drawRadialGradient(gradient([(rgb(0xffffff, 0.35), 0), (rgb(0xffffff, 0), 1)]),
                       startCenter: CGPoint(x: 25, y: 10), startRadius: 0,
                       endCenter: CGPoint(x: 25, y: 10), endRadius: 80, options: [])
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: CGRect(x: 0.4, y: 0.4, width: 99.2, height: 99.2), cornerWidth: 22.1, cornerHeight: 22.1, transform: nil))
ctx.setStrokeColor(rgb(0xffffff, 0.22))
ctx.setLineWidth(0.8)
ctx.strokePath()

// Shield outline as a polyline, starting at the top point and running clockwise, so a fraction
// of its length maps onto a share of the disk the same way the app's donut does.
func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, steps: Int = 48) -> [CGPoint] {
    (1...steps).map { i in
        let t = CGFloat(i) / CGFloat(steps), u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }
}
var shield: [CGPoint] = [CGPoint(x: 50, y: 17), CGPoint(x: 77, y: 26.5), CGPoint(x: 77, y: 48)]
shield += cubic(CGPoint(x: 77, y: 48), CGPoint(x: 77, y: 67), CGPoint(x: 65.5, y: 79), CGPoint(x: 50, y: 86))
shield += cubic(CGPoint(x: 50, y: 86), CGPoint(x: 34.5, y: 79), CGPoint(x: 23, y: 67), CGPoint(x: 23, y: 48))
shield += [CGPoint(x: 23, y: 26.5), CGPoint(x: 50, y: 17)]
var lengths: [CGFloat] = [0]
for i in 1..<shield.count { lengths.append(lengths[i - 1] + hypot(shield[i].x - shield[i - 1].x, shield[i].y - shield[i - 1].y)) }
let total = lengths.last!

func point(at d: CGFloat) -> CGPoint {
    let i = max(1, lengths.firstIndex { $0 >= d } ?? lengths.count - 1)
    let t = (d - lengths[i - 1]) / max(lengths[i] - lengths[i - 1], 0.0001)
    return CGPoint(x: shield[i - 1].x + (shield[i].x - shield[i - 1].x) * t, y: shield[i - 1].y + (shield[i].y - shield[i - 1].y) * t)
}
func outline(from a: CGFloat, to b: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: point(at: a * total))
    for (p, l) in zip(shield, lengths) where l > a * total && l < b * total { path.addLine(to: p) }
    path.addLine(to: point(at: b * total))
    return path
}

// Glass body.
let shieldPath = CGMutablePath()
shieldPath.addLines(between: shield)
shieldPath.closeSubpath()
ctx.saveGState()
ctx.addPath(shieldPath)
ctx.clip()
ctx.drawLinearGradient(gradient([(rgb(0xffffff, 0.40), 0), (rgb(0xffffff, 0.08), 1)]),
                       start: CGPoint(x: 50, y: 17), end: CGPoint(x: 50, y: 86), options: [])
ctx.restoreGState()

// Outline: used space in the app's category colours, each with a glow; free space as a faint track.
let gap: CGFloat = 0.008
let segs: [(CGFloat, CGFloat, UInt32)] = [(0, 0.22, 0x4da3ff), (0.22, 0.37, 0xff7a45), (0.37, 0.60, 0x2fd49a), (0.60, 0.78, 0xffc233)]
ctx.setLineJoin(.round)
ctx.setLineCap(.butt)
for (a, b, hex) in segs {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 7 * unit, color: rgb(hex, 0.9))
    ctx.addPath(outline(from: a + gap, to: b - gap))
    ctx.setStrokeColor(rgb(hex))
    ctx.setLineWidth(4.2)
    ctx.strokePath()
    ctx.restoreGState()
}
ctx.addPath(outline(from: 0.78 + gap, to: 1 - gap))
ctx.setStrokeColor(rgb(0xffffff, 0.22))
ctx.setLineWidth(4.2)
ctx.strokePath()

// Check mark.
ctx.move(to: CGPoint(x: 38.5, y: 50))
ctx.addLine(to: CGPoint(x: 46.5, y: 58.5))
ctx.addLine(to: CGPoint(x: 62, y: 41))
ctx.setStrokeColor(rgb(0xffffff))
ctx.setLineWidth(5.2)
ctx.setLineCap(.round)
ctx.strokePath()
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
