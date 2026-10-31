import Foundation
import UniformTypeIdentifiers

public enum MediaKind: String, Codable, Sendable, CaseIterable {
    case image
    case video
    case audio
    case pdf
    case archive
    case other
}

public enum ConvertTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    case jpeg
    case png
    case webp
    case heic
    case tiff
    case bmp
    case gif
    case pdf
    case mp4
    case mov
    case m4a

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .tiff: "tif"
        case .pdf: "pdf"
        default: rawValue
        }
    }

    public var isRaster: Bool {
        switch self {
        case .mp4, .mov, .m4a: false
        default: true
        }
    }
}

public enum ToolID: String, Codable, Sendable, CaseIterable, Identifiable {
    case convert
    case compress
    case resize
    case crop
    case rotate
    case stripMetadata
    case imagesToPDF
    case mergePDF
    case splitPDF
    case archive

    public var id: String { rawValue }

    public var isReady: Bool { true }
}

public enum PlannedTool: String, Codable, Sendable, CaseIterable, Identifiable {
    case video
    case audio
    case annotate
    case qr
    case download
    case collage

    public var id: String { rawValue }
}

public enum ActionID: String, Codable, Sendable, CaseIterable, Identifiable {
    case float
    case copy
    case move
    case copyPath
    case duplicate
    case reveal
    case airDrop
    case zip

    public var id: String { rawValue }
}

public enum Catalog {
    public static func kind(for url: URL) -> MediaKind {
        if isDirectory(url) { return .other }
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .image) || url.pathExtension.lowercased() == "heic" {
            return .image
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return .video
        }
        if type.conforms(to: .audio) {
            return .audio
        }
        if type.conforms(to: .pdf) {
            return .pdf
        }
        if type.conforms(to: .archive) || type.conforms(to: .zip) || url.pathExtension.lowercased() == "zip" {
            return .archive
        }
        return .other
    }

    public static func convertTargets(for kind: MediaKind) -> [ConvertTarget] {
        switch kind {
        case .image:
            [.jpeg, .png, .webp, .heic, .tiff, .bmp, .gif, .pdf]
        case .video:
            [.mp4, .mov]
        case .audio:
            [.m4a]
        case .pdf, .archive, .other:
            []
        }
    }

    public static func commonConvertTargets(for kinds: [MediaKind]) -> [ConvertTarget] {
        guard let first = kinds.first else { return [] }
        return kinds.dropFirst().reduce(convertTargets(for: first)) { partial, kind in
            let allowed = Set(convertTargets(for: kind))
            return partial.filter { allowed.contains($0) }
        }
    }

    public static func tools(for kind: MediaKind) -> [ToolID] {
        switch kind {
        case .image:
            [.compress, .resize, .crop, .rotate, .stripMetadata, .imagesToPDF]
        case .pdf:
            [.mergePDF, .splitPDF]
        case .archive:
            [.archive]
        case .video, .audio, .other:
            []
        }
    }

    public static func commonTools(for kinds: [MediaKind]) -> [ToolID] {
        guard let first = kinds.first else { return [] }
        return kinds.dropFirst().reduce(tools(for: first)) { partial, kind in
            let allowed = Set(tools(for: kind))
            return partial.filter { allowed.contains($0) }
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
}
