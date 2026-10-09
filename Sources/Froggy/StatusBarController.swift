import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let tongue = TongueOverlay()
    private let hud = ConfirmationHUD()
    private let frogWindow: FrogBarWindow
    private let frogView: FrogFaceView
    private var menuWork: DispatchWorkItem?
    private var screenshotTask: Task<Void, Never>?

    override init() {
        frogView = FrogFaceView(frame: NSRect(origin: .zero, size: MenuBarSpot.frogSize))
        frogWindow = FrogBarWindow(contentRect: NSRect(origin: .zero, size: MenuBarSpot.frogSize))
        super.init()
        frogView.toolTip = "Drag the tongue onto a file for a PDF. Double-click to screenshot. Click to choose the save folder."
        frogView.setAccessibilityElement(true)
        frogView.setAccessibilityLabel("Froggy")
        frogView.onPress = { [weak self] in
            self?.frogPressed()
        }
        frogWindow.contentView = frogView
        frogWindow.title = "Froggy"
        placeFrog()
        frogWindow.orderFrontRegardless()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenChanged() {
        placeFrog()
    }

    private func placeFrog() {
        frogWindow.setFrame(MenuBarSpot.frame(), display: true)
    }

    private func frogPressed() {
        menuWork?.cancel()
        guard let window = frogView.window else { return }
        guard let start = NSApp.currentEvent, start.type == .leftMouseDown else { return }

        let origin = screenPoint(of: start, in: window)
        let clickCount = start.clickCount
        var dragged = false
        var latest = origin
        let trackingStarted = Date()

        while true {
            let event = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp, .mouseMoved],
                until: Date().addingTimeInterval(1.0 / 60.0),
                inMode: .eventTracking,
                dequeue: true
            )
            let buttonReleased: Bool
            if let event {
                latest = screenPoint(of: event, in: window)
                buttonReleased = event.type == .leftMouseUp
            } else {
                latest = NSEvent.mouseLocation
                let buttonIsUp = NSEvent.pressedMouseButtons & 0x1 == 0
                buttonReleased = buttonIsUp && Date().timeIntervalSince(trackingStarted) > 0.05
            }
            if hypot(latest.x - origin.x, latest.y - origin.y) >= 5 {
                dragged = true
            }
            if dragged {
                frogView.mouthOpen = true
                tongue.show(from: mouthPoint(), to: latest)
            }
            if buttonReleased {
                break
            }
        }

        tongue.hide()
        frogView.mouthOpen = false

        switch Self.gesture(clickCount: clickCount, dragged: dragged) {
        case .drag:
            grabFile(at: latest)
        case .screenshot:
            takeScreenshot()
        case .menu:
            scheduleMenu()
        }
    }

    enum Gesture {
        case drag
        case screenshot
        case menu
    }

    static func gesture(clickCount: Int, dragged: Bool) -> Gesture {
        if dragged {
            return .drag
        }
        if clickCount >= 2 {
            return .screenshot
        }
        return .menu
    }

    private func scheduleMenu() {
        menuWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.showMenu()
        }
        menuWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    private func showMenu() {
        let menu = makeMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: frogView)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let current = NSMenuItem(title: "Save to: \(SaveLocation.displayPath)", action: nil, keyEquivalent: "")
        current.isEnabled = false
        menu.addItem(current)

        let change = NSMenuItem(title: "Change Save Folder…", action: #selector(changeFolder(_:)), keyEquivalent: "")
        change.target = self
        change.isEnabled = true
        menu.addItem(change)

        let open = NSMenuItem(title: "Open Save Folder", action: #selector(openFolder(_:)), keyEquivalent: "o")
        open.target = self
        open.isEnabled = true
        menu.addItem(open)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Froggy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        quit.isEnabled = true
        menu.addItem(quit)
        return menu
    }

    var hasFrogButton: Bool {
        guard frogWindow.isVisible, frogView.accessibilityLabel() == "Froggy" else { return false }
        return NSScreen.screens.contains { screen in
            let areas = [screen.auxiliaryTopLeftArea, screen.auxiliaryTopRightArea].compactMap { $0 }
            if areas.isEmpty {
                return frogWindow.frame.maxY > screen.visibleFrame.maxY && screen.frame.intersects(frogWindow.frame)
            }
            return areas.contains { $0.intersects(frogWindow.frame) }
        }
    }

    @objc private func changeFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where Froggy saves PDFs and screenshots."
        panel.directoryURL = SaveLocation.folder
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        SaveLocation.setFolder(url)
        hud.show("Saving to \(SaveLocation.displayPath)", near: mouthPoint())
    }

    @objc private func openFolder(_ sender: Any?) {
        NSWorkspace.shared.open(SaveLocation.folder)
    }

    private func grabFile(at point: NSPoint) {
        guard FileResolver.accessGranted(prompt: true) else {
            hud.show("Allow Froggy in System Settings → Privacy & Security → Accessibility.", near: point)
            return
        }
        Thread.sleep(forTimeInterval: 0.03)
        guard let file = FileResolver.file(at: point) else {
            hud.show("No file under the tongue.", near: point)
            return
        }
        do {
            let saved = try PdfConverter.makePDF(from: file, in: SaveLocation.folder)
            hud.show("Saved \(saved.lastPathComponent)", near: point)
        } catch {
            hud.show(error.localizedDescription, near: point)
        }
    }

    private func takeScreenshot() {
        let screen = screenForFrog()
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let scale = screen.backingScaleFactor
        let destination = SaveLocation.uniqueDestination(
            in: SaveLocation.folder,
            baseName: screenshotBaseName(),
            pathExtension: "png"
        )
        screenshotTask?.cancel()
        screenshotTask = Task { [weak self] in
            do {
                try await ScreenCapture.savePNG(displayID: displayID, scale: scale, to: destination)
                self?.hud.show("Saved \(destination.lastPathComponent)", near: self?.mouthPoint() ?? .zero)
            } catch {
                self?.hud.show(error.localizedDescription, near: self?.mouthPoint() ?? .zero)
            }
        }
    }

    private func screenshotBaseName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date()))"
    }

    private func mouthPoint() -> NSPoint {
        let local = FrogIcon.mouthPoint(in: frogView.bounds)
        let inWindow = frogView.convert(local, to: nil)
        return frogWindow.convertToScreen(NSRect(origin: inWindow, size: .zero)).origin
    }

    private func screenForFrog() -> NSScreen {
        let point = mouthPoint()
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func screenPoint(of event: NSEvent, in window: NSWindow) -> NSPoint {
        window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
    }
}

private enum MenuBarSpot {
    static let frogSize = NSSize(width: 22, height: 22)

    static func frame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = frogSize
        let right = screen.auxiliaryTopRightArea
        let left = screen.auxiliaryTopLeftArea
        let menuBar = right ?? left ?? NSRect(
            x: screen.frame.maxX - 160,
            y: screen.visibleFrame.maxY,
            width: 160,
            height: max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        )
        let extrasMinX = leftmostMenuExtraX(on: screen, in: right)
        var x = (extrasMinX ?? menuBar.maxX) - size.width - 3
        var band = menuBar
        if let right, x < right.minX + 1 {
            if let left {
                band = left
                x = left.maxX - size.width - 4
            } else {
                x = right.minX + 2
            }
        }
        x = min(max(x, band.minX + 1), band.maxX - size.width - 1)
        let y = band.midY - size.height / 2
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func leftmostMenuExtraX(on screen: NSScreen, in rightArea: NSRect?) -> CGFloat? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let primaryHeight = (NSScreen.screens.first?.frame.maxY) ?? screen.frame.maxY
        var minX: CGFloat?
        for window in info {
            let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t ?? 0
            if ownerPID == getpid() { continue }
            guard let bounds = cgRect(window[kCGWindowBounds as String]) else { continue }
            let cocoa = NSRect(
                x: bounds.minX,
                y: primaryHeight - bounds.maxY,
                width: bounds.width,
                height: bounds.height
            )
            guard cocoa.width < 200, cocoa.height < 80, cocoa.maxY > screen.visibleFrame.maxY else { continue }
            if let rightArea, cocoa.maxX < rightArea.minX { continue }
            minX = min(minX ?? cocoa.minX, cocoa.minX)
        }
        return minX
    }

    private static func cgRect(_ value: Any?) -> NSRect? {
        guard let bounds = value as? [String: Any] else { return nil }
        func number(_ key: String) -> CGFloat? {
            (bounds[key] as? NSNumber).map { CGFloat($0.doubleValue) }
        }
        guard let x = number("X"), let y = number("Y"), let width = number("Width"), let height = number("Height") else {
            return nil
        }
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private final class FrogBarWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FrogFaceView: NSView {
    var onPress: (() -> Void)?
    var mouthOpen = false {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onPress?()
    }

    override func draw(_ dirtyRect: NSRect) {
        FrogIcon.draw(mouthOpen: mouthOpen, in: bounds)
    }
}

private enum FrogIcon {
    /// Bottom lip of the open mouth, in the 22-point design space.
    private static let mouthDesign = NSPoint(x: 11, y: 3.0)

    static func mouthPoint(in bounds: NSRect) -> NSPoint {
        let scaleX = bounds.width / 22
        let scaleY = bounds.height / 22
        return NSPoint(
            x: bounds.minX + mouthDesign.x * scaleX,
            y: bounds.minY + mouthDesign.y * scaleY
        )
    }

    static func draw(mouthOpen: Bool, in rect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 22, yBy: rect.height / 22)
        transform.concat()

        let green = NSColor(srgbRed: 0.45, green: 0.86, blue: 0.48, alpha: 1)
        let outline = NSColor(srgbRed: 0.16, green: 0.45, blue: 0.28, alpha: 1)
        let belly = NSColor(srgbRed: 0.86, green: 0.97, blue: 0.62, alpha: 1)
        let blush = NSColor(srgbRed: 1, green: 0.55, blue: 0.66, alpha: 0.85)

        outline.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2.6, y: 0.6, width: 16.8, height: 14.4)).fill()
        green.setFill()
        NSBezierPath(ovalIn: NSRect(x: 3.5, y: 1.5, width: 15.0, height: 12.6)).fill()
        belly.setFill()
        NSBezierPath(ovalIn: NSRect(x: 7.6, y: 2.2, width: 6.8, height: 5.2)).fill()
        blush.setFill()
        NSBezierPath(ovalIn: NSRect(x: 4.0, y: 5.6, width: 3.1, height: 1.8)).fill()
        NSBezierPath(ovalIn: NSRect(x: 14.9, y: 5.6, width: 3.1, height: 1.8)).fill()

        func eye(at x: CGFloat) {
            outline.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: 10.6, width: 8.4, height: 9.0)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: x + 0.7, y: 11.3, width: 7.0, height: 7.6)).fill()
            NSColor(srgbRed: 0.12, green: 0.16, blue: 0.18, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: x + 2.15, y: 12.5, width: 3.7, height: 4.3)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: x + 2.45, y: 15.0, width: 1.7, height: 1.7)).fill()
            NSBezierPath(ovalIn: NSRect(x: x + 4.35, y: 13.3, width: 0.75, height: 0.75)).fill()
        }
        eye(at: 1.7)
        eye(at: 11.9)

        if mouthOpen {
            NSColor(srgbRed: 0.72, green: 0.16, blue: 0.32, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 7.4, y: 3.0, width: 7.2, height: 3.5)).fill()
        } else {
            let smile = NSBezierPath()
            smile.lineWidth = 1.05
            smile.lineCapStyle = .round
            outline.setStroke()
            smile.move(to: NSPoint(x: 8.7, y: 5.15))
            smile.curve(
                to: NSPoint(x: 13.3, y: 5.15),
                controlPoint1: NSPoint(x: 9.8, y: 3.85),
                controlPoint2: NSPoint(x: 12.2, y: 3.85)
            )
            smile.stroke()
        }

        context.restoreGraphicsState()
    }
}
