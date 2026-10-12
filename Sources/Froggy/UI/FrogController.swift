import AppKit

/// Routes clicks on the frog to a PDF, a screenshot, or the save-folder menu.
@MainActor
final class FrogController: NSObject {
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
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: frogView)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let current = NSMenuItem(title: "Save to: \(SaveLocation.displayPath)", action: nil, keyEquivalent: "")
        current.isEnabled = false
        menu.addItem(current)
        menu.addItem(item("Change Save Folder…", action: #selector(changeFolder(_:))))
        menu.addItem(item("Open Save Folder", action: #selector(openFolder(_:)), key: "o"))

        if let last = SaveLocation.lastFile {
            menu.addItem(.separator())
            menu.addItem(item(last.lastPathComponent, action: #selector(showLastFile(_:))))
            menu.addItem(item("Undo Last Save", action: #selector(undoLastSave(_:)), key: "z"))
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit Froggy", action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        return menu
    }

    private func item(_ title: String, action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        item.isEnabled = true
        return item
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

    @objc private func showLastFile(_ sender: Any?) {
        guard let url = SaveLocation.lastFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func undoLastSave(_ sender: Any?) {
        do {
            let name = try SaveLocation.moveLastFileToTrash()
            hud.show("Moved \(name) to Trash", near: mouthPoint())
        } catch {
            hud.show(error.localizedDescription, near: mouthPoint())
        }
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
            let saved = try savePDF(of: file)
            noteSaved(saved, near: point)
        } catch {
            hud.show(error.localizedDescription, near: point)
        }
    }

    private func savePDF(of file: URL) throws -> URL {
        let folder = SaveLocation.folder
        let destination = SaveLocation.uniqueDestination(
            in: folder,
            baseName: file.deletingPathExtension().lastPathComponent,
            pathExtension: "pdf"
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try PdfConverter.makePDF(from: file, to: destination)
        return destination
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
                self?.noteSaved(destination, near: self?.mouthPoint() ?? .zero)
            } catch {
                self?.hud.show(error.localizedDescription, near: self?.mouthPoint() ?? .zero)
            }
        }
    }

    private func noteSaved(_ url: URL, near point: NSPoint) {
        SaveLocation.remember(url)
        hud.show("Saved \(url.lastPathComponent)", near: point)
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
