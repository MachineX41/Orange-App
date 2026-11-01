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
}
