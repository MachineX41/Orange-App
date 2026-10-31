import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageOperation: Equatable, Sendable {
    case original
    case resize(width: Int, height: Int)
    case cropNormalized(CGRect)
    case rotateClockwise(Int)
    case flipHorizontal
    case flipVertical
}

public struct ImageRequest: Sendable {
    public var source: URL
    public var operation: ImageOperation
    public var format: ConvertTarget
    public var quality: Double
    public var directory: URL
    public var suffix: String?
    public var preserveMetadata: Bool

    public init(
        source: URL,
        operation: ImageOperation = .original,
        format: ConvertTarget,
        quality: Double = 0.9,
        directory: URL,
        suffix: String? = nil,
        preserveMetadata: Bool = true
    ) {
        self.source = source
        self.operation = operation
        self.format = format
        self.quality = quality
        self.directory = directory
        self.suffix = suffix
        self.preserveMetadata = preserveMetadata
    }
}

public enum ImageEngine {
    public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    // MARK: Reading

    public static func properties(of url: URL) -> [String: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return [:]
        }
        return properties
    }

    public static func pixelSize(of url: URL) -> CGSize {
        let props = properties(of: url)
        let width = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue ?? 0
        let orientation = (props[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// Loads the first frame upright (EXIF orientation applied) as 8-bit RGBA.
    public static func load(_ url: URL, maxPixel: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw OrangeError.unreadable(url.lastPathComponent)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let width = (props?[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue ?? 0
        let height = (props?[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue ?? 0
        var limit = max(width, height)
        if limit == 0 { limit = 8192 }
        if let maxPixel { limit = min(limit, maxPixel) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw OrangeError.unreadable(url.lastPathComponent)
        }
        return try normalize(image)
    }

    // MARK: Drawing

    public static func makeContext(width: Int, height: Int, space: CGColorSpace = sRGB) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    public static func render(
        width: Int,
        height: Int,
        space: CGColorSpace? = nil,
        draw: (CGContext) -> Void
    ) throws -> CGImage {
        guard width > 0, height > 0 else { throw OrangeError.writeFailed("image") }
        let context = makeContext(width: width, height: height, space: space ?? sRGB)
            ?? makeContext(width: width, height: height)
        guard let context else { throw OrangeError.writeFailed("image") }
        context.interpolationQuality = .high
        draw(context)
        guard let image = context.makeImage() else { throw OrangeError.writeFailed("image") }
        return image
    }

    static func normalize(_ image: CGImage) throws -> CGImage {
        if image.bitsPerComponent == 8,
           image.bitsPerPixel == 32,
           image.colorSpace?.model == .rgb,
           image.alphaInfo == .premultipliedLast || image.alphaInfo == .noneSkipLast {
            return image
        }
        let space = image.colorSpace?.model == .rgb ? image.colorSpace : nil
        return try render(width: image.width, height: image.height, space: space) { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    public static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast: true
        default: false
        }
    }

    public static func flattened(_ image: CGImage, background: CGColor = CGColor(gray: 1, alpha: 1)) throws -> CGImage {
        try render(width: image.width, height: image.height) { context in
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(background)
            context.fill(rect)
            context.draw(image, in: rect)
        }
    }

    public static func transform(_ image: CGImage, _ operation: ImageOperation) throws -> CGImage {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        switch operation {
        case .original:
            return image
        case .resize(let width, let height):
            guard width > 0, height > 0 else { throw OrangeError.unsupported("resize") }
            return try render(width: width, height: height) { context in
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        case .cropNormalized(let normalized):
            let pixels = CropMath.pixelRect(
                normalizedTopLeft: normalized,
                imageSize: CGSize(width: image.width, height: image.height)
            ).integral
            let rect = pixels.intersection(full)
            guard rect.width >= 1, rect.height >= 1, let cropped = image.cropping(to: rect) else {
                throw OrangeError.unsupported("crop")
            }
            return try normalize(cropped)
        case .rotateClockwise(let degrees):
            let turns = ((degrees % 360) + 360) % 360
            if turns == 0 { return image }
            let swap = turns == 90 || turns == 270
            let width = swap ? image.height : image.width
            let height = swap ? image.width : image.height
            return try render(width: width, height: height) { context in
                context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
                context.rotate(by: -CGFloat(turns) * .pi / 180)
                context.translateBy(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2)
                context.draw(image, in: full)
            }
        case .flipHorizontal:
            return try render(width: image.width, height: image.height) { context in
                context.translateBy(x: CGFloat(image.width), y: 0)
                context.scaleBy(x: -1, y: 1)
                context.draw(image, in: full)
            }
        case .flipVertical:
            return try render(width: image.width, height: image.height) { context in
                context.translateBy(x: 0, y: CGFloat(image.height))
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: full)
            }
        }
    }

    // MARK: Writing

    public static func uprightProperties(_ properties: [String: Any]) -> [String: Any] {
        var copy = properties
        copy[kCGImagePropertyOrientation as String] = 1
        if var tiff = copy[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            copy[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        copy.removeValue(forKey: kCGImagePropertyPixelWidth as String)
        copy.removeValue(forKey: kCGImagePropertyPixelHeight as String)
        return copy
    }

    public static func encode(
        _ image: CGImage,
        as target: ConvertTarget,
        quality: Double,
        properties: [String: Any] = [:]
    ) throws -> Data {
        guard let type = target.imageType else { throw OrangeError.unsupported(target.rawValue.uppercased()) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw OrangeError.unsupported(target.rawValue.uppercased())
        }
        let prepared = (target == .jpeg || target == .bmp) && hasAlpha(image) ? try flattened(image) : image
        var options = properties
        if target.isLossyImage {
            options[kCGImageDestinationLossyCompressionQuality as String] = min(max(quality, 0.05), 1)
        }
        CGImageDestinationAddImage(destination, prepared, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw OrangeError.writeFailed(target.rawValue.uppercased())
        }
        return data as Data
    }

    public static func write(
        _ image: CGImage,
        to url: URL,
        as target: ConvertTarget,
        quality: Double,
        properties: [String: Any] = [:]
    ) throws {
        if target == .pdf {
            try writePDF([image], to: url)
            return
        }
        let data = try encode(image, as: target, quality: quality, properties: properties)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
    }

    public static func writePDF(_ images: [CGImage], to url: URL) throws {
        guard let first = images.first, let consumer = CGDataConsumer(url: url as CFURL) else {
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
        var box = CGRect(x: 0, y: 0, width: first.width, height: first.height)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
        for image in images {
            var page = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let boxData = withUnsafeBytes(of: &page) { Data($0) }
            context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            context.draw(image, in: page)
            context.endPDFPage()
        }
        context.closePDF()
    }

    public static func convert(_ request: ImageRequest) throws -> URL {
        let image = try transform(load(request.source), request.operation)
        let destination = UniqueDestination.url(
            in: request.directory,
            baseName: OutputLocation.baseName(request.source, suffix: request.suffix),
            extension: request.format.fileExtension
        )
        let props = request.preserveMetadata ? uprightProperties(properties(of: request.source)) : [:]
        try write(image, to: destination, as: request.format, quality: request.quality, properties: props)
        return destination
    }

    public static func sameFormat(as url: URL) -> ConvertTarget {
        let ext = Catalog.canonicalExtension(url.pathExtension)
        if let match = ConvertTarget.allCases.first(where: { $0.imageType != nil && $0.fileExtension == ext }),
           ImageCapabilities.canWrite(match) {
            return match
        }
        return .png
    }

    @discardableResult
    public static func save(
        _ image: CGImage,
        from source: URL,
        suffix: String,
        format: ConvertTarget? = nil,
        quality: Double = 0.92,
        keepMetadata: Bool = false
    ) throws -> URL {
        let target = format ?? sameFormat(as: source)
        let destination = UniqueDestination.url(
            in: OutputLocation.directory(beside: source),
            baseName: OutputLocation.baseName(source, suffix: suffix),
            extension: target.fileExtension
        )
        let props = keepMetadata ? uprightProperties(properties(of: source)) : [:]
        try write(image, to: destination, as: target, quality: quality, properties: props)
        return destination
    }
}
