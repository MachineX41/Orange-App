import AVFoundation
import Foundation
import ImageIO
import PDFKit

public struct MetadataField: Identifiable, Hashable, Sendable {
    public var id: String { group + "." + key }
    public var group: String
    public var key: String
    public var value: String
}

public enum MetadataKit {
    public static func fields(of url: URL) async -> [MetadataField] {
        var fields: [MetadataField] = []
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .localizedTypeDescriptionKey])
        let file = Lang.t("File", "Dosya")
        fields.append(MetadataField(group: file, key: Lang.t("Name", "Ad"), value: url.lastPathComponent))
        if let type = values?.localizedTypeDescription {
            fields.append(MetadataField(group: file, key: Lang.t("Kind", "Tür"), value: type))
        }
        if let size = values?.fileSize {
            fields.append(MetadataField(group: file, key: Lang.t("Size", "Boyut"), value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
        }
        if let created = values?.creationDate {
            fields.append(MetadataField(group: file, key: Lang.t("Created", "Oluşturma"), value: created.formatted(date: .abbreviated, time: .shortened)))
        }
        if let modified = values?.contentModificationDate {
            fields.append(MetadataField(group: file, key: Lang.t("Modified", "Değiştirme"), value: modified.formatted(date: .abbreviated, time: .shortened)))
        }

        switch Catalog.kind(for: url) {
        case .image:
            fields += imageFields(ImageEngine.properties(of: url))
        case .pdf:
            if let document = PDFDocument(url: url) {
                let group = "PDF"
                fields.append(MetadataField(group: group, key: Lang.t("Pages", "Sayfa"), value: "\(document.pageCount)"))
                for (key, value) in document.documentAttributes ?? [:] {
                    fields.append(MetadataField(group: group, key: "\(key)", value: describe(value)))
                }
            }
        case .video, .audio:
            let asset = AVURLAsset(url: url)
            let group = Lang.t("Media", "Medya")
            if let duration = try? await asset.load(.duration), duration.isNumeric {
                fields.append(MetadataField(group: group, key: Lang.t("Duration", "Süre"), value: Timecode.string(duration.seconds, fraction: true)))
            }
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize),
               let rate = try? await track.load(.nominalFrameRate) {
                fields.append(MetadataField(group: group, key: Lang.t("Resolution", "Çözünürlük"), value: "\(Int(abs(size.width))) × \(Int(abs(size.height)))"))
                fields.append(MetadataField(group: group, key: "FPS", value: String(format: "%.2f", rate)))
            }
            if let items = try? await asset.load(.metadata) {
                for item in items {
                    let key = item.commonKey?.rawValue ?? (item.identifier?.rawValue ?? "?")
                    if let value = try? await item.load(.stringValue) {
                        fields.append(MetadataField(group: "Tags", key: key, value: value))
                    } else if let date = try? await item.load(.dateValue) {
                        fields.append(MetadataField(group: "Tags", key: key, value: date.formatted()))
                    }
                }
            }
        default:
            break
        }
        return fields
    }

    static func imageFields(_ properties: [String: Any]) -> [MetadataField] {
        var fields: [MetadataField] = []
        for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
            if let dictionary = value as? [String: Any] {
                let group = key.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                for (subKey, subValue) in dictionary.sorted(by: { $0.key < $1.key }) {
                    fields.append(MetadataField(group: group, key: subKey, value: describe(subValue)))
                }
            } else {
                fields.append(MetadataField(group: Lang.t("Image", "Görsel"), key: key, value: describe(value)))
            }
        }
        return fields
    }

    static func describe(_ value: Any) -> String {
        switch value {
        case let array as [Any]: array.map(describe).joined(separator: ", ")
        case let date as Date: date.formatted()
        case let number as NSNumber: number.stringValue
        default: "\(value)"
        }
    }

    public static func hasLocation(_ url: URL) -> Bool {
        ImageEngine.properties(of: url)[kCGImagePropertyGPSDictionary as String] != nil
    }

    // MARK: Stripping

    public static func strip(_ url: URL, progress: ProgressHandler? = nil) async throws -> URL {
        let destination = UniqueDestination.url(
            in: OutputLocation.directory(beside: url),
            baseName: OutputLocation.baseName(url, suffix: Lang.t("Clean", "Temiz")),
            extension: url.pathExtension
        )
        switch Catalog.kind(for: url) {
        case .image:
            try stripImage(url, to: destination)
        case .pdf:
            guard let document = PDFDocument(url: url) else { throw OrangeError.unreadable(url.lastPathComponent) }
            document.documentAttributes = [:]
            guard document.write(to: destination) else { throw OrangeError.writeFailed(destination.lastPathComponent) }
        case .video, .audio:
            let asset = AVURLAsset(url: url)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw OrangeError.unsupported(url.pathExtension)
            }
            session.metadata = []
            session.metadataItemFilter = .forSharing()
            let type = VideoEditor.fileType(for: url.pathExtension)
            try await VideoEditor.run(session, to: destination, type: type, progress: progress)
        default:
            throw OrangeError.unsupported(url.pathExtension)
        }
        return destination
    }

    static func stripImage(_ url: URL, to destination: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else {
            throw OrangeError.unreadable(url.lastPathComponent)
        }
        let original = ImageEngine.properties(of: url)
        let orientation = original[kCGImagePropertyOrientation as String] ?? 1
        let null = kCFNull as Any
        let options: [String: Any] = [
            kCGImagePropertyExifDictionary as String: null,
            kCGImagePropertyGPSDictionary as String: null,
            kCGImagePropertyIPTCDictionary as String: null,
            kCGImagePropertyTIFFDictionary as String: null,
            kCGImagePropertyMakerAppleDictionary as String: null,
            kCGImageMetadataShouldExcludeXMP as String: true,
            kCGImageMetadataShouldExcludeGPS as String: true,
            kCGImagePropertyOrientation as String: orientation
        ]
        if let data = NSMutableData() as NSMutableData?,
           let target = CGImageDestinationCreateWithData(data, type, 1, nil) {
            var error: Unmanaged<CFError>?
            if CGImageDestinationCopyImageSource(target, source, options as CFDictionary, &error) {
                try data.write(to: destination, options: .atomic)
                let after = ImageEngine.properties(of: destination)
                if after[kCGImagePropertyGPSDictionary as String] == nil,
                   after[kCGImagePropertyExifDictionary as String] == nil {
                    return
                }
            }
        }
        let image = try ImageEngine.load(url)
        try ImageEngine.write(image, to: destination, as: ImageEngine.sameFormat(as: url), quality: 0.95)
    }
}

public enum Timecode {
    public static func string(_ seconds: Double, fraction: Bool = false) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, seconds)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let secs = total.truncatingRemainder(dividingBy: 60)
        let secText = fraction ? String(format: "%05.2f", secs) : String(format: "%02d", Int(secs))
        return hours > 0 ? "\(hours):" + String(format: "%02d", minutes) + ":" + secText : "\(minutes):" + secText
    }
}
