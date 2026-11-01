import CoreGraphics
import Foundation

/// Identifies which engine performs recognition. `appleVision` is the OS-managed
/// default; the rest are downloadable single-file GGUF pairs (model + projector).
public enum OCRModelID: String, Codable, CaseIterable, Sendable {
    case appleVision = "apple-vision"
    case glmOCR = "glm-ocr"
    case qwen3VL2B = "qwen3-vl-2b"

}

public enum OCRMode: String, Codable, Sendable, CaseIterable {
    case text
    case document
}

public enum OCRComputePreference: String, Codable, Sendable, CaseIterable {
    case automatic
    case metal
    case cpu
}

public enum OCRQuality: String, Codable, Sendable, CaseIterable {
    case balanced
    case high
}

/// Where the numbers actually came from. Apple delegates to the OS; `metalTextCPUProjector`
/// `metalTextCPUProjector` is reserved for split backends (LM on Metal, projector on CPU).
public enum OCRActualCompute: String, Codable, Sendable {
    case appleManaged = "appleManaged"
    case metal = "metal"
    case cpu = "cpu"
    case metalTextCPUProjector = "metalTextCPUProjector"
}

public struct OCROptions: Sendable {
    public var modelID: OCRModelID
    public var mode: OCRMode
    public var languageIdentifiers: [String]
    public var compute: OCRComputePreference
    public var quality: OCRQuality

    public init(
        modelID: OCRModelID = .appleVision,
        mode: OCRMode = .text,
        languageIdentifiers: [String] = [],
        compute: OCRComputePreference = .automatic,
        quality: OCRQuality = .balanced
    ) {
        self.modelID = modelID
        self.mode = mode
        self.languageIdentifiers = languageIdentifiers
        self.compute = compute
        self.quality = quality
    }

    public static var appleDefault: OCROptions {
        OCROptions(modelID: .appleVision, mode: .text, compute: .automatic, quality: .balanced)
    }
}

public struct OCRTextBlock: Codable, Sendable {
    /// Recognized line text.
    public var text: String
    /// Normalized top-left-origin rect in unit space; `.null` when the engine gives no layout.
    public var bounds: CGRect

    public init(text: String, bounds: CGRect = .null) {
        self.text = text
        self.bounds = bounds
    }
}

public struct OCRTableCell: Codable, Sendable {
    public var text: String
    public var rowRange: Range<Int>
    public var columnRange: Range<Int>

    public init(text: String, rowRange: Range<Int>, columnRange: Range<Int>) {
        self.text = text
        self.rowRange = rowRange
        self.columnRange = columnRange
    }
}

public struct OCRTable: Codable, Sendable {
    public var cells: [OCRTableCell]

    public init(cells: [OCRTableCell] = []) {
        self.cells = cells
    }
}

public struct OCRPageContent: Sendable {
    public var text: String
    public var markdown: String?
    public var blocks: [OCRTextBlock]
    public var tables: [OCRTable]
    /// Regions in reading order; empty when the engine did whole-page recognition.
    public var regions: [OCRRegion]
    public var actualCompute: OCRActualCompute
    public var durationSeconds: Double
    public var truncated: Bool

    public init(
        text: String,
        markdown: String? = nil,
        blocks: [OCRTextBlock] = [],
        tables: [OCRTable] = [],
        regions: [OCRRegion] = [],
        actualCompute: OCRActualCompute,
        durationSeconds: Double = 0,
        truncated: Bool = false
    ) {
        self.text = text
        self.markdown = markdown
        self.blocks = blocks
        self.tables = tables
        self.regions = regions
        self.actualCompute = actualCompute
        self.durationSeconds = durationSeconds
        self.truncated = truncated
    }

    public static func empty(actualCompute: OCRActualCompute, durationSeconds: Double = 0) -> OCRPageContent {
        OCRPageContent(text: "", actualCompute: actualCompute, durationSeconds: durationSeconds)
    }
}

public struct OCRPageResult: Sendable {
    public var sourceURL: URL
    /// Zero-based page index; 0 for single images.
    public var pageIndex: Int
    public var content: OCRPageContent
    /// True when the page already had a usable text layer and no recognition ran.
    public var embeddedTextUsed: Bool

    public init(sourceURL: URL, pageIndex: Int, content: OCRPageContent, embeddedTextUsed: Bool = false) {
        self.sourceURL = sourceURL
        self.pageIndex = pageIndex
        self.content = content
        self.embeddedTextUsed = embeddedTextUsed
    }
}

public struct OCRDocumentResult: Sendable {
    /// Pages in source order.
    public var pages: [OCRPageResult]

    public init(pages: [OCRPageResult]) {
        self.pages = pages
    }

    public var text: String {
        pages.map(\.content.text).joined(separator: "\n\n")
    }
}

public protocol OCREngine: Sendable {
    func recognize(_ image: CGImage, options: OCROptions) async throws -> OCRPageContent
}

/// A layout region on a page: text/table goes to the VLM as a crop,
/// figure is cropped to a real file and referenced. Follows the
/// Marker/MinerU recipe: never ask the VLM about pixels.
public struct OCRRegion: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case text
        case table
        case figure
    }

    public var kind: Kind
    /// Normalized top-left-origin rect in unit space.
    public var bounds: CGRect
    /// VLM transcription for text/table; nil for figure.
    public var text: String?
    /// Local image path for figure; nil otherwise.
    public var imagePath: String?

    public init(kind: Kind, bounds: CGRect, text: String? = nil, imagePath: String? = nil) {
        self.kind = kind
        self.bounds = bounds
        self.text = text
        self.imagePath = imagePath
    }
}


