// InfoWindow.swift - the window behind a banner's Info button: one Markdown file,
// rendered in an NSTextView so VoiceOver reads it, text selects and links open.

import AppKit

final class InfoWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private let raw: String

    init(title: String, markdown: String) {
        raw = markdown
        super.init()
        let frame = NSRect(x: 0, y: 0, width: 600, height: 440)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = title
        window.delegate = self
        window.minSize = NSSize(width: 360, height: 200)
        window.setFrameAutosaveName("NotifyInfo")

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 14, height: 12)
        text.isAutomaticLinkDetectionEnabled = true
        text.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        text.textStorage?.setAttributedString(styled(markdown: markdown))
        text.setAccessibilityLabel(title)
        scroll.documentView = text

        let copy = NSButton(title: "Copy", target: self, action: #selector(copyAll))
        copy.bezelStyle = .rounded
        copy.setAccessibilityLabel("Copy the whole text")
        copy.translatesAutoresizingMaskIntoConstraints = false
        let close = NSButton(title: "Close", target: window, action: #selector(NSWindow.performClose(_:)))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"
        close.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: frame)
        content.addSubview(scroll)
        content.addSubview(copy)
        content.addSubview(close)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: copy.topAnchor, constant: -8),
            copy.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            copy.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            close.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
        window.contentView = content
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // The window drawn by itself, for checking the rendering from a script.
    // No screen capture is involved, so no Screen Recording permission.
    func snapshot(to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fail("cannot render", code: 1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("cannot encode", code: 1) }
        do { try png.write(to: URL(fileURLWithPath: path)) }
        catch { fail("cannot write \(path): \(error.localizedDescription)", code: 1) }
    }

    @objc func copyAll() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(raw, forType: .string)
    }

    /// Set by the app: whether closing this window ends the process depends on
    /// what else is running.
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            if let f = self?.onClose { f() } else { exit(0) }
        }
    }
}

// Cmd-W, Cmd-C, Cmd-A and Cmd-Q only work with a menu bar to route them,
