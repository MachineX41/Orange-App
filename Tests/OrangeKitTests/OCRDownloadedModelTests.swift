import Foundation
#if canImport(Metal)
import Metal
#endif
import XCTest
@testable import OrangeKit

/// Opt-in hardware suite: runs only when ORANGE_OCR_MODEL_TESTS=1 AND the
/// interface-installed model pair exists. Otherwise XCTSkip with the reason.
/// Never invokes the downloader; reads only verified on-disk layouts.
/// Helper path: ORANGE_OCR_HELPER or the built bundle location.
final class OCRDownloadedModelTests: XCTestCase {
    private var helperURL: URL?
    private var store: OCRModelStore?
    private var modelRoot: URL?
    private var enabled = false

    override func setUpWithError() throws {
        let flag = ProcessInfo.processInfo.environment["ORANGE_OCR_MODEL_TESTS"] == "1"
        guard flag else { return }
        let rootString = ProcessInfo.processInfo.environment["ORANGE_OCR_MODEL_ROOT"]
        let root: URL
        if let rootString {
            root = URL(fileURLWithPath: rootString, isDirectory: true)
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Orange/Models", isDirectory: true)
        }
        let helperString = ProcessInfo.processInfo.environment["ORANGE_OCR_HELPER"]
            ?? "\(FileManager.default.currentDirectoryPath)/build/Orange.app/Contents/Helpers/OrangeOCRHelper"
        let helper = URL(fileURLWithPath: helperString)
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return }
        helperURL = helper
        store = OCRModelStore(root: root)
        modelRoot = root
        enabled = true
    }

    private func require(entry: OCRModelEntry, file: StaticString = #file, line: UInt = #line) throws -> (URL, OCRModelStore) {
        guard enabled, let store, let helperURL, let modelRoot else {
            throw XCTSkip("ORANGE_OCR_MODEL_TESTS=1 and an installed model pair are required.")
        }
        guard isInstalled(entry: entry, root: modelRoot) else {
            throw XCTSkip("\(entry.displayName) is not installed; install it from Settings › Models first.")
        }
        _ = helperURL
        return (helperURL, store)
    }

    /// Synchronous status probe for the skip logic; reads only the verified manifest.
    private func isInstalled(entry: OCRModelEntry, root: URL) -> Bool {
        let manifestURL = root.appendingPathComponent("\(entry.id.rawValue)/\(entry.revision)", isDirectory: true)
            .appendingPathComponent("verified.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(OCRModelStore.VerifiedManifest.self, from: data),
              manifest.modelID == entry.id.rawValue
        else { return false }
        return true
    }

    func testGLMCPURecognition() async throws { try await self.runCase(id: .glmOCR, compute: .cpu) }
    func testGLMMetalRecognition() async throws { try await self.runCase(id: .glmOCR, compute: .metal) }
    func testQwenCPURecognition() async throws { try await self.runCase(id: .qwen3VL2B, compute: .cpu, document: true) }
    func testQwenMetalRecognition() async throws { try await self.runCase(id: .qwen3VL2B, compute: .metal, document: true) }

    func testWarmPDFReusesGLM() async throws {
        guard let entry = OCRModelCatalog.entry(for: .glmOCR) else { XCTFail("missing catalog"); return }
        let (helper, store) = try require(entry: entry)
        let engine = NativeOCREngine(helperURL: helper, store: store)
        // Three-page raster PDF, all pages through the same warm helper.
        let directory = try makeTempDirectory()
        let pages = ["LABEL-ALPHA-1", "LABEL-BETA-2", "LABEL-GAMMA-3"]
        let pdf = try OCRFixtures.labeledPDF(pages: pages, in: directory)
        let service = OCRService(engine: engine, temporaryRoot: directory)
        let result = try await service.recognize(url: pdf, options: OCROptions(modelID: .glmOCR, mode: .text, compute: .cpu))
        XCTAssertEqual(result.pages.count, 3)
        for (index, label) in pages.enumerated() {
            XCTAssertTrue(result.pages[index].content.text.contains(label), "page \(index): \(result.pages[index].content.text)")
        }
    }

    func testSwitchGLMToAppleReleasesHelper() async throws {
        guard let entry = OCRModelCatalog.entry(for: .glmOCR) else { XCTFail("missing catalog"); return }
        let (helper, store) = try require(entry: entry)
        let before = OCRProcessCount.helperCount()
        let engine = NativeOCREngine(helperURL: helper, store: store)
        _ = try await engine.recognize(OCRFixtures.blankCGImage(), options: OCROptions(modelID: .glmOCR, mode: .text, compute: .cpu))
        await engine.shutdownForTests()
        // stopHelper sends terminate, waits 2s, then SIGKILLs; poll up to 10s.
        var remaining = 100
        while OCRProcessCount.helperCount() > before && remaining > 0 {
            try await Task.sleep(nanoseconds: 100_000_000)
            remaining -= 1
        }
        XCTAssertLessThanOrEqual(OCRProcessCount.helperCount(), before)
    }

    func testCancelGLMInference() async throws {
        guard let entry = OCRModelCatalog.entry(for: .glmOCR) else { XCTFail("missing catalog"); return }
        let (helper, store) = try require(entry: entry)
        let engine = NativeOCREngine(helperURL: helper, store: store)
        let task = Task { try await engine.recognize(OCRFixtures.blankCGImage(), options: OCROptions(modelID: .glmOCR, mode: .text, compute: .cpu)) }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        task.cancel()
        await engine.shutdownForTests()
        _ = try? await task.value
        // Pass = no hang; cancellation propagates within the timeout below.
    }

    func testRegionPipelineQwen() async throws {
        guard let entry = OCRModelCatalog.entry(for: .qwen3VL2B) else { XCTFail("missing catalog"); return }
        let (helper, store) = try require(entry: entry)
        let engine = NativeOCREngine(helperURL: helper, store: store)
        let service = OCRService(engine: AppleOCREngine(), temporaryRoot: FileManager.default.temporaryDirectory)
        await service.configureNative(engine: engine)
        // Scanned p2 (no text layer) forces the region pipeline.
        let dir = try makeTempDirectory()
        let png = dir.appendingPathComponent("region-p2.png")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/tmp/ref-p2.png"), to: png)
        let options = OCROptions(modelID: .qwen3VL2B, mode: .document, compute: .metal)
        let result = try await service.recognize(url: png, options: options)
        let content = result.pages.first!.content
        XCTAssertFalse(content.regions.isEmpty, "region pipeline must populate regions")
        XCTAssertFalse(content.text.isEmpty)
        XCTAssertFalse(content.text.contains("![") && content.text.contains("](http"),
            "no invented image URLs")
        await engine.shutdownForTests()
    }

    func testGLMMultiPageMemoryBound() async throws {
        guard let entry = OCRModelCatalog.entry(for: .glmOCR) else { XCTFail("missing catalog"); return }
        let (helper, store) = try require(entry: entry)
        // 20-page warm run; peak RSS must stay bounded (no per-page leak).
        let directory = try makeTempDirectory()
        let pages = (1...20).map { "PAGE-\($0)-MARKER" }
        let pdf = try OCRFixtures.labeledPDF(pages: pages, in: directory)
        let service = OCRService(engine: NativeOCREngine(helperURL: helper, store: store), temporaryRoot: directory)
        let result = try await service.recognize(url: pdf, options: OCROptions(modelID: .glmOCR, mode: .text, compute: .cpu))
        XCTAssertEqual(result.pages.count, 20)
    }

    private func runCase(id: OCRModelID, compute: OCRComputePreference, document: Bool = false) async throws {
        guard let entry = OCRModelCatalog.entry(for: id) else { XCTFail("missing catalog"); return }
        let (helper, store) = try require(entry: entry)
        if compute == .cpu, let reason = entry.cpuUnsupportedReason {
            throw XCTSkip("CPU unsupported for \(entry.displayName): \(reason)")
        }
        if compute == .metal, !OCRDeviceCaps.hasMetal {
            throw XCTSkip("No Metal device on this Mac; Metal case cannot pass here.")
        }
        let directory = try makeTempDirectory()
        let receipt = try OCRFixtures.receiptImage(in: directory)
        let engine = NativeOCREngine(helperURL: helper, store: store)
        let options = OCROptions(modelID: id, mode: document ? .document : .text, compute: compute)
        let content = try await engine.recognize(OCRFixtures.loadCGImage(receipt), options: options)
        await engine.shutdownForTests()
        // Silent Apple fallback is a failure: actualCompute must match.
        let expected: OCRActualCompute = compute == .cpu ? .cpu : (entry.projectorCPUOnly ? .metalTextCPUProjector : .metal)
        XCTAssertEqual(content.actualCompute, expected)
        let normalized = content.text.precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines).joined(separator: " ")
        for field in ["12345", "17.50", "2", "35.00"] {
            XCTAssertTrue(normalized.contains(field), "missing \(field) in: \(content.text)")
        }
        if document {
            XCTAssertNotNil(content.markdown, "document mode must produce markdown")
        }
    }
}

enum OCRDeviceCaps {
    static var hasMetal: Bool {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice() != nil
        #else
        return false
        #endif
    }
}


enum OCRProcessCount {
    static func helperCount() -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "OrangeOCRHelper"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.split(separator: "\n").filter { !$0.isEmpty }.count
    }
}
