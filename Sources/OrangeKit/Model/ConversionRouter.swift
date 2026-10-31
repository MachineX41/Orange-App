import Foundation

public enum ConversionRouter {
    public static func convert(_ url: URL, to target: ConvertTarget, quality: Double = 0.9, progress: ProgressHandler? = nil) async throws -> [URL] {
        let directory = OutputLocation.directory(beside: url)
        switch Catalog.kind(for: url) {
        case .image:
            if target == .txt {
                let result = try await OCRService.shared.recognize(url: url, options: OCROptions.appleDefault, progress: progress)
                guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OrangeError.nothingFound }
                return [try writeText(result.text, beside: url)]
            }
            let request = ImageRequest(source: url, format: target, quality: quality, directory: directory)
            return [try ImageEngine.convert(request)]
        case .video:
            return [try await VideoEditor.convert(url, to: target, progress: progress)]
        case .audio:
            return [try await AudioEngine.convert(url, to: target, progress: progress)]
        case .pdf:
            switch target {
            case .png, .jpeg, .heic, .tiff, .webp:
                return try PDFToolkit.toImages(url: url, format: target, progress: progress)
            case .txt:
                return [try writeText(try await PDFToolkit.text(of: url, progress: progress), beside: url)]
            default:
                return [try await DocumentConverter.convert(url, to: target)]
            }
        case .document:
            return [try await DocumentConverter.convert(url, to: target)]
        case .archive, .other:
            throw OrangeError.unsupported(url.pathExtension.uppercased())
        }
    }

    static func writeText(_ text: String, beside url: URL) throws -> URL {
        let destination = UniqueDestination.url(
            in: OutputLocation.directory(beside: url),
            baseName: OutputLocation.baseName(url),
            extension: "txt"
        )
        do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            throw OrangeError.writeFailed(destination.lastPathComponent)
        }
        return destination
    }
}
