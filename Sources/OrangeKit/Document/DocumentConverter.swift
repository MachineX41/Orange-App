import AppKit
import CoreText
import Foundation

public enum DocumentConverter {
    static func onMain<T>(_ body: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try body() }
        return try DispatchQueue.main.sync(execute: body)
    }

    public static func load(_ url: URL) async throws -> NSAttributedString {
        let ext = Catalog.canonicalExtension(url.pathExtension)
        switch ext {
        case "pdf":
            return try await PDFToolkit.attributedText(of: url)
        case "txt", "text", "md":
            let text = try readPlainText(url)
            return NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.black
            ])
        default:
            let type: NSAttributedString.DocumentType? = switch ext {
            case "rtf": .rtf
            case "docx": .officeOpenXML
            case "doc": .docFormat
            case "odt": .openDocument
            case "html": .html
            case "webarchive": .webArchive
            default: nil
            }
            var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
            if let type { options[.documentType] = type }
            if ext == "html" { options[.characterEncoding] = String.Encoding.utf8.rawValue }
            let needsMain = ext == "html" || ext == "webarchive"
            do {
                let load = { try NSAttributedString(url: url, options: options, documentAttributes: nil) }
                return needsMain ? try onMain(load) : try load()
            } catch {
                throw OrangeError.unreadable(url.lastPathComponent)
            }
        }
    }

    static func readPlainText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        for encoding in [String.Encoding.utf8, .utf16, .windowsCP1254, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        throw OrangeError.unreadable(url.lastPathComponent)
    }

    public static func convert(_ url: URL, to target: ConvertTarget) async throws -> URL {
        let text = try await load(url)
        let destination = UniqueDestination.url(
            in: OutputLocation.directory(beside: url),
            baseName: OutputLocation.baseName(url),
            extension: target.fileExtension
        )
        try write(text, to: destination, as: target)
        return destination
    }

    public static func write(_ text: NSAttributedString, to url: URL, as target: ConvertTarget) throws {
        let range = NSRange(location: 0, length: text.length)
        do {
            switch target {
            case .txt:
                try text.string.write(to: url, atomically: true, encoding: .utf8)
            case .pdf:
                try writePDF(text, to: url)
            case .docx, .rtf, .html, .odt:
                let type: NSAttributedString.DocumentType = switch target {
                case .docx: .officeOpenXML
                case .rtf: .rtf
                case .html: .html
                default: .openDocument
                }
                let data = try text.data(from: range, documentAttributes: [.documentType: type])
                try data.write(to: url, options: .atomic)
            default:
                throw OrangeError.unsupported(target.rawValue.uppercased())
            }
        } catch let error as OrangeError {
            throw error
        } catch {
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
    }

    /// Lays text out on A4 pages with CoreText.
    public static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        var page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let frameRect = page.insetBy(dx: 56, dy: 64)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &page, nil) else {
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
        let source = text.length > 0 ? text : NSAttributedString(string: " ")
        let framesetter = CTFramesetterCreateWithAttributedString(source as CFAttributedString)
        var location = 0
        repeat {
            context.beginPDFPage(nil)
            let path = CGPath(rect: frameRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guard visible.length > 0 else { break }
            location += visible.length
        } while location < source.length
        context.closePDF()
    }
}
