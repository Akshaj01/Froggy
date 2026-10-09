import AppKit
import CoreText
import UniformTypeIdentifiers

@MainActor
enum PdfConverter {
    enum Failure: LocalizedError {
        case unsupported
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unsupported:
                "Can't make a PDF of that."
            case .unreadable:
                "Couldn't read that file."
            }
        }
    }

    static func makePDF(from file: URL, in folder: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) else {
            throw Failure.unreadable
        }
        guard !isDirectory.boolValue else {
            throw Failure.unsupported
        }

        let destination = SaveLocation.uniqueDestination(
            in: folder,
            baseName: file.deletingPathExtension().lastPathComponent,
            pathExtension: "pdf"
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let type = UTType(filenameExtension: file.pathExtension) ?? .data
        if type.conforms(to: .pdf) || file.pathExtension.lowercased() == "pdf" {
            try FileManager.default.copyItem(at: file, to: destination)
            return destination
        }
        if type.conforms(to: .image) {
            try writeImagePDF(from: file, to: destination)
            return destination
        }
        if documentType(for: file) != nil {
            try writeTextPDF(from: file, to: destination)
            return destination
        }
        if file.pathExtension.isEmpty {
            if (try? writeImagePDF(from: file, to: destination)) != nil {
                return destination
            }
            try writeTextPDF(from: file, to: destination)
            return destination
        }
        throw Failure.unsupported
    }

    private static func writeImagePDF(from file: URL, to destination: URL) throws {
        guard let image = NSImage(contentsOf: file) else {
            throw Failure.unreadable
        }
        let size = image.size
        guard size.width > 1, size.height > 1 else {
            throw Failure.unreadable
        }

        var page = CGRect(origin: .zero, size: size)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &page, nil) else {
            throw Failure.unreadable
        }

        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: page)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        do {
            try (data as Data).write(to: destination)
        } catch {
            throw Failure.unreadable
        }
    }

    private static func writeTextPDF(from file: URL, to destination: URL) throws {
        let docType = documentType(for: file) ?? .plain
        let loaded: NSAttributedString
        do {
            var attributes: NSDictionary?
            loaded = try NSAttributedString(
                url: file,
                options: [.documentType: docType],
                documentAttributes: &attributes
            )
        } catch {
            throw Failure.unreadable
        }

        let styled = NSMutableAttributedString(attributedString: loaded)
        let range = NSRange(location: 0, length: styled.length)
        if range.length == 0 {
            styled.replaceCharacters(in: range, with: " ")
        }
        let fullRange = NSRange(location: 0, length: styled.length)
        if docType == .plain {
            styled.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: fullRange)
        }
        styled.addAttribute(
            .foregroundColor,
            value: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
            range: fullRange
        )

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let textRect = pageRect.insetBy(dx: 54, dy: 54)
        let framesetter = CTFramesetterCreateWithAttributedString(styled)
        let data = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw Failure.unreadable
        }

        var index = 0
        let length = styled.length
        var pages = 0
        while index < length && pages < 500 {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(pageRect)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: index, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            pages += 1
            if visible.length <= 0 {
                break
            }
            index += visible.length
        }
        guard pages > 0 else {
            throw Failure.unreadable
        }
        context.closePDF()

        do {
            try (data as Data).write(to: destination)
        } catch {
            throw Failure.unreadable
        }
    }

    private static func documentType(for file: URL) -> NSAttributedString.DocumentType? {
        switch file.pathExtension.lowercased() {
        case "txt", "text", "md", "markdown":
            .plain
        case "html", "htm":
            .html
        case "rtf":
            .rtf
        case "rtfd":
            .rtfd
        case "doc":
            .docFormat
        case "docx":
            .officeOpenXML
        default:
            nil
        }
    }
}
