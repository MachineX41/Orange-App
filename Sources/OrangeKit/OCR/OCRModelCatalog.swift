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
            id: .paddleOCRVL16,
            displayName: "PaddleOCR-VL 1.6",
            sourceRepo: "PaddlePaddle/PaddleOCR-VL-1.6-GGUF",
            revision: "511b09642bb324401f15f97cc23bc67e8f0a291d",
            artifacts: [
                OCRModelArtifact(role: "model", filename: "PaddleOCR-VL-1.6-GGUF.gguf", byteCount: 935_769_056, sha256: "f3ae46ec885050acf4b3d31944431e1fd90d50664fb09126af4a3c050ba14ee8"),
                OCRModelArtifact(role: "projector", filename: "PaddleOCR-VL-1.6-GGUF-mmproj.gguf", byteCount: 881_770_560, sha256: "204d757d7610d9b3faab10d506d69e5b244e32bf765e2bab2d0167e65e0a058a"),
            ],
            license: "Apache-2.0",
            licenseURL: "https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.6-GGUF",
            sourceURL: "https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.6-GGUF",
            modes: [.text, .document],
            languageClaim: "Yerel ölçüm yapılmadı",
            provenance: "producer",
            estimatedWorkingSetBytes: 4_000_000_000,
            projectorCPUOnly: false,
            cpuUnsupportedReason: "Vision encoder hangs on CPU backend (upstream llama.cpp); Metal required.",
            scoreNote: "96.33 OmniDocBench v1.6 (upstream pipeline, not this build)"
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
        OCRModelEntry(
            id: .dotsOCR,
            displayName: "dots.ocr",
            sourceRepo: "ggml-org/dots.ocr-GGUF",
            revision: "2c093a32ca360a396bc6d87d60408636130b9d9b",
            artifacts: [
                OCRModelArtifact(role: "model", filename: "dots.ocr-Q8_0.gguf", byteCount: 1_894_530_272, sha256: "6f2db1a75215893760b7c7185d52f11715d2e0cb7bff9cefd3f6d409fa1de7e9"),
                OCRModelArtifact(role: "projector", filename: "mmproj-dots.ocr-Q8_0.gguf", byteCount: 1_344_068_512, sha256: "20d3d35bea3a64ead0b4b213f8db0de136e174bb5b75b8e85786c51e8e822423"),
            ],
            license: "MIT",
            licenseURL: "https://github.com/rednote-hilab/dots.ocr/blob/master/LICENSE",
            sourceURL: "https://huggingface.co/ggml-org/dots.ocr-GGUF",
            modes: [.text, .document],
            languageClaim: "Yerel ölçüm yapılmadı",
            provenance: "ggml-conversion",
            estimatedWorkingSetBytes: 6_000_000_000,
            projectorCPUOnly: false,
            cpuUnsupportedReason: nil,
            scoreNote: nil
        ),
        OCRModelEntry(
            id: .deepseekOCR2,
            displayName: "DeepSeek-OCR 2",
            sourceRepo: "42ailab/DeepSeek-OCR-2-GGUF",
            revision: "2b2f86a4bd33f98580605a47d3c55533eb551422",
            artifacts: [
                OCRModelArtifact(role: "model", filename: "deepseek-ocr-2-Q4_K_M.gguf", byteCount: 1_950_320_688, sha256: "2b5625a1d649670fa4300a1ca139869850a86e9f3ad5b8e389e2133a210b139d"),
                OCRModelArtifact(role: "projector", filename: "mmproj-deepseek-ocr-2-q8_0.gguf", byteCount: 512_537_792, sha256: "46efe1304f581869f3b067eb77b1151dc0daf32bc25ef644fc7d505f4153a545"),
            ],
            license: "Apache-2.0",
            licenseURL: "https://huggingface.co/deepseek-ai/DeepSeek-OCR-2",
            sourceURL: "https://huggingface.co/42ailab/DeepSeek-OCR-2-GGUF",
            modes: [.text, .document],
            languageClaim: "Türkçe: yerel ölçüm yapılmadı",
            provenance: "community",
            estimatedWorkingSetBytes: 5_000_000_000,
            projectorCPUOnly: true,
            cpuUnsupportedReason: nil,
            scoreNote: "Community mirror; hybrid precision note applies"
        ),
    ]

    public static var all: [OCRModelEntry] { [apple] + downloadable }

    public static func entry(for id: OCRModelID) -> OCRModelEntry? {
        all.first { $0.id == id }
    }
}
