// Renders the background of the MacSafe.dmg window: a light ground, the title, and a dashed arc from
// the app over to Applications. Light on purpose: Finder always draws the icon names in black here.
// Usage: swift make_dmg_background.swift out.png <scale>
// The window is 600×400 pt; build.sh places the icons at (160, 200) and (440, 200). Finder can't stop the
// window being resized and pins the picture top-left, so the image is far larger than the window and
// the ground carries on past the design: enlarging the window only shows more of it.
import AppKit

let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let size = CGSize(width: 2560, height: 1600)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.translateBy(x: 0, y: size.height)  // top-left origin, like the Finder window
ctx.scaleBy(x: 1, y: -1)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

// Ground, with a soft blue glow behind the app icon.
ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: [rgb(0xf8f9fb), rgb(0xeceff4)] as CFArray, locations: [0, 1])!,
                       start: .zero, end: CGPoint(x: 0, y: 400), options: [.drawsAfterEndLocation])
let glow = CGGradient(colorsSpace: space, colors: [rgb(0x3566e8, 0.20), rgb(0x3566e8, 0.07), rgb(0x3566e8, 0)] as CFArray,
                      locations: [0, 0.45, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 160, y: 190), startRadius: 0,
                       endCenter: CGPoint(x: 160, y: 190), endRadius: 160, options: [])

// Title.
let para = NSMutableParagraphStyle()
para.alignment = .center
let title = NSAttributedString(string: "Drag MacSafe into Applications", attributes: [
    .font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor(cgColor: rgb(0x15171c))!,
    .paragraphStyle: para])
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
title.draw(with: CGRect(x: 40, y: 40, width: 520, height: 40), options: [.usesLineFragmentOrigin])
NSGraphicsContext.restoreGraphicsState()

// Dashed arc between the icons: both ends at the icons' centre height, the dashes spaced so the line
// starts and ends on a dash, and the head following the curve.
let p0 = CGPoint(x: 238, y: 200), c = CGPoint(x: 300, y: 156), p1 = CGPoint(x: 362, y: 200)
var length: CGFloat = 0
var last = p0
for i in 1...200 {
    let t = CGFloat(i) / 200, u = 1 - t
    let p = CGPoint(x: u * u * p0.x + 2 * u * t * c.x + t * t * p1.x, y: u * u * p0.y + 2 * u * t * c.y + t * t * p1.y)
    length += hypot(p.x - last.x, p.y - last.y)
    last = p
}
let dash = length * 0.015, gap = (length - dash) / 12 - dash
ctx.setStrokeColor(rgb(0x9da1a8))  // opaque: dash and head overlap at the tip
ctx.setLineWidth(4)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.saveGState()
ctx.setLineDash(phase: 0, lengths: [dash, gap])
ctx.move(to: p0)
ctx.addQuadCurve(to: p1, control: c)
ctx.strokePath()
ctx.restoreGState()
let dir = CGVector(dx: p1.x - c.x, dy: p1.y - c.y)
let n = hypot(dir.dx, dir.dy)
for a in [CGFloat.pi * 32 / 180, -CGFloat.pi * 32 / 180] {
    let dx = dir.dx / n, dy = dir.dy / n
    let hx = -(dx * cos(a) - dy * sin(a)) * 15, hy = -(dx * sin(a) + dy * cos(a)) * 15
    ctx.move(to: CGPoint(x: p1.x + hx, y: p1.y + hy))
    ctx.addLine(to: p1)
}
ctx.strokePath()

// The storage colours, as four short dashes along the bottom.
for (i, hex) in [0x4da3ff, 0xff7a45, 0x2fd49a, 0xffc233].enumerated() {
    let path = CGPath(roundedRect: CGRect(x: 300 - 51 + CGFloat(i) * 28, y: 352, width: 18, height: 3),
                      cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(rgb(UInt32(hex)))
    ctx.fillPath()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
