// Icons.swift - a sender's glyph and colour. `--icon fa-rocket --color orange`
// names a Nerd Fonts glyph, `--icon sf:bell.badge` an SF Symbol, `--icon U+F135`
// a codepoint, and `--icon 🚀` any single character. The glyph is rendered to a
// PNG and attached to the banner, where macOS shows it beside the text, and the
// same rendering marks the row in the history window and the menu bar list.
//
// Symbols Nerd Font Mono travels in the bundle (Resources/nerd-fonts, MIT,
// scripts/fetch-nerd-font.sh pins the release) and is registered for this
// process only, so nothing is installed on the machine. glyphnames.json beside
// it maps the 10,996 names to codepoints; `notify icons QUERY` searches it.

import AppKit
import CoreText

enum Glyphs {
    static let resources = "nerd-fonts"

    /// The font's PostScript name once registered, nil when the bundle lacks it.
    static let fontName: String? = {
        guard let url = Bundle.main.url(forResource: "SymbolsNerdFontMono-Regular", withExtension: "ttf", subdirectory: resources) else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String else { return nil }
        return name
    }()

    static func font(size: CGFloat) -> NSFont? { fontName.flatMap { NSFont(name: $0, size: size) } }

    /// name -> codepoint hex, from the compacted glyphnames.json.
    static let index: [String: String] = {
        guard let url = Bundle.main.url(forResource: "glyphnames", withExtension: "json", subdirectory: resources),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in raw where k != "METADATA" {
            if let s = v as? String { out[k] = s } else if let d = v as? [String: Any], let s = d["code"] as? String { out[k] = s }
        }
        return out
    }()

    static func character(named name: String) -> String? {
        var n = name.lowercased()
        if n.hasPrefix("nf-") { n.removeFirst(3) }
        guard let hex = index[n], let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) else { return nil }
        return String(Character(scalar))
    }

    static func search(_ query: String, limit: Int = 60) -> [(name: String, char: String, code: String)] {
        let q = query.lowercased()
        return index.keys.filter { q.isEmpty || $0.contains(q) }.sorted().prefix(limit).compactMap { name in
            character(named: name).map { (name, $0, index[name]!) }
        }
    }
}

struct IconSpec {
    enum Kind {
        case nerd(String)
        case symbol(String)
        case text(String)
    }
    let kind: Kind
    let spec: String

    init?(_ spec: String) {
        self.spec = spec
        if spec.hasPrefix("sf:") {
            let name = String(spec.dropFirst(3))
            guard NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { return nil }
            kind = .symbol(name)
            return
        }
        let lower = spec.lowercased()
        if lower.hasPrefix("u+") || lower.hasPrefix("0x"),
           let v = UInt32(lower.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(v) {
            kind = .nerd(String(Character(scalar)))
            return
        }
        if let c = Glyphs.character(named: spec) {
            kind = .nerd(c)
            return
        }
        if spec.count <= 2, !spec.contains(" ") {
            kind = .text(spec)
            return
        }
        return nil
    }
}

/// `#rrggbb`, `#rgb`, `rrggbb`, or a system colour by name.
func parseColor(_ s: String) -> NSColor? {
    let named: [String: NSColor] = [
        "red": .systemRed, "orange": .systemOrange, "yellow": .systemYellow, "green": .systemGreen,
        "mint": .systemMint, "teal": .systemTeal, "cyan": .systemCyan, "blue": .systemBlue,
        "indigo": .systemIndigo, "purple": .systemPurple, "pink": .systemPink, "brown": .systemBrown,
        "gray": .systemGray, "grey": .systemGray, "white": .white, "black": .black,
    ]
    if let c = named[s.lowercased()] { return c }
    var hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
    if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
    guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// The glyph on a transparent square, `pixels` wide.
func iconImage(_ icon: IconSpec, color: NSColor, pixels: Int) -> NSImage? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    let side = CGFloat(pixels)
    let bounds = NSRect(x: 0, y: 0, width: side, height: side)
    switch icon.kind {
    case .symbol(let name):
        // Hierarchical, so a symbol's secondary layer (the check inside a
        // seal) keeps its contrast instead of flooding to one colour.
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.62, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: name)?.withSymbolConfiguration(config) else { return nil }
        let s = image.size
        let scale = min((side * 0.8) / max(s.width, 1), (side * 0.8) / max(s.height, 1))
        let w = s.width * scale, h = s.height * scale
        image.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
    case .nerd(let text), .text(let text):
        let isNerd: Bool
        if case .nerd = icon.kind { isNerd = true } else { isNerd = false }
        let font = (isNerd ? Glyphs.font(size: side * 0.72) : nil) ?? NSFont.systemFont(ofSize: side * 0.66)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
        _ = bounds
    }
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
}

@discardableResult
func writePNG(_ image: NSImage, to path: String) -> Bool {
    guard let rep = image.representations.first as? NSBitmapImageRep,
          let png = rep.representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: URL(fileURLWithPath: path))) != nil
}
