import AppKit

@MainActor
final class TongueOverlay {
    private var window: OverlayWindow?
    private var canvas: TongueCanvas?

    func show(from start: NSPoint, to end: NSPoint) {
        let window = ensureWindow()
        guard let canvas else { return }

        let frame = Self.unionFrame()
        if window.frame != frame {
            window.setFrame(frame, display: false)
            canvas.frame = NSRect(origin: .zero, size: frame.size)
        }
        canvas.start = convert(start, in: frame)
        canvas.end = convert(end, in: frame)
        canvas.needsDisplay = true
        window.orderFrontRegardless()
        window.display()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func ensureWindow() -> OverlayWindow {
        if let window {
            return window
        }
        let created = makeWindow()
        window = created
        return created
    }

    private func makeWindow() -> OverlayWindow {
        let frame = Self.unionFrame()
        let window = OverlayWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let canvas = TongueCanvas(frame: NSRect(origin: .zero, size: frame.size))
        self.canvas = canvas
        window.contentView = canvas
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.sharingType = .none
        return window
    }

    private func convert(_ point: NSPoint, in frame: NSRect) -> NSPoint {
        NSPoint(x: point.x - frame.minX, y: point.y - frame.minY)
    }

    private static func unionFrame() -> NSRect {
        NSScreen.screens.reduce(NSRect.null) { partial, screen in
            partial.union(screen.frame)
        }
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TongueCanvas: NSView {
    var start: NSPoint = .zero
    var end: NSPoint = .zero

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }

        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux
        let stretch = min(length / 320, 1)
        let baseWidth: CGFloat = 8.5
        let tipWidth = max(3.5, baseWidth - stretch * 4.5)

        func shifted(_ origin: NSPoint, along: CGFloat, side: CGFloat) -> NSPoint {
            NSPoint(x: origin.x + ux * along + px * side, y: origin.y + uy * along + py * side)
        }

        let body = tongueShape(
            from: start,
            to: end,
            baseWidth: baseWidth,
            tipWidth: tipWidth,
            shifted: shifted
        )
        NSColor(srgbRed: 0.84, green: 0.18, blue: 0.32, alpha: 0.96).setFill()
        body.fill()

        let sheen = tongueShape(
            from: shifted(start, along: length * 0.04, side: baseWidth * 0.08),
            to: shifted(end, along: -tipWidth * 0.35, side: tipWidth * 0.06),
            baseWidth: baseWidth * 0.34,
            tipWidth: tipWidth * 0.28,
            shifted: shifted
        )
        NSColor(srgbRed: 1, green: 0.62, blue: 0.70, alpha: 0.85).setFill()
        sheen.fill()
    }

    private func tongueShape(
        from start: NSPoint,
        to end: NSPoint,
        baseWidth: CGFloat,
        tipWidth: CGFloat,
        shifted: (NSPoint, CGFloat, CGFloat) -> NSPoint
    ) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: shifted(start, 0, baseWidth / 2))
        path.line(to: shifted(end, 0, tipWidth / 2))
        path.curve(
            to: shifted(end, 0, -tipWidth / 2),
            controlPoint1: shifted(end, tipWidth * 0.9, tipWidth / 2),
            controlPoint2: shifted(end, tipWidth * 0.9, -tipWidth / 2)
        )
        path.line(to: shifted(start, 0, -baseWidth / 2))
        path.curve(
            to: shifted(start, 0, baseWidth / 2),
            controlPoint1: shifted(start, -baseWidth * 0.12, -baseWidth / 2),
            controlPoint2: shifted(start, -baseWidth * 0.12, baseWidth / 2)
        )
        path.close()
        return path
    }
}

@MainActor
final class ConfirmationHUD {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ message: String, near anchor: NSPoint) {
        hideWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let background = panel.contentView, let label = background.viewWithTag(1) as? NSTextField else { return }

        label.stringValue = message
        let textWidth = min(max(label.intrinsicContentSize.width, 120), 380)
        let width = textWidth + 28
        let height: CGFloat = 36
        var origin = NSPoint(x: anchor.x - width / 2, y: anchor.y - 52)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - height - 8)
        }

        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: false)
        background.frame = NSRect(origin: .zero, size: panel.frame.size)
        label.frame = NSRect(x: 14, y: 8, width: textWidth, height: 20)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak panel] in
            panel?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .none

        let background = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "")
        label.tag = 1
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        background.addSubview(label)
        panel.contentView = background
        return panel
    }
}
