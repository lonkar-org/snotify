// icon.swift - draw Snotify.app's icon set: green slime dripping down a dark rounded square, at the
// ten sizes iconutil wants. Run by scripts/snotify-app.sh at build time.
//
// Usage: icon OUTPUT.iconset
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Snotify.iconset"
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

/// The drip: slime over the top of the square with strands of different
/// lengths hanging off it, each ending in a round drop, and one drop that has
/// let go. Coordinates are fractions of the square, y up.
func drips(in square: NSRect) -> [NSBezierPath] {
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: square.minX + x * square.width, y: square.minY + y * square.height) }
    func len(_ f: CGFloat) -> CGFloat { f * square.width }
    var parts: [NSBezierPath] = []
    let capBottom: CGFloat = 0.74
    // the cap, with a gently uneven bottom edge
    let cap = NSBezierPath()
    cap.move(to: pt(0, 1.1))
    cap.line(to: pt(1, 1.1))
    cap.line(to: pt(1, capBottom + 0.02))
    cap.curve(to: pt(0.5, capBottom - 0.015), controlPoint1: pt(0.85, capBottom - 0.035), controlPoint2: pt(0.65, capBottom - 0.03))
    cap.curve(to: pt(0, capBottom + 0.01), controlPoint1: pt(0.35, capBottom + 0.01), controlPoint2: pt(0.15, capBottom + 0.02))
    cap.close()
    parts.append(cap)
    // strands: x, width at the cap, y where the drop hangs
    let strands: [(CGFloat, CGFloat, CGFloat)] = [(0.17, 0.085, 0.50), (0.40, 0.10, 0.20), (0.62, 0.07, 0.42), (0.84, 0.09, 0.58)]
    for (x, w, endY) in strands {
        let strand = NSBezierPath()
        strand.move(to: pt(x - w / 2, capBottom + 0.05))
        strand.line(to: pt(x + w / 2, capBottom + 0.05))
        strand.curve(to: pt(x + w * 0.22, endY), controlPoint1: pt(x + w / 2, capBottom - 0.18), controlPoint2: pt(x + w * 0.22, endY + 0.18))
        strand.line(to: pt(x - w * 0.22, endY))
        strand.curve(to: pt(x - w / 2, capBottom + 0.05), controlPoint1: pt(x - w * 0.22, endY + 0.18), controlPoint2: pt(x - w / 2, capBottom - 0.18))
        strand.close()
        parts.append(strand)
        let r = len(w * 0.58)
        parts.append(NSBezierPath(ovalIn: NSRect(x: pt(x, endY).x - r, y: pt(x, endY).y - r * 1.05, width: 2 * r, height: 2 * r)))
    }
    // the drop that let go, under the longest strand
    let r = len(0.045)
    parts.append(NSBezierPath(ovalIn: NSRect(x: pt(0.40, 0.08).x - r, y: pt(0.40, 0.08).y - r, width: 2 * r, height: 2 * r)))
    return parts
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let side = CGFloat(px)
    // Apple's grid: the square is 824/1024 of the canvas, corners 0.2237 of the side.
    let inset = side * (1 - 824.0 / 1024.0) / 2
    let square = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let back = NSBezierPath(roundedRect: square, xRadius: square.width * 0.2237, yRadius: square.width * 0.2237)
    NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.25, blue: 0.29, alpha: 1),
               ending: NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.16, alpha: 1))!
        .draw(in: back, angle: -90)
    // everything else stays inside the rounded square
    back.addClip()
    let lime = NSColor(calibratedRed: 0.56, green: 0.86, blue: 0.24, alpha: 1)
    let shade = NSColor(calibratedRed: 0.36, green: 0.62, blue: 0.14, alpha: 1)
    let parts = drips(in: square)
    // a thin darker edge under each piece, then the fill
    for p in parts {
        let shadow = p.copy() as! NSBezierPath
        shadow.transform(using: AffineTransform(translationByX: 0, byY: -square.width * 0.018))
        shade.setFill()
        shadow.fill()
    }
    lime.setFill()
    for p in parts { p.fill() }
    // a highlight along the cap
    NSColor(calibratedRed: 0.78, green: 0.96, blue: 0.50, alpha: 0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: square.minX + square.width * 0.12, y: square.minY + square.height * 0.86,
                                     width: square.width * 0.40, height: square.height * 0.05),
                 xRadius: square.height * 0.025, yRadius: square.height * 0.025).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
