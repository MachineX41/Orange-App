import Foundation

/// Curated OCR model library: Apple default plus five downloadable families.
/// Fixed at compile time — no remote catalog fetch at launch.
public struct OCRModelArtifact: Codable, Sendable {
    public var role: String
    public var filename: String
    public var byteCount: Int64
    public var sha256: String

    public init(role: String, filename: String, byteCount: Int64, sha256: String) {
        self.role = role
        self.filename = filename
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct OCRModelEntry: Sendable {
    public var id: OCRModelID
    public var displayName: String
    public var sourceRepo: String
    public var revision: String
    public var artifacts: [OCRModelArtifact]
    public var license: String
    public var licenseURL: String
    public var sourceURL: String
    public var modes: [OCRMode]
    public var languageClaim: String
    public var provenance: String
    public var estimatedWorkingSetBytes: Int64
    public var projectorCPUOnly: Bool
    public var cpuUnsupportedReason: String?
    public var scoreNote: String?

    public var totalBytes: Int64 { artifacts.reduce(0) { $0 + $1.byteCount } }

    public var downloadBaseURL: String {
        "https://huggingface.co/\(sourceRepo)/resolve/\(revision)"
    }
}

public enum OCRModelCatalog {
    public static let apple = OCRModelEntry(
        id: .appleVision,
        displayName: "Apple",
        sourceRepo: "",
        revision: "os",
        artifacts: [],
        license: "OS",
        licenseURL: "",
        sourceURL: "",
        modes: [.text, .document],
        languageClaim: "On-device languages",
        provenance: "producer",
        estimatedWorkingSetBytes: 0,
        projectorCPUOnly: false,
        cpuUnsupportedReason: nil,
        scoreNote: nil
    )

    /// Pinned GGUF pairs. Hashes are HF LFS oids recorded at research time;
    /// never auto-upgraded to a newer revision.
    public static let downloadable: [OCRModelEntry] = [
        OCRModelEntry(
            id: .glmOCR,
            displayName: "GLM-OCR",
            sourceRepo: "ggml-org/GLM-OCR-GGUF",
            revision: "65a42de1148dbed2297e922b5dbc7d9b70c36578",
            artifacts: [
                OCRModelArtifact(role: "model", filename: "GLM-OCR-Q8_0.gguf", byteCount: 950_433_408, sha256: "45bc244a6446aff850521dc41f18bc8d7105ad5f0c2c8c28af04e7cc4f4d50b1"),
                OCRModelArtifact(role: "projector", filename: "mmproj-GLM-OCR-Q8_0.gguf", byteCount: 484_403_648, sha256: "9c4b58e33e316ed142eb5dcb41abec3844d3e6e5dc361ffb782c3fa9d175141f"),
            ],
            license: "MIT",
            licenseURL: "https://huggingface.co/zai-org/GLM-OCR",
            sourceURL: "https://huggingface.co/ggml-org/GLM-OCR-GGUF",
            modes: [.text, .document],
            languageClaim: "Yerel ölçüm yapılmadı",
            provenance: "ggml-conversion",
            estimatedWorkingSetBytes: 3_000_000_000,
            projectorCPUOnly: false,
            cpuUnsupportedReason: nil,
            scoreNote: "94.62 OmniDocBench v1.5 (upstream pipeline, not this build)"
        ),
        OCRModelEntry(
            id: .qwen3VL2B,
            displayName: "Qwen3-VL 2B",
            sourceRepo: "Qwen/Qwen3-VL-2B-Instruct-GGUF",
            revision: "52d6c8ffea26cc873ac5ad116f8631268d7eb503",
            artifacts: [
                OCRModelArtifact(role: "model", filename: "Qwen3VL-2B-Instruct-Q4_K_M.gguf", byteCount: 1_107_409_952, sha256: "089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae"),
                OCRModelArtifact(role: "projector", filename: "mmproj-Qwen3VL-2B-Instruct-F16.gguf", byteCount: 819_394_848, sha256: "c3d5afbef5287953acd57b4043d2269456e5761a4eaccb3b71b062996970aea5"),
            ],
            license: "Apache-2.0",
            licenseURL: "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF",
            sourceURL: "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF",
            modes: [.text, .document],
            languageClaim: "32 OCR languages (upstream claim)",
            provenance: "producer",
            estimatedWorkingSetBytes: 4_000_000_000,
            projectorCPUOnly: false,
            cpuUnsupportedReason: nil,
            scoreNote: nil
        ),
    ]

    public static var all: [OCRModelEntry] { [apple] + downloadable }

    public static func entry(for id: OCRModelID) -> OCRModelEntry? {
        all.first { $0.id == id }
    }
}
