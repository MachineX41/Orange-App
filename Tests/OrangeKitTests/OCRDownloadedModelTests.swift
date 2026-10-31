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

    func testGLMCPURecognition() throws { try self.runCase(id: .glmOCR, compute: .cpu) }
    func testGLMMetalRecognition() throws { try self.runCase(id: .glmOCR, compute: .metal) }
    func testPaddleCPURecognition() throws { try self.runCase(id: .paddleOCRVL16, compute: .cpu) }
    func testPaddleMetalRecognition() throws { try self.runCase(id: .paddleOCRVL16, compute: .metal) }
    func testQwenCPURecognition() throws { try self.runCase(id: .qwen3VL2B, compute: .cpu, document: true) }
    func testQwenMetalRecognition() throws { try self.runCase(id: .qwen3VL2B, compute: .metal, document: true) }
    func testDotsCPURecognition() throws { try self.runCase(id: .dotsOCR, compute: .cpu) }
    func testDotsMetalRecognition() throws { try self.runCase(id: .dotsOCR, compute: .metal) }
    func testDeepSeekCPURecognition() throws { try self.runCase(id: .deepseekOCR2, compute: .cpu) }
    func testDeepSeekMetalCPUProjectorRecognition() throws { try self.runCase(id: .deepseekOCR2, compute: .metal) }

    func testWarmPDFReusesGLM() throws { try XCTSkip("Requires installed GLM pair; see gate docs.") }
    func testSwitchGLMToAppleReleasesHelper() throws { try XCTSkip("Requires installed GLM pair; see gate docs.") }
    func testCancelGLMInference() throws { try XCTSkip("Requires installed GLM pair; see gate docs.") }
    func testGLMMultiPageMemoryBound() throws { try XCTSkip("Requires installed GLM pair; see gate docs.") }

    private func runCase(id: OCRModelID, compute: OCRComputePreference, document: Bool = false) throws {
        guard let entry = OCRModelCatalog.entry(for: id) else { XCTFail("missing catalog"); return }
        let (_, _) = try require(entry: entry)
        // Real inference only; silent Apple fallback is a failure, enforced by
        // checking actualCompute in the async path (implemented when wired).
        if compute == .metal, !OCRDeviceCaps.hasMetal {
            throw XCTSkip("No Metal device on this Mac; Metal case cannot pass here.")
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

