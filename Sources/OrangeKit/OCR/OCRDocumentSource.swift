import CoreGraphics
import Foundation
import PDFKit

/// Extracts one page at a time from a PDF: native text when present, otherwise a
/// bounded CGImage snapshot. PDFKit access stays inside short synchronous lock
/// closures — no lock is ever held across an await.
public struct OCRDocumentSource: Sendable {
    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    public var isPDF: Bool { Catalog.kind(for: url) == .pdf }

    public func pageCount() throws -> Int {
        if isPDF {
            try PDFToolkit.locked { try PDFToolkit.open(url).pageCount }
        } else {
            1
        }
    }

    public enum PageInput: Sendable {
        case text(String)
        case image(CGImage)
    }

    /// Native (embedded) text for `pageIndex`, or nil when the page is a scan.
    /// Lock scope covers PDFKit only; rendering happens after release.
    public func nativeText(pageIndex: Int) throws -> (String, NSAttributedString?)? {
        guard isPDF else { return nil }
        return try PDFToolkit.locked {
            let document = try PDFToolkit.open(url)
            guard let page = document.page(at: pageIndex) else {
                throw OrangeError.unreadable("\(url.lastPathComponent) p\(pageIndex + 1)")
            }
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return (text, page.attributedString)
        }
    }

    /// Renders a single page snapshot. Scale is capped so the long edge stays
    /// within `maxSide` pixels, honoring the plan's 4096px OCR ceiling.
    public func renderImage(pageIndex: Int, maxSide: CGFloat = 4096) throws -> CGImage {
        if isPDF {
            let captured: (CGFloat, CGFloat, Int) = try PDFToolkit.locked {
                let document = try PDFToolkit.open(url)
                guard let page = document.page(at: pageIndex) else {
                    throw OrangeError.unreadable("\(url.lastPathComponent) p\(pageIndex + 1)")
                }
                let bounds = page.bounds(for: .mediaBox)
                let rotated = page.rotation % 180 != 0
                let width = rotated ? bounds.height : bounds.width
                let height = rotated ? bounds.width : bounds.height
                return (width, height, page.rotation)
            }
            let longest = max(captured.0, captured.1, 1)
            // Rotation-aware: pageImage derives its own scale from the page bounds.
            let scale = min(3, maxSide / longest)
            let rendered: CGImage? = PDFToolkit.locked {
                guard let document = try? PDFToolkit.open(url),
                      let page = document.page(at: pageIndex)
                else { return nil }
                return PDFToolkit.pageImage(page, scale: scale)
            }
            guard let rendered else {
                throw OrangeError.unreadable("\(url.lastPathComponent) p\(pageIndex + 1)")
            }
            return rendered
        }
        return try ImageEngine.load(url, maxPixel: Int(maxSide))
    }

    /// Page input for text mode: native text wins, scans fall back to rendering.
    /// Document mode always renders, so structure survives on mixed pages too.
    public func input(pageIndex: Int, mode: OCRMode, maxSide: CGFloat = 4096) throws -> PageInput {
        if mode == .document {
            return try .image(renderImage(pageIndex: pageIndex, maxSide: maxSide))
        }
        if let (text, _) = try nativeText(pageIndex: pageIndex) {
            return .text(text)
        }
        return try .image(renderImage(pageIndex: pageIndex, maxSide: maxSide))
    }
}
