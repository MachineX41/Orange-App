import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum MediaKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case image
    case video
    case audio
    case pdf
    case document
    case archive
    case other

    public var id: String { rawValue }
}

public enum ConvertTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    case jpeg, png, heic, webp, avif, tiff, bmp, gif
    case pdf, txt, md, docx, rtf, html, odt
    case mp4, mov, m4v
    case m4a, wav, aiff

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        default: rawValue
        }
    }

    public var imageType: UTType? {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .webp: .webP
        case .avif: UTType("public.avif")
        case .tiff: .tiff
        case .bmp: .bmp
        case .gif: .gif
        default: nil
        }
    }

    public var isLossyImage: Bool {
        self == .jpeg || self == .heic || self == .webp || self == .avif
    }
}

public enum ImageCapabilities {
    public static let writable: Set<String> = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    public static func canWrite(_ target: ConvertTarget) -> Bool {
        guard let type = target.imageType else { return false }
        return target == .webp || writable.contains(type.identifier)
    }
}

public enum ToolID: String, Codable, Sendable, CaseIterable, Identifiable {
    case adjustImage, cropImage, compressImage, annotateImage, redactImage, addBackground
    case removeBackground, resizeImage, rotateImage, collage, imagesToPDF, recognizeText
    case mergePDF, splitPDF, organizePDF, compressPDF
    case trimVideo, cropVideo, compressVideo, videoSpeed, muteVideo, videoFrames, splitVideo, redactVideo, joinVideos
    case trimAudio, normalizeAudio, audioChannels, bleepAudio, audioToVideo
    case metadata, readQR, unzip
    public var id: String { rawValue }

    public var kinds: Set<MediaKind> {
        switch self {
        case .adjustImage, .cropImage, .compressImage, .annotateImage, .redactImage, .addBackground,
             .removeBackground, .resizeImage, .rotateImage, .collage, .imagesToPDF:
            [.image]
        case .recognizeText:
            [.image, .pdf]
        case .mergePDF, .splitPDF, .organizePDF, .compressPDF:
            [.pdf]
        case .trimVideo, .cropVideo, .compressVideo, .videoSpeed, .muteVideo, .videoFrames,
             .splitVideo, .redactVideo, .joinVideos:
            [.video]
        case .trimAudio, .normalizeAudio, .audioChannels, .bleepAudio, .audioToVideo:
            [.audio]
        case .metadata:
            [.image, .video, .audio, .pdf]
        case .readQR:
            [.image, .pdf]
        case .unzip:
            [.archive]
        }
    }

    public var minimumFiles: Int {
        switch self {
        case .mergePDF, .joinVideos, .collage: 2
        default: 1
        }
    }

    public var acceptsMany: Bool {
        switch self {
        case .compressImage, .removeBackground, .readQR, .recognizeText, .compressPDF, .muteVideo, .compressVideo,
             .normalizeAudio, .imagesToPDF, .collage, .mergePDF, .joinVideos, .unzip:
            true
        default:
            false
        }
    }

    public var primaryKind: MediaKind {
        switch self {
        case .metadata, .readQR: .image
        case .recognizeText: .image
        default: kinds.first ?? .other
        }
    }
}

public enum Catalog {
    static let documentExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "rtf", "doc", "docx", "odt", "html", "htm", "webarchive"
    ]
    static let archiveExtensions: Set<String> = [
        "zip", "tar", "tgz", "gz", "bz2", "tbz", "tbz2", "xz", "txz", "7z", "rar"
    ]

    public static func kind(for url: URL) -> MediaKind {
        let ext = url.pathExtension.lowercased()
        if documentExtensions.contains(ext) { return .document }
        if archiveExtensions.contains(ext) { return .archive }
        let type = UTType(filenameExtension: ext) ?? .data
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .svg) { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .other
    }

    public static func canonicalExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpeg", "jpe": "jpg"
        case "tif": "tiff"
        case "heif": "heic"
        case "htm": "html"
        case "markdown": "md"
        case "aif": "aiff"
        default: ext.lowercased()
        }
    }

    public static func convertTargets(for url: URL) -> [ConvertTarget] {
        let own = canonicalExtension(url.pathExtension)
        let list: [ConvertTarget]
        switch kind(for: url) {
        case .image:
            list = [.jpeg, .png, .heic, .webp, .avif, .tiff, .bmp, .gif].filter(ImageCapabilities.canWrite) + [.pdf, .txt]
        case .video:
            list = [.mp4, .mov, .m4v, .gif, .m4a]
        case .audio:
            list = [.m4a, .wav, .aiff]
        case .pdf:
            list = [.png, .jpeg, .webp, .txt, .md, .docx, .rtf]
        case .document:
            list = [.pdf, .docx, .rtf, .html, .odt, .txt]
        case .archive, .other:
            list = []
        }
        return list.filter { $0.fileExtension != own }
    }

    public static func commonConvertTargets(for urls: [URL]) -> [ConvertTarget] {
        guard let first = urls.first else { return [] }
        let kind = kind(for: first)
        guard urls.allSatisfy({ self.kind(for: $0) == kind }) else { return [] }
        return urls.dropFirst().reduce(convertTargets(for: first)) { partial, url in
            let allowed = Set(convertTargets(for: url))
            return partial.filter { allowed.contains($0) }
        }
    }

    public static func tools(for kind: MediaKind) -> [ToolID] {
        switch kind {
        case .image:
            [.adjustImage, .cropImage, .compressImage, .annotateImage, .redactImage, .addBackground,
             .removeBackground, .metadata, .resizeImage, .rotateImage, .readQR, .recognizeText, .collage, .imagesToPDF]
        case .video:
            [.trimVideo, .cropVideo, .compressVideo, .videoSpeed, .muteVideo, .videoFrames,
             .splitVideo, .redactVideo, .metadata, .joinVideos]
        case .audio:
            [.trimAudio, .normalizeAudio, .audioChannels, .bleepAudio, .audioToVideo, .metadata]
        case .pdf:
            [.mergePDF, .splitPDF, .organizePDF, .compressPDF, .recognizeText, .readQR, .metadata]
        case .archive:
            [.unzip]
        case .document, .other:
            []
        }
    }

    public static func commonTools(for urls: [URL]) -> [ToolID] {
        let kinds = urls.map(kind(for:))
        guard let first = kinds.first else { return [] }
        return tools(for: first).filter { tool in
            kinds.allSatisfy { tool.kinds.contains($0) }
                && (urls.count == 1 ? tool.minimumFiles <= 1 : tool.acceptsMany)
        }
    }
}
