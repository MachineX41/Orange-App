import CoreGraphics
import Foundation

/// IPC contract for the warm native helper process (stdin/stdout NDJSON,
/// protocolVersion 1; logs go to stderr, never stdout). Swift drains stdout
/// line-delimited (16 MiB cap/line) and stderr tail (last 64 KiB); every
/// handler path completes exactly one continuation per runID.
public enum OCRHelperIPC {
    public static let protocolVersion = 1

    public struct LoadCommand: Codable, Sendable {
        public var type: String = "load"
        public var protocolVersion: Int = 1
        public var requestID: String
        public var modelID: String
        public var modelPath: String
        public var projectorPath: String
        public var compute: String
        public var quality: String
        public var contextTokens: Int
        public var maxOutputTokens: Int
        public var threads: Int

        public init(
            requestID: String = UUID().uuidString,
            modelID: OCRModelID,
            modelPath: String,
            projectorPath: String,
            compute: OCRComputePreference,
            quality: OCRQuality,
            contextTokens: Int = 8192,
            maxOutputTokens: Int = 4096,
            threads: Int = 4
        ) {
            self.requestID = requestID
            self.modelID = modelID.rawValue
            self.modelPath = modelPath
            self.projectorPath = projectorPath
            self.compute = compute.rawValue
            self.quality = quality.rawValue
            self.contextTokens = contextTokens
            self.maxOutputTokens = maxOutputTokens
            self.threads = threads
        }
    }

    public struct RecognizeCommand: Codable, Sendable {
        public var type: String = "recognize"
        public var protocolVersion: Int = 1
        public var requestID: String
        public var imagePath: String
        public var mode: String

        public init(requestID: String = UUID().uuidString, imagePath: String, mode: OCRMode) {
            self.requestID = requestID
            self.imagePath = imagePath
            self.mode = mode.rawValue
        }
    }

    public struct ShutdownCommand: Codable, Sendable {
        public var type: String = "shutdown"
        public var protocolVersion: Int = 1
    }

    public struct Capabilities: Codable, Sendable {
        public var protocolVersion: Int
        public var runtimeRevision: String
        public var cpuAvailable: Bool
        public var metalAvailable: Bool
        public var recommendedMetalBytes: Int64?
    }

    public enum EventKind: String, Codable, Sendable {
        case ready
        case progress
        case result
        case error
    }

    public struct Event: Codable, Sendable {
        public var type: String
        public var protocolVersion: Int
        public var requestID: String?
        public var text: String?
        public var markdown: String?
        public var actualCompute: String?
        public var inputTokens: Int?
        public var outputTokens: Int?
        public var durationSeconds: Double?
        public var truncated: Bool?
        public var code: String?
        public var message: String?
    }

    public enum HelperError: Error, Sendable {
        case invalidRequest(String)
        case modelLoad(String)
        case metalUnavailable(String)
        case metalInitialization(String)
        case outOfMemory(String)
        case contextOverflow(String)
        case decodeFailed(String)
    }
}

/// Pinned per-model prompts. One literal prompt per family — never a single
/// generic "OCR" string. Native helper selects by modelID; app never injects
/// free-form prompts.
public enum OCRModelPrompts {
    public static func textPrompt(for id: OCRModelID) -> String {
        switch id {
        case .appleVision:
            "Transcribe all visible text exactly. Preserve reading order and line breaks."
        case .glmOCR:
            "Text Recognition:"
        case .paddleOCRVL16:
            "OCR:"
        case .qwen3VL2B:
            "Transcribe all visible text exactly. Preserve reading order and line breaks."
        case .dotsOCR:
            "Extract the text content from this image."
        case .deepseekOCR2:
            "Free OCR."
        }
    }

    public static func documentPrompt(for id: OCRModelID) -> String {
        "Transcribe this document as Markdown. Preserve all visible text, reading order, headings, lists, tables and formulas. Do not translate, summarize, or invent content."
    }
}
