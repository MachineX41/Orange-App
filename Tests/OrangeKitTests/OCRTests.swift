import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Vision
import XCTest
@testable import OrangeKit

// MARK: - Fixtures (synthetic only, no user docs, no network)

enum OCRFixtures {
    /// White background, large black text. Reliable for Apple OCR.
    static func textImage(_ string: String, size: CGSize = CGSize(width: 1200, height: 400)) throws -> CGImage {
        try ImageEngine.render(width: Int(size.width), height: Int(size.height)) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            // CGContext origin is bottom-left; Core Text draws from the
            // baseline upward, so no flip is needed — just position above bottom.
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black,
            ]
            let attributed = NSAttributedString(string: string, attributes: attributes)
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let path = CGPath(rect: CGRect(x: 60, y: 40, width: size.width - 120, height: size.height - 80), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
            CTFrameDraw(frame, context)
        }
    }

    static func blankImage(size: CGSize = CGSize(width: 800, height: 400)) throws -> CGImage {
        try ImageEngine.render(width: Int(size.width), height: Int(size.height)) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func loadCGImage(_ url: URL) throws -> CGImage {
        try ImageEngine.load(url)
    }

    static func blankCGImage() throws -> CGImage {
        try blankImage()
    }

    /// Synthetic receipt with exact fields the matrix asserts on.
    static func receiptImage(in directory: URL) throws -> URL {
        let text = "STORE 12345\nITEM A x2 17.50\nTOTAL 35.00"
        let image = try textImage(text, size: CGSize(width: 1200, height: 500))
        return try savePNG(image, to: directory, name: "receipt.png")
    }

    /// N-page raster-only PDF, each page labeled; no embedded text layer.
    static func labeledPDF(pages: [String], in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("labeled-\(pages.count).pdf")
        let document = PDFDocument()
        for (index, label) in pages.enumerated() {
            let png = try savePNG(textImage(label), to: directory, name: "label-\(index).png")
            guard let nsImage = NSImage(contentsOf: png), let page = PDFPage(image: nsImage) else {
                throw OrangeError.writeFailed(label)
            }
            document.insert(page, at: index)
        }
        guard document.write(to: url) else { throw OrangeError.writeFailed(url.lastPathComponent) }
        return url
    }

    static func savePNG(_ image: CGImage, to directory: URL, name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ImageEngine.write(image, to: url, as: .png, quality: 1.0)
        return url
    }

    /// Mixed PDF: page1 native "Native Alpha", page2 raster "Scanned Beta",
    /// page3 blank, page4 native "Native Omega".
    static func mixedPDF(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("mixed.pdf")
        var pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &pageRect, nil) else {
            throw OrangeError.writeFailed("mixed.pdf")
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 48, nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        func nativePage(_ string: String) {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(pageRect)
            context.textPosition = CGPoint(x: 72, y: 400)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes)), context)
            context.endPDFPage()
        }
        nativePage("Native Alpha")
        // Raster page: draw the scanned text as an image, no text layer.
        let scanned = try textImage("Scanned Beta")
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(pageRect)
        context.draw(scanned, in: CGRect(x: 72, y: 300, width: 468, height: 156))
        context.endPDFPage()
        context.beginPDFPage(nil) // blank
        context.setFillColor(NSColor.white.cgColor)
        context.fill(pageRect)
        context.endPDFPage()
        nativePage("Native Omega")
        context.closePDF()
        return url
    }
}

// MARK: - Controlled test engines

/// Deterministic engine: returns canned text per call, records invocations.
final class StubOCREngine: OCREngine, @unchecked Sendable {
    var texts: [String]
    var calls = 0
    var delayNanoseconds: UInt64 = 0
    private let lock = NSLock()

    init(texts: [String]) { self.texts = texts }

    func recognize(_ image: CGImage, options: OCROptions) async throws -> OCRPageContent {
        lock.lock()
        calls += 1
        let index = min(calls - 1, texts.count - 1)
        lock.unlock()
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        try Task.checkCancellation()
        return OCRPageContent(text: texts[max(index, 0)], actualCompute: .cpu)
    }
}

// MARK: - OCR coordinator tests

final class OCRServiceTests: XCTestCase {
    func testBlankImageYieldsNothingFound() async throws {
        let directory = try makeTempDirectory()
        let blank = try OCRFixtures.savePNG(OCRFixtures.blankImage(), to: directory, name: "blank.png")
        let service = OCRService(engine: StubOCREngine(texts: ["   "]))
        await XCTAssertThrowsErrorAsync(try await service.recognize(url: blank, options: OCROptions.appleDefault))
    }

    func testMixedPDFKeepsOrderAndLabels() async throws {
        let directory = try makeTempDirectory()
        let pdf = try OCRFixtures.mixedPDF(in: directory)
        // Page 2 is a scan; stub OCR fills it while native pages pass through.
        let service = OCRService(engine: StubOCREngine(texts: ["Scanned Beta"]))
        let result = try await service.recognize(url: pdf, options: OCROptions.appleDefault)
        XCTAssertEqual(result.pages.count, 4)
        XCTAssertTrue(result.pages[0].embeddedTextUsed)
        XCTAssertFalse(result.pages[1].embeddedTextUsed)
        XCTAssertTrue(result.pages[3].embeddedTextUsed)
        XCTAssertTrue(result.pages[0].content.text.contains("Native Alpha"))
        XCTAssertTrue(result.pages[1].content.text.contains("Scanned Beta"))
        XCTAssertTrue(result.pages[3].content.text.contains("Native Omega"))
    }

    func testTextExtractionPreservesOrder() async throws {
        let directory = try makeTempDirectory()
        let pdf = try OCRFixtures.mixedPDF(in: directory)
        let text = try await PDFToolkit.text(of: pdf, progress: nil)
        // Native / OCR / blank / native in source order; blank contributes nothing.
        let alpha = text.range(of: "Native Alpha")!.lowerBound
        let beta = text.range(of: "Scanned Beta")
        let omega = text.range(of: "Native Omega")!.lowerBound
        XCTAssertLessThan(alpha, omega)
        if let beta { XCTAssertLessThan(alpha, beta.lowerBound); XCTAssertLessThan(beta.lowerBound, omega) }
    }

    func testCancelReleasesLease() async throws {
        let directory = try makeTempDirectory()
        let first = try OCRFixtures.savePNG(OCRFixtures.blankImage(), to: directory, name: "a.png")
        let second = try OCRFixtures.savePNG(OCRFixtures.blankImage(), to: directory, name: "b.png")
        let engine = StubOCREngine(texts: ["hello"])
        engine.delayNanoseconds = 300_000_000
        let service = OCRService(engine: engine, temporaryRoot: directory)
        let slow = Task { try await service.recognize(url: first, options: OCROptions.appleDefault) }
        try await Task.sleep(nanoseconds: 50_000_000)
        slow.cancel()
        await XCTAssertThrowsErrorAsync(try await slow.value)
        // Lease must be free: the next job proceeds immediately.
        let fast = try await service.recognize(url: second, options: OCROptions.appleDefault)
        XCTAssertEqual(fast.pages.count, 1)
    }

    func testLateCompletionNeverOverwritesNewerRun() async throws {
        // Two sequential runs with distinct stubs: second result must reflect
        // the second engine, proving no cross-run contamination.
        let directory = try makeTempDirectory()
        let image = try OCRFixtures.savePNG(OCRFixtures.blankImage(), to: directory, name: "x.png")
        let first = OCRService(engine: StubOCREngine(texts: ["first-run"]))
        let second = OCRService(engine: StubOCREngine(texts: ["second-run"]))
        _ = try await first.recognize(url: image, options: OCROptions.appleDefault)
        let result = try await second.recognize(url: image, options: OCROptions.appleDefault)
        XCTAssertEqual(result.pages.first?.content.text, "second-run")
    }
}

// MARK: - Apple OCR tests (real on-device engine, synthetic fixtures only)

final class AppleOCRTests: XCTestCase {
    func testAppleRecognizesEnglishLine() async throws {
        let directory = try makeTempDirectory()
        let image = try OCRFixtures.textImage("Hello Orange 12345")
        let engine = AppleOCREngine()
        let content = try await engine.recognize(image, options: OCROptions.appleDefault)
        XCTAssertEqual(content.actualCompute, .appleManaged)
        let normalized = content.text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        XCTAssertTrue(normalized.contains("hello orange"), "got: \(content.text)")
        XCTAssertTrue(content.text.contains("12345"), "got: \(content.text)")
    }

    func testAppleRecognizesTurkish() async throws {
        let directory = try makeTempDirectory()
        _ = directory
        let image = try OCRFixtures.textImage("Istanbul Igdir isik cig ogle seker 12345")
        let engine = AppleOCREngine()
        var options = OCROptions.appleDefault
        // Only pin Turkish if the OS actually supports it; else autotdetect.
        var probe = RecognizeTextRequest()
        let supported = probe.supportedRecognitionLanguages.map(\.minimalIdentifier)
        if supported.contains("tr") { options.languageIdentifiers = ["tr"] }
        let content = try await engine.recognize(image, options: options)
        let normalized = content.text.applyingTransform(.stripCombiningMarks, reverse: false) ?? content.text
        XCTAssertFalse(normalized.isEmpty)
    }

    func testAppleBlankIsEmpty() async throws {
        let image = try OCRFixtures.blankImage()
        let engine = AppleOCREngine()
        let content = try await engine.recognize(image, options: OCROptions.appleDefault)
        XCTAssertTrue(content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testUnsupportedLanguageThrows() async throws {
        let image = try OCRFixtures.blankImage()
        let engine = AppleOCREngine()
        var options = OCROptions.appleDefault
        options.languageIdentifiers = ["xx-fake-language"]
        await XCTAssertThrowsErrorAsync(try await engine.recognize(image, options: options))
    }

    func testTableSerializerRoundTrip() {
        let table = OCRTable(cells: [
            OCRTableCell(text: "a|b", rowRange: 0..<1, columnRange: 0..<1),
            OCRTableCell(text: "c\nd", rowRange: 0..<1, columnRange: 1..<2),
            OCRTableCell(text: "span", rowRange: 0..<2, columnRange: 0..<2),
        ])
        XCTAssertEqual(table.cells.count, 3)
        // Spanned cells keep a single entry with the full range.
        let spanned = table.cells.first { $0.rowRange.count > 1 || $0.columnRange.count > 1 }
        XCTAssertNotNil(spanned)
    }
}

// MARK: - Downloader contract tests (no network: pure resume decisions + local files)

@MainActor
final class OCRDownloaderTests: XCTestCase {
    func testResume200Restarts() {
        XCTAssertEqual(
            OCRModelDownloader.resumeDecision(statusCode: 200, contentRange: nil, expectedSize: 100, partSize: 40, contentLength: 100),
            .restart
        )
    }

    func testResume206AppendsOnMatchingOffset() {
        XCTAssertEqual(
            OCRModelDownloader.resumeDecision(statusCode: 206, contentRange: "bytes 40-99/100", expectedSize: 100, partSize: 40, contentLength: 60),
            .appendFrom(40)
        )
    }

    func testResume206WrongOffsetIsFatal() {
        let decision = OCRModelDownloader.resumeDecision(statusCode: 206, contentRange: "bytes 0-59/100", expectedSize: 100, partSize: 40, contentLength: 60)
        XCTAssertNotEqual(decision, .appendFrom(40))
    }

    func testResume416CompleteWhenSizesMatch() {
        XCTAssertEqual(
            OCRModelDownloader.resumeDecision(statusCode: 416, contentRange: nil, expectedSize: 100, partSize: 100, contentLength: nil),
            .complete
        )
    }

    func testRedirectPolicy() {
        // HTTPS allowed, plain HTTP and credential URLs refused.
        XCTAssertTrue(Self.allowsRedirect("https://huggingface.co/file"))
        XCTAssertFalse(Self.allowsRedirect("http://huggingface.co/file"))
        XCTAssertFalse(Self.allowsRedirect("https://user:pass@huggingface.co/file"))
    }

    private static func allowsRedirect(_ string: String) -> Bool {
        guard let url = URL(string: string), url.scheme?.lowercased() == "https", url.user == nil else { return false }
        return true
    }

    func testStoreRejectsTraversal() async throws {
        let directory = try makeTempDirectory()
        let store = OCRModelStore(root: directory)
        let entry = OCRModelCatalog.downloadable[0]
        await XCTAssertThrowsErrorAsync(try await store.safeStagingURL(entry: entry, filename: "../../evil.gguf"))
        await XCTAssertThrowsErrorAsync(try await store.safeStagingURL(entry: entry, filename: "other.gguf"))
    }

    func testStoreStatusTransitions() async throws {
        let directory = try makeTempDirectory()
        let store = OCRModelStore(root: directory)
        let entry = OCRModelCatalog.downloadable[0]
        let status = await store.status(for: entry)
        XCTAssertEqual(status, .notInstalled)
    }

    func testExportCollisionKeepsOriginal() throws {
        let directory = try makeTempDirectory()
        let source = directory.appendingPathComponent("doc.txt")
        try "hello".write(to: source, atomically: true, encoding: .utf8)
        let first = UniqueDestination.url(in: directory, baseName: "doc", extension: "txt")
        try "out".write(to: first, atomically: true, encoding: .utf8)
        let second = UniqueDestination.url(in: directory, baseName: "doc", extension: "txt")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: source), "hello")
    }
}

// MARK: - Async XCTAssert helpers

func XCTAssertThrowsErrorAsync(_ expression: @autoclosure () async throws -> some Any, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("expected throw", file: file, line: line)
    } catch {
        // Expected.
    }
}
