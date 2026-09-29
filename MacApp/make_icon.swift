// Renders the app icon: a squircle with a storage "donut" chart. Usage: swift make_icon.swift out.png
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824pt body centred in the 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let path = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
ctx.addPath(path)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let grad = CGGradient(colorsSpace: space, colors: [
    NSColor(srgbRed: 0.09, green: 0.11, blue: 0.16, alpha: 1).cgColor,
    NSColor(srgbRed: 0.16, green: 0.20, blue: 0.29, alpha: 1).cgColor,
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
ctx.restoreGState()

// Donut: used-space segments in the app's palette, free space as a faint track.
let center = CGPoint(x: 512, y: 512)
let radius: CGFloat = 250
let lineWidth: CGFloat = 104
func arc(_ from: CGFloat, _ to: CGFloat, _ color: NSColor) {
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.butt)
    let start = CGFloat.pi / 2 - from * 2 * .pi
    let end = CGFloat.pi / 2 - to * 2 * .pi
    ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    ctx.strokePath()
}
arc(0, 1, NSColor.white.withAlphaComponent(0.10))
let gap: CGFloat = 0.012
let segs: [(CGFloat, CGFloat, UInt32)] = [(0, 0.20, 0x3987e5), (0.20, 0.34, 0xeb6834), (0.34, 0.58, 0x1baf7a), (0.58, 0.76, 0xeda100)]
for (a, b, hex) in segs {
    arc(a + gap, b - gap, NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                                  blue: CGFloat(hex & 0xff) / 255, alpha: 1))
}
// Centre dot
ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
ctx.fillEllipse(in: CGRect(x: 512 - 46, y: 512 - 46, width: 92, height: 92))
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
