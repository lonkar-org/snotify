// icon.swift - draw Notify.app's icon set: a bell on a rounded square, at the
// ten sizes iconutil wants. Run by scripts/notify-app.sh at build time.
//
// Usage: icon OUTPUT.iconset
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Notify.iconset"
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

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
    let path = NSBezierPath(roundedRect: square, xRadius: square.width * 0.2237, yRadius: square.width * 0.2237)
    NSGradient(starting: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.15, alpha: 1),
               ending: NSColor(calibratedRed: 0.80, green: 0.28, blue: 0.10, alpha: 1))!
        .draw(in: path, angle: -90)
    if let symbol = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: side * 0.5, weight: .medium)) {
        let size = symbol.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        let scale = (square.width * 0.58) / max(size.width, size.height)
        let w = size.width * scale, h = size.height * scale
        tinted.draw(in: NSRect(x: square.midX - w / 2, y: square.midY - h / 2, width: w, height: h))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
