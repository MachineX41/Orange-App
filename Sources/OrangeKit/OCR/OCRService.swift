import CoreGraphics
import Foundation

/// Coordinates OCR across images and PDFs. Serializes access to the shared
/// native helper through a process-wide FIFO lease so two recognize calls can
/// never enter the same helper concurrently. Pending work holds URLs and
/// options only — no bitmap is rendered before its turn.
public actor OCRService {
    public static let shared = OCRService()

    private var engine: any OCREngine
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var occupied = false
    private let defaultMaxSide: CGFloat = 4096

    public init(engine: any OCREngine = AppleOCREngine()) {
        self.engine = engine
    }

    /// Test seam: controlled engines plus an isolated store root.
    init(engine: any OCREngine, temporaryRoot: URL) {
        self.engine = engine
        _ = temporaryRoot
    }

    public func recognize(
        url: URL,
        options: OCROptions,
        onPage: (@Sendable (OCRPageResult) -> Void)? = nil,
        progress: ProgressHandler? = nil
    ) async throws -> OCRDocumentResult {
        try Task.checkCancellation()
        await acquire()
        defer { release() }
        let source = OCRDocumentSource(url: url)
        let count = try source.pageCount()
        var pages: [OCRPageResult] = []
        pages.reserveCapacity(count)
        for pageIndex in 0..<count {
            try Task.checkCancellation()
            let page = try await recognizePage(source: source, pageIndex: pageIndex, options: options)
            pages.append(page)
            onPage?(page)
            progress?(Double(pageIndex + 1) / Double(max(count, 1)))
        }
        let texts = pages.map { $0.content.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if texts.allSatisfy(\.isEmpty) { throw OrangeError.nothingFound }
        return OCRDocumentResult(pages: pages)
    }

    private func recognizePage(source: OCRDocumentSource, pageIndex: Int, options: OCROptions) async throws -> OCRPageResult {
        try Task.checkCancellation()
        let input: OCRDocumentSource.PageInput
        do {
            input = try autoreleasepool {
                try source.input(pageIndex: pageIndex, mode: options.mode, maxSide: defaultMaxSide)
            }
        } catch {
            throw pageError(source: source, pageIndex: pageIndex, underlying: error)
        }
        switch input {
        case .text(let text):
            let content = OCRPageContent(text: text, actualCompute: .appleManaged)
            return OCRPageResult(sourceURL: source.url, pageIndex: pageIndex, content: content, embeddedTextUsed: true)
        case .image(let image):
            let content: OCRPageContent
            do {
                content = try await engine.recognize(image, options: options)
            } catch {
                if error is CancellationError || (error as? OrangeError) == .cancelled { throw error }
                throw pageError(source: source, pageIndex: pageIndex, underlying: error)
            }
            return OCRPageResult(sourceURL: source.url, pageIndex: pageIndex, content: content)
        }
    }

    private func pageError(source: OCRDocumentSource, pageIndex: Int, underlying: Error) -> Error {
        if underlying is CancellationError || (underlying as? OrangeError) == .cancelled { return underlying }
        if let orange = underlying as? OrangeError { return orange }
        return OrangeError.toolFailed("\(source.url.lastPathComponent) p\(pageIndex + 1): \(underlying.localizedDescription)")
    }

    /// FIFO ticket lock; actor isolation makes the queue itself race-free.
    private func acquire() async {
        if !occupied {
            occupied = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            occupied = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
