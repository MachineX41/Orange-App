import CoreGraphics
import Foundation
import PDFKit

public enum PDFToolkit: Sendable {
    private static let queue = DispatchQueue(label: "app.orange.studio.pdf")

    public static func pageCount(of url: URL) throws -> Int {
        try queue.sync {
            guard let document = PDFDocument(url: url) else {
                throw OrangeError.unreadable(url.lastPathComponent)
            }
            return document.pageCount
        }
    }

    public static func merge(urls: [URL], into directory: URL) throws -> URL {
        guard urls.count >= 2 else { throw OrangeError.unsupported("pdf") }
        return try queue.sync {
            let document = PDFDocument()
            for url in urls {
                guard let part = PDFDocument(url: url) else {
                    throw OrangeError.unreadable(url.lastPathComponent)
                }
                for index in 0..<part.pageCount {
                    guard let page = part.page(at: index)?.copy() as? PDFPage else { continue }
                    document.insert(page, at: document.pageCount)
                }
            }
            guard document.pageCount > 0 else { throw OrangeError.unreadable("pdf") }
            let destination = UniqueDestination.url(in: directory, baseName: "Merged", extension: "pdf")
            guard document.write(to: destination) else {
                throw OrangeError.writeFailed(destination.lastPathComponent)
            }
            return destination
        }
    }

    public static func split(url: URL, selection: String, into directory: URL) throws -> [URL] {
        try queue.sync {
            guard let source = PDFDocument(url: url) else {
                throw OrangeError.unreadable(url.lastPathComponent)
            }
            let ranges = try parsePageSelection(selection, pageCount: source.pageCount)
            let base = url.deletingPathExtension().lastPathComponent
            var outputs: [URL] = []
            for range in ranges {
                let document = PDFDocument()
                for pageNumber in range {
                    guard let page = source.page(at: pageNumber - 1)?.copy() as? PDFPage else { continue }
                    document.insert(page, at: document.pageCount)
                }
                let name = range.lowerBound == range.upperBound
                    ? "\(base) p\(range.lowerBound)"
                    : "\(base) p\(range.lowerBound)-\(range.upperBound)"
                let destination = UniqueDestination.url(in: directory, baseName: name, extension: "pdf")
                guard document.write(to: destination) else {
                    throw OrangeError.writeFailed(destination.lastPathComponent)
                }
                outputs.append(destination)
            }
            return outputs
        }
    }

    public static func imagesToPDF(sources: [URL], quality: Double, into directory: URL) throws -> URL {
        guard !sources.isEmpty else { throw OrangeError.empty }
        let transcoder = ImageTranscoder()
        var images: [CGImage] = []
        for source in sources {
            images.append(try transcoder.loadOriented(source))
        }
        let destination = UniqueDestination.url(in: directory, baseName: "Images", extension: "pdf")
        guard let consumer = CGDataConsumer(url: destination as CFURL) else {
            throw OrangeError.writeFailed(destination.lastPathComponent)
        }
        var firstBox = CGRect(x: 0, y: 0, width: images[0].width, height: images[0].height)
        guard let context = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else {
            throw OrangeError.writeFailed(destination.lastPathComponent)
        }
        for image in images {
            let box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.beginPDFPage([kCGPDFContextMediaBox: box] as CFDictionary)
            context.draw(image, in: box)
            context.endPDFPage()
        }
        context.closePDF()
        _ = quality
        return destination
    }

    public static func parsePageSelection(_ raw: String, pageCount: Int) throws -> [ClosedRange<Int>] {
        guard pageCount > 0 else { throw OrangeError.invalidPages }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty || text == "all" || text == "hepsi" {
            return [1...pageCount]
        }
        let pieces = text.split { $0 == "," || $0 == ";" }.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard !pieces.isEmpty else { throw OrangeError.invalidPages }
        var ranges: [ClosedRange<Int>] = []
        for piece in pieces {
            let ends = piece.split(separator: "-", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let lower: Int
            let upper: Int
            if ends.count == 1 {
                guard let value = Int(ends[0]) else { throw OrangeError.invalidPages }
                lower = value
                upper = value
            } else if ends.count == 2 {
                guard let start = Int(ends[0]), let end = Int(ends[1]) else { throw OrangeError.invalidPages }
                lower = start
                upper = end
            } else {
                throw OrangeError.invalidPages
            }
            guard lower >= 1, upper <= pageCount, lower <= upper else { throw OrangeError.invalidPages }
            ranges.append(lower...upper)
        }
        return ranges
    }
}
