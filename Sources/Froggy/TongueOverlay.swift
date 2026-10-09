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
        guard start != .zero || end != .zero else { return }
        let path = NSBezierPath()
        path.move(to: start)
        let midpoint = NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let length = max(hypot(end.x - start.x, end.y - start.y), 1)
        let sag = min(70, length * 0.22)
        let control = NSPoint(x: midpoint.x, y: midpoint.y - sag)
        path.curve(to: end, controlPoint1: control, controlPoint2: control)
        path.lineCapStyle = .round

        NSColor(srgbRed: 0.55, green: 0.08, blue: 0.16, alpha: 0.35).setStroke()
        path.lineWidth = 11
        path.stroke()

        NSColor(srgbRed: 0.96, green: 0.38, blue: 0.48, alpha: 0.96).setStroke()
        path.lineWidth = 7
        path.stroke()

        NSColor(srgbRed: 1, green: 0.78, blue: 0.82, alpha: 0.7).setStroke()
        path.lineWidth = 1.6
        path.stroke()
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
