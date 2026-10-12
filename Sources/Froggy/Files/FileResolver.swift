import AppKit
import ApplicationServices

enum FileResolver {
    static func accessGranted(prompt: Bool) -> Bool {
        guard prompt else {
            return AXIsProcessTrusted()
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func file(at cocoaPoint: NSPoint) -> URL? {
        guard let element = element(at: cocoaPoint) else { return nil }
        return resolve(element)
    }

    private static func element(at cocoaPoint: NSPoint) -> AXUIElement? {
        guard let screen = NSScreen.screens.first else { return nil }
        let axPoint = CGPoint(x: cocoaPoint.x, y: screen.frame.maxY - cocoaPoint.y)
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(axPoint.x),
            Float(axPoint.y),
            &element
        )
        guard result == .success else { return nil }
        return element
    }

    /// The hit element is the file under the cursor. Ancestor URLs cover document
    /// windows, and a filename plus the Finder folder covers icons that only expose a title.
    private static func resolve(_ start: AXUIElement) -> URL? {
        guard pid(of: start) != getpid() else { return nil }

        if let file = fileURL(on: start) ?? fileURL(among: limitedChildren(of: start)) {
            return file
        }
        if directoryURL(on: start) != nil {
            return directoryURL(on: start)
        }

        var names = labels(on: start)
        for child in limitedChildren(of: start) {
            names.append(contentsOf: labels(on: child))
        }

        var folders: [URL] = []
        var current: AXUIElement? = parent(of: start)
        var depth = 0
        while let element = current, depth < 14 {
            depth += 1
            if pid(of: element) != getpid() {
                if let file = fileURL(on: element) {
                    return file
                }
                if let folder = directoryURL(on: element) {
                    folders.append(folder)
                }
            }
            current = parent(of: element)
        }

        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        folders.append(desktop)

        for name in names {
            for candidate in nameCandidates(name) {
                for folder in folders {
                    let url = folder.appendingPathComponent(candidate)
                    if isFile(url) {
                        return url
                    }
                }
            }
        }
        return nil
    }

    private static func fileURL(among elements: [AXUIElement]) -> URL? {
        elements.compactMap { fileURL(on: $0) }.first
    }

    private static func fileURL(on element: AXUIElement) -> URL? {
        urls(on: element).first { isFile($0) }
    }

    private static func directoryURL(on element: AXUIElement) -> URL? {
        urls(on: element).first { isDirectory($0) }
    }

    private static func urls(on element: AXUIElement) -> [URL] {
        var found: [URL] = []
        if let value = copyAttribute(element, kAXURLAttribute as CFString), let url = value as? URL {
            found.append(url)
        }
        if let document = stringAttribute(element, kAXDocumentAttribute as CFString),
           let url = url(from: document) {
            found.append(url)
        }
        return found
    }

    private static func labels(on element: AXUIElement) -> [String] {
        [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].compactMap { attribute in
            stringAttribute(element, attribute as CFString)
        }
    }

    private static func limitedChildren(of element: AXUIElement) -> [AXUIElement] {
        let kids = children(of: element)
        return kids.count <= 6 ? kids : []
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        return value as? String
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(element, kAXChildrenAttribute as CFString) else { return [] }
        let items = value as? [AnyObject] ?? []
        return items.compactMap { item in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            return (item as! AXUIElement)
        }
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(element, kAXParentAttribute as CFString) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func pid(of element: AXUIElement) -> pid_t {
        var processID: pid_t = 0
        AXUIElementGetPid(element, &processID)
        return processID
    }

    private static func url(from string: String) -> URL? {
        if let url = URL(string: string), url.isFileURL {
            return url
        }
        if string.hasPrefix("/") {
            return URL(fileURLWithPath: string)
        }
        let encoded = string.replacingOccurrences(of: " ", with: "%20")
        if let url = URL(string: encoded), url.isFileURL {
            return url
        }
        return nil
    }

    private static func nameCandidates(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 400, !trimmed.contains("/") else { return [] }
        var results = [trimmed]
        if let firstLine = trimmed.split(whereSeparator: \.isNewline).first {
            let line = String(firstLine).trimmingCharacters(in: .whitespaces)
            if line != trimmed {
                results.append(line)
            }
        }
        return results
    }

    private static func isFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
