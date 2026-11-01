import CoreGraphics
import Foundation
#if canImport(Metal)
import Metal
#endif
/// Coordinates OCR across images and PDFs. Serializes access to the shared
/// native helper through a process-wide FIFO lease so two recognize calls can
/// never enter the same helper concurrently. Pending work holds URLs and
/// options only — no bitmap is rendered before its turn.
public actor OCRService {
    public static let shared = OCRService()

    private var engine: any OCREngine
    private var nativeEngine: (any OCREngine)?
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

    public func configureNative(engine: any OCREngine) {
        nativeEngine = engine
    }

    /// Idle reaper hook: drops the warm helper after `timeout` of disuse.
    /// Called from AppDelegate's timer and memory-pressure handler.
    public func reapNativeIfIdle(timeout: TimeInterval = 60) async {
        if let native = nativeEngine as? NativeOCREngine {
            await native.reapIfIdle(timeout: timeout)
        }
    }

    public func handleMemoryPressure() async {
        if let native = nativeEngine as? NativeOCREngine {
            await native.handleMemoryPressure()
        }
    }

    public func recognize(
        url: URL,
        options: OCROptions,
        onPage: (@Sendable (OCRPageResult) -> Void)? = nil,
        progress: ProgressHandler? = nil
    ) async throws -> OCRDocumentResult {
        try Task.checkCancellation()
        try checkMemory(for: options)
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
            // Region pipeline: VLM + document mode splits the page via Apple
            // layout, asks the VLM per text region, crops figures to files.
            // Never asks the VLM about pixels (Marker/MinerU recipe).
            if options.modelID != .appleVision, options.mode == .document,
               let native = nativeEngine {
                let content = try await recognizeRegions(
                    image, source: source, pageIndex: pageIndex, options: options, native: native)
                return OCRPageResult(sourceURL: source.url, pageIndex: pageIndex, content: content)
            }
            let active = (options.modelID == .appleVision) ? engine : (nativeEngine ?? engine)
            let content: OCRPageContent
            do {
                content = try await active.recognize(image, options: options)
            } catch {
                if error is CancellationError || (error as? OrangeError) == .cancelled { throw error }
                throw pageError(source: source, pageIndex: pageIndex, underlying: error)
            }
            return OCRPageResult(sourceURL: source.url, pageIndex: pageIndex, content: content)
        }
    }

    /// Region-based document recognition: Apple layout -> VLM per text region.
    private func recognizeRegions(
        _ image: CGImage, source: OCRDocumentSource, pageIndex: Int,
        options: OCROptions, native: any OCREngine
    ) async throws -> OCRPageContent {
        let started = ContinuousClock.now
        // 1. Fast Apple layout pass for line boxes (text recognition is cheap;
        // we only need bounds, transcription comes from the VLM).
        var layoutOptions = OCROptions.appleDefault
        layoutOptions.mode = .text
        let layout = try await engine.recognize(image, options: layoutOptions)
        let lines = layout.blocks.filter { $0.bounds != .null }
        // 2. Group lines into row bands (reading order: top to bottom, left to right).
        let bands = groupLinesIntoBands(lines)
        // 3. Ask the VLM per band crop (text mode: terse trigger, no figure talk).
        var textOptions = options
        textOptions.mode = .text
        var regions: [OCRRegion] = []
        var markdownParts: [String] = []
        var textParts: [String] = []
        var truncated = false
        for band in bands {
            try Task.checkCancellation()
            guard let crop = crop(image, to: band) else { continue }
            let content = try await native.recognize(crop, options: textOptions)
            truncated = truncated || content.truncated
            let clean = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            regions.append(OCRRegion(kind: .text, bounds: band, text: clean))
            markdownParts.append(clean)
            textParts.append(clean)
        }
        // 4. Figures: large areas not covered by text -> crop to caller-provided dir.
        // (Extraction to files happens at export; here we record bounds only.)
        for box in figureBoxes(pageSize: CGSize(width: 1, height: 1), covered: bands) {
            regions.append(OCRRegion(kind: .figure, bounds: box))
        }
        regions.sort { readingOrder($0.bounds, $1.bounds) }
        let elapsed = ContinuousClock.now - started
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return OCRPageContent(
            text: textParts.joined(separator: "\n\n"),
            markdown: markdownParts.joined(separator: "\n\n"),
            blocks: layout.blocks,
            regions: regions,
            actualCompute: .metal,
            durationSeconds: seconds,
            truncated: truncated
        )
    }

    /// Groups line boxes into horizontal bands: lines whose vertical centers
    /// are within half a line-height merge; bands split on large gaps.
    private func groupLinesIntoBands(_ lines: [OCRTextBlock]) -> [CGRect] {
        let sorted = lines.map(\.bounds).sorted {
            if abs($0.midY - $1.midY) > 0.005 { return $0.midY < $1.midY }
            return $0.minX < $1.minX
        }
        var bands: [CGRect] = []
        for box in sorted {
            guard box != .null, box.width > 0.01, box.height > 0 else { continue }
            if let last = bands.last,
               abs(box.midY - last.midY) < max(box.height, last.height) * 0.9 {
                bands[bands.count - 1] = last.union(box)
            } else {
                bands.append(box)
            }
        }
        // Pad slightly so descenders/ascenders survive the crop.
        return bands.map { $0.insetBy(dx: -0.005, dy: -0.004) }
            .map { $0.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)) }
    }

    /// Gaps between text bands wider than 8% of page height are figure candidates.
    private func figureBoxes(pageSize: CGSize, covered: [CGRect]) -> [CGRect] {
        _ = pageSize
        let sorted = covered.sorted { $0.minY < $1.minY }
        var boxes: [CGRect] = []
        var cursor: CGFloat = 0
        for band in sorted {
            let gap = CGRect(x: 0, y: cursor, width: 1, height: band.minY - cursor)
            if gap.height > 0.08 { boxes.append(gap) }
            cursor = max(cursor, band.maxY)
        }
        let tail = CGRect(x: 0, y: cursor, width: 1, height: 1 - cursor)
        if tail.height > 0.08 { boxes.append(tail) }
        return boxes
    }

    private func readingOrder(_ a: CGRect, _ b: CGRect) -> Bool {
        if abs(a.midY - b.midY) > 0.01 { return a.midY < b.midY }
        return a.minX < b.minX
    }

    private func crop(_ image: CGImage, to normalized: CGRect) -> CGImage? {
        let rect = CGRect(
            x: normalized.minX * CGFloat(image.width),
            y: normalized.minY * CGFloat(image.height),
            width: normalized.width * CGFloat(image.width),
            height: normalized.height * CGFloat(image.height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard rect.width >= 16, rect.height >= 16 else { return nil }
        return image.cropping(to: rect)
    }

    /// Preflight memory gate: estimated working set vs half of physical RAM.
    /// Throws before any bitmap is rendered; the UI turns this into the
    /// explicit memory-confirmation prompt, never a silent downgrade.
    private func checkMemory(for options: OCROptions) throws {
        guard options.modelID != .appleVision,
              let entry = OCRModelCatalog.entry(for: options.modelID)
        else { return }
        let physical = ProcessInfo.processInfo.physicalMemory
        guard physical > 0 else { return }
        if entry.estimatedWorkingSetBytes > Int64(physical / 2) {
            throw OrangeError.toolFailed(
                "\(entry.displayName) needs ~\(entry.estimatedWorkingSetBytes / 1_000_000_000) GB but this Mac has \(physical / 1_000_000_000) GB RAM."
            )
        }
        if options.compute != .cpu, let metalBytes = metalRecommendedMax() {
            if entry.estimatedWorkingSetBytes > Int64(Double(metalBytes) * 0.8) {
                throw OrangeError.toolFailed(
                    "\(entry.displayName) exceeds 80% of the Metal budget on this Mac."
                )
            }
        }
    }

    private func metalRecommendedMax() -> UInt64? {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return device.recommendedMaxWorkingSetSize
        #else
        return nil
        #endif
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
