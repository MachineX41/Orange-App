import AppKit
import CoreGraphics
import Foundation
import PDFKit

public enum SplitMode: Hashable, Sendable {
    case everyPage
    case ranges(String)
    case chunks(Int)
}

public struct PageEdit: Hashable, Sendable {
    /// Zero-based index into the source document.
    public var source: Int
    public var rotation: Int

    public init(source: Int, rotation: Int = 0) {
        self.source = source
        self.rotation = rotation
    }
}

public enum PDFToolkit {
    static let lock = NSRecursiveLock()

    static func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw OrangeError.unreadable(url.lastPathComponent) }
        if document.isLocked { throw OrangeError.unreadable(url.lastPathComponent) }
        return document
    }

    static func write(_ document: PDFDocument, to url: URL, options: [PDFDocumentWriteOption: Any] = [:]) throws {
        guard document.write(to: url, withOptions: options) else { throw OrangeError.writeFailed(url.lastPathComponent) }
    }

    public static func pageCount(of url: URL) throws -> Int {
        try locked { try open(url).pageCount }
    }

    // MARK: Merge / split / organize

    public static func merge(urls: [URL], into directory: URL) throws -> URL {
        guard urls.count >= 2 else { throw OrangeError.unsupported("PDF") }
        return try locked {
            let output = PDFDocument()
            for url in urls {
                let part = try open(url)
                for index in 0..<part.pageCount {
                    guard let page = part.page(at: index)?.copy() as? PDFPage else { continue }
                    output.insert(page, at: output.pageCount)
                }
            }
            guard output.pageCount > 0 else { throw OrangeError.empty }
            let destination = UniqueDestination.url(
                in: directory,
                baseName: OutputLocation.baseName(urls[0], suffix: Lang.t("Merged", "Birleşik")),
                extension: "pdf"
            )
            try write(output, to: destination)
            return destination
        }
    }

    public static func split(url: URL, mode: SplitMode, into directory: URL) throws -> [URL] {
        try locked {
            let source = try open(url)
            let count = source.pageCount
            let ranges: [ClosedRange<Int>]
            switch mode {
            case .everyPage:
                ranges = (1...max(count, 1)).map { $0...$0 }
            case .ranges(let text):
                ranges = try parsePageSelection(text, pageCount: count)
            case .chunks(let size):
                guard size >= 1 else { throw OrangeError.invalidPages }
                ranges = stride(from: 1, through: count, by: size).map { $0...min($0 + size - 1, count) }
            }
            guard count > 0 else { throw OrangeError.empty }
            let base = url.deletingPathExtension().lastPathComponent
            let folder = UniqueDestination.folder(in: directory, baseName: "\(base) \(Lang.t("Pages", "Sayfalar"))")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return try ranges.map { range in
                let part = PDFDocument()
                for number in range {
                    guard let page = source.page(at: number - 1)?.copy() as? PDFPage else { continue }
                    part.insert(page, at: part.pageCount)
                }
                let label = range.count == 1 ? "p\(range.lowerBound)" : "p\(range.lowerBound)-\(range.upperBound)"
                let destination = UniqueDestination.url(in: folder, baseName: "\(base) \(label)", extension: "pdf")
                try write(part, to: destination)
                return destination
            }
        }
    }

    public static func organize(url: URL, pages: [PageEdit]) throws -> URL {
        guard !pages.isEmpty else { throw OrangeError.empty }
        return try locked {
            let source = try open(url)
            let output = PDFDocument()
            for edit in pages {
                guard let page = source.page(at: edit.source)?.copy() as? PDFPage else { continue }
                page.rotation = ((page.rotation + edit.rotation) % 360 + 360) % 360
                output.insert(page, at: output.pageCount)
            }
            let destination = UniqueDestination.url(
                in: OutputLocation.directory(beside: url),
                baseName: OutputLocation.baseName(url, suffix: Lang.t("Organized", "Düzenlenmiş")),
                extension: "pdf"
            )
            try write(output, to: destination)
            return destination
        }
    }

    public static func compress(url: URL) throws -> URL {
        try locked {
            let source = try open(url)
            let destination = UniqueDestination.url(
                in: OutputLocation.directory(beside: url),
                baseName: OutputLocation.baseName(url, suffix: Lang.t("Compressed", "Sıkıştırılmış")),
                extension: "pdf"
            )
            try write(source, to: destination, options: [
                .saveImagesAsJPEGOption: true,
                .optimizeImagesForScreenOption: true
            ])
            let before = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let after = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if before > 0, after >= before {
                try? FileManager.default.removeItem(at: destination)
                throw OrangeError.notSmaller
            }
            return destination
        }
    }

    // MARK: Rendering

    public static func pageImage(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let width = Int(((rotated ? bounds.height : bounds.width) * scale).rounded())
        let height = Int(((rotated ? bounds.width : bounds.height) * scale).rounded())
        guard width > 0, height > 0 else { return nil }
        return try? ImageEngine.render(width: width, height: height) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        }
    }

    public static func forEachPage(of url: URL, scale: CGFloat, _ body: (Int, CGImage) throws -> Void) throws {
        try locked {
            let document = try open(url)
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index), let image = pageImage(page, scale: scale) else { continue }
                try body(index, image)
            }
        }
    }

    public static func thumbnails(of url: URL, maxSide: CGFloat) throws -> [CGImage] {
        try locked {
            let document = try open(url)
            return (0..<document.pageCount).compactMap { index in
                guard let page = document.page(at: index) else { return nil }
                let bounds = page.bounds(for: .mediaBox)
                let scale = maxSide / max(bounds.width, bounds.height, 1)
                return pageImage(page, scale: scale)
            }
        }
    }

    public static func toImages(url: URL, format: ConvertTarget, scale: CGFloat = 2, progress: ProgressHandler? = nil) throws -> [URL] {
        let count = try pageCount(of: url)
        let base = url.deletingPathExtension().lastPathComponent
        let parent = OutputLocation.directory(beside: url)
        let folder = count > 1 ? UniqueDestination.folder(in: parent, baseName: "\(base) \(format.rawValue.uppercased())") : parent
        if count > 1 { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        var outputs: [URL] = []
        try forEachPage(of: url, scale: scale) { index, image in
            let name = count > 1 ? "\(base) p\(index + 1)" : base
            let destination = UniqueDestination.url(in: folder, baseName: name, extension: format.fileExtension)
            try ImageEngine.write(image, to: destination, as: format, quality: 0.9)
            outputs.append(destination)
            progress?(Double(index + 1) / Double(max(count, 1)))
        }
        return count > 1 ? [folder] : outputs
    }

    public static func text(of url: URL, progress: ProgressHandler? = nil) async throws -> String {
        let document = try locked { try open(url) }
        _ = document
        // Reuse the shared OCR path: native per-page text wins, scans get Apple OCR.
        // Lock scope stays inside OCRDocumentSource; no lock is held across await.
        let result = try await OCRService.shared.recognize(url: url, options: OCROptions.appleDefault, progress: progress)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw OrangeError.nothingFound }
        return result.pages
            .map { $0.content.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func attributedText(of url: URL, progress: ProgressHandler? = nil) async throws -> NSAttributedString {
        let output = NSMutableAttributedString()
        // Native rich text first, page by page (short lock each), scan pages via Apple OCR.
        let count = try locked { try open(url).pageCount }
        for index in 0..<count {
            try Task.checkCancellation()
            let native: NSAttributedString? = locked {
                guard let page = try? open(url).page(at: index) else { return nil }
                guard let attributed = page.attributedString, attributed.length > 0 else { return nil }
                return attributed
            }
            if let native, native.length > 0 {
                if output.length > 0 { output.append(NSAttributedString(string: "\n\n")) }
                output.append(native)
                progress?(Double(index + 1) / Double(max(count, 1)))
                continue
            }
            let source = OCRDocumentSource(url: url)
            let image: CGImage
            do {
                image = try autoreleasepool { try source.renderImage(pageIndex: index) }
            } catch {
                throw OrangeError.toolFailed("\(url.lastPathComponent) p\(index + 1): \(error.localizedDescription)")
            }
            let content = try await AppleOCREngine().recognize(image, options: OCROptions.appleDefault)
            if output.length > 0 { output.append(NSAttributedString(string: "\n\n")) }
            output.append(NSAttributedString(string: content.text))
            progress?(Double(index + 1) / Double(max(count, 1)))
        }
        if output.length > 0 { return output }
        throw OrangeError.nothingFound
    }

    // MARK: Building

    public static func imagesToPDF(sources: [URL], into directory: URL) throws -> URL {
        guard let first = sources.first else { throw OrangeError.empty }
        let images = try sources.map { try ImageEngine.load($0, maxPixel: 4096) }
        let destination = UniqueDestination.url(
            in: directory,
            baseName: sources.count == 1 ? OutputLocation.baseName(first) : Lang.t("Images", "Görseller"),
            extension: "pdf"
        )
        try ImageEngine.writePDF(images, to: destination)
        return destination
    }

    public static func parsePageSelection(_ raw: String, pageCount: Int) throws -> [ClosedRange<Int>] {
        guard pageCount > 0 else { throw OrangeError.invalidPages }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty || text == "all" || text == "hepsi" || text == "tümü" {
            return [1...pageCount]
        }
        let pieces = text.split { $0 == "," || $0 == ";" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else { throw OrangeError.invalidPages }
        return try pieces.map { piece in
            let ends = piece.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let lower: Int
            let upper: Int
            switch ends.count {
            case 1:
                guard let value = Int(ends[0]) else { throw OrangeError.invalidPages }
                lower = value
                upper = value
            case 2:
                guard let start = Int(ends[0]) else { throw OrangeError.invalidPages }
                let end = ends[1].isEmpty ? pageCount : Int(ends[1])
                guard let end else { throw OrangeError.invalidPages }
                lower = start
                upper = end
            default:
                throw OrangeError.invalidPages
            }
            guard lower >= 1, upper <= pageCount, lower <= upper else { throw OrangeError.invalidPages }
            return lower...upper
        }
    }
}
