import AppKit

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
