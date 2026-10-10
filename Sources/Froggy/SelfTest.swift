import AppKit
import PDFKit

@MainActor
enum FroggySelfTest {
    static func run() -> Int32 {
        _ = NSApplication.shared
        var failed = false

        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("PASS \(name)")
            } else {
                failed = true
                print("FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            }
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("froggy-self-test-\(UUID().uuidString)", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        } catch {
            print("FAIL setup — \(error.localizedDescription)")
            return 1
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "froggy-self-test"
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        suite.removePersistentDomain(forName: suiteName)
        let previous = SaveLocation.defaults
        SaveLocation.defaults = suite
        defer {
            SaveLocation.defaults = previous
            suite.removePersistentDomain(forName: suiteName)
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Froggy", isDirectory: true)
        check(
            "default folder is Documents/Froggy",
            SaveLocation.folder.standardizedFileURL.path == documents.standardizedFileURL.path
        )
        check("default folder was created", FileManager.default.fileExists(atPath: documents.path))

        let chosen = root.appendingPathComponent("chosen", isDirectory: true)
        SaveLocation.setFolder(chosen)
        check("save folder is remembered", SaveLocation.folder.standardizedFileURL.path == chosen.standardizedFileURL.path)
        check("save folder was created", FileManager.default.fileExists(atPath: chosen.path))
        check("display path is absolute for a temp folder", SaveLocation.displayPath == chosen.standardizedFileURL.path)

        let occupied = SaveLocation.uniqueDestination(in: output, baseName: "Notes", pathExtension: "pdf")
        FileManager.default.createFile(atPath: occupied.path, contents: Data("%PDF".utf8))
        let next = SaveLocation.uniqueDestination(in: output, baseName: "Notes", pathExtension: "pdf")
        check("names do not overwrite", next.lastPathComponent == "Notes 2.pdf")

        do {
            let png = root.appendingPathComponent("lily.png")
            try writeSamplePNG(to: png)
            let pdf = try PdfConverter.makePDF(from: png, in: output)
            let document = PDFDocument(url: pdf)
            check("image becomes a one-page PDF", document?.pageCount == 1, pdf.lastPathComponent)
            check("image pdf header", headerIsPDF(pdf))
        } catch {
            check("image becomes a one-page PDF", false, error.localizedDescription)
        }

        do {
            let text = root.appendingPathComponent("field-notes.txt")
            try "Hello from Froggy\n".write(to: text, atomically: true, encoding: .utf8)
            let pdf = try PdfConverter.makePDF(from: text, in: output)
            let document = PDFDocument(url: pdf)
            check("text becomes a PDF", document?.string?.contains("Hello from Froggy") == true)
        } catch {
            check("text becomes a PDF", false, error.localizedDescription)
        }

        do {
            let html = root.appendingPathComponent("page.html")
            try "<html><body><p>Hello frog</p></body></html>".write(to: html, atomically: true, encoding: .utf8)
            let pdf = try PdfConverter.makePDF(from: html, in: output)
            check("html becomes a PDF", PDFDocument(url: pdf)?.pageCount == 1)
        } catch {
            check("html becomes a PDF", false, error.localizedDescription)
        }

        do {
            let rtf = root.appendingPathComponent("letter.rtf")
            try "{\\rtf1\\ansi Hello rtf}".write(to: rtf, atomically: true, encoding: .utf8)
            let pdf = try PdfConverter.makePDF(from: rtf, in: output)
            check("rtf becomes a PDF", PDFDocument(url: pdf)?.string?.contains("Hello rtf") == true)
        } catch {
            check("rtf becomes a PDF", false, error.localizedDescription)
        }

        do {
            let source = output.appendingPathComponent("already.pdf")
            let document = PDFDocument()
            document.insert(PDFPage(), at: 0)
            document.write(to: source)
            let copied = try PdfConverter.makePDF(from: source, in: output)
            check("pdf is copied", copied.lastPathComponent == "already 2.pdf" && headerIsPDF(copied))
        } catch {
            check("pdf is copied", false, error.localizedDescription)
        }

        do {
            let folder = root.appendingPathComponent("not-a-file", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try PdfConverter.makePDF(from: folder, in: output)
            check("folder is rejected", false)
        } catch {
            check("folder is rejected", error.localizedDescription == "Can't make a PDF of that.")
        }

        do {
            let movie = root.appendingPathComponent("clip.mov")
            FileManager.default.createFile(atPath: movie.path, contents: Data("not a video".utf8))
            _ = try PdfConverter.makePDF(from: movie, in: output)
            check("video is rejected", false)
        } catch {
            check("video is rejected", error.localizedDescription == "Can't make a PDF of that.")
        }

        check("drag wins over a double-click", StatusBarController.gesture(clickCount: 2, dragged: true) == .drag)
        check("double-click screenshots", StatusBarController.gesture(clickCount: 2, dragged: false) == .screenshot)
        check("single click opens the menu", StatusBarController.gesture(clickCount: 1, dragged: false) == .menu)

        let controller = StatusBarController()
        check("frog button is installed", controller.hasFrogButton)
        let titles = controller.makeMenu().items.map(\.title).filter { !$0.isEmpty }
        check(
            "menu lists the save folder actions",
            titles == [
                "Save to: \(SaveLocation.displayPath)",
                "Change Save Folder…",
                "Open Save Folder",
                "Quit Froggy",
            ],
            titles.joined(separator: " | ")
        )

        let recent = output.appendingPathComponent("latest.pdf")
        FileManager.default.createFile(atPath: recent.path, contents: Data("%PDF".utf8))
        SaveLocation.remember(recent)
        let recentTitles = controller.makeMenu().items.map(\.title).filter { !$0.isEmpty }
        check(
            "menu shows the last file above undo",
            recentTitles == [
                "Save to: \(SaveLocation.displayPath)",
                "Change Save Folder…",
                "Open Save Folder",
                "latest.pdf",
                "Undo Last Save",
                "Quit Froggy",
            ],
            recentTitles.joined(separator: " | ")
        )
        do {
            let trashed = try SaveLocation.moveLastFileToTrash()
            check("undo moves the last file to trash", trashed == "latest.pdf" && SaveLocation.lastFile == nil && !FileManager.default.fileExists(atPath: recent.path))
        } catch {
            check("undo moves the last file to trash", false, error.localizedDescription)
        }

        print(failed ? "SELF-TEST FAILED" : "SELF-TEST PASSED")
        return failed ? 1 : 0
    }

    private static func headerIsPDF(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = try? handle.read(upToCount: 4)
        return header == Data("%PDF".utf8)
    }

    private static func writeSamplePNG(to url: URL) throws {
        let image = NSImage(size: NSSize(width: 40, height: 24), flipped: false) { rect in
            NSColor.systemGreen.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw PdfConverter.Failure.unreadable
        }
        try png.write(to: url)
    }
}
