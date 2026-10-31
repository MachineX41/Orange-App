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
}

public struct ImageRequest: Sendable {
    public var source: URL
    public var operation: ImageOperation
    public var format: ConvertTarget
    public var quality: Double
    public var directory: URL

    public init(source: URL, operation: ImageOperation, format: ConvertTarget, quality: Double, directory: URL) {
        self.source = source
        self.operation = operation
        self.format = format
        self.quality = quality
        self.directory = directory
    }
}

public struct ImageTranscoder: Sendable {
    public init() {}

    public func convert(_ request: ImageRequest) throws -> URL {
        guard request.format.isRaster else {
            throw OrangeError.unsupported(request.format.rawValue)
        }
        let loaded = try loadOriented(request.source)
        let image = try apply(request.operation, to: loaded)
        let base = request.source.deletingPathExtension().lastPathComponent
        let destination = UniqueDestination.url(
            in: request.directory,
            baseName: base,
            extension: request.format.fileExtension
        )
        if request.format == .pdf {
            try writePDF(image, to: destination)
        } else {
            try write(image, format: request.format, quality: request.quality, to: destination)
        }
        return destination
    }

    public func loadOriented(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw OrangeError.unreadable(url.lastPathComponent)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
        let maxPixel = max(width, height, 1)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw OrangeError.unreadable(url.lastPathComponent)
        }
        return try normalize(thumbnail)
    }

    private func apply(_ operation: ImageOperation, to image: CGImage) throws -> CGImage {
        switch operation {
        case .original:
            return image
        case .resize(let width, let height):
            guard width > 0, height > 0 else { throw OrangeError.unsupported("resize") }
            return try render(width: width, height: height) { context in
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        case .cropNormalized(let normalized):
            let pixels = CropMath.pixelRect(
                normalizedTopLeft: normalized,
                imageSize: CGSize(width: image.width, height: image.height)
            ).integral
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let rect = pixels.intersection(bounds)
            guard rect.width >= 1, rect.height >= 1, let cropped = image.cropping(to: rect) else {
                throw OrangeError.unsupported("crop")
            }
            return try normalize(cropped)
        case .rotateClockwise(let degrees):
            return try rotate(image, clockwise: degrees)
        case .flipHorizontal:
            return try render(width: image.width, height: image.height) { context in
                context.translateBy(x: CGFloat(image.width), y: 0)
                context.scaleBy(x: -1, y: 1)
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
        }
    }

    private func rotate(_ image: CGImage, clockwise degrees: Int) throws -> CGImage {
        let turns = ((degrees % 360) + 360) % 360
        if turns == 0 { return image }
        let swap = turns == 90 || turns == 270
        let width = swap ? image.height : image.width
        let height = swap ? image.width : image.height
        return try render(width: width, height: height) { context in
            context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            context.rotate(by: -CGFloat(turns) * .pi / 180)
            context.translateBy(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    private func render(width: Int, height: Int, draw: (CGContext) -> Void) throws -> CGImage {
        guard let context = rgbaContext(width: width, height: height) else {
            throw OrangeError.writeFailed("image")
        }
        context.interpolationQuality = .high
        draw(context)
        guard let rendered = context.makeImage() else {
            throw OrangeError.writeFailed("image")
        }
        return rendered
    }

    private func normalize(_ image: CGImage) throws -> CGImage {
        if image.bitsPerComponent == 8,
           image.colorSpace?.model == .rgb,
           image.alphaInfo == .premultipliedLast || image.alphaInfo == .noneSkipLast {
            return image
        }
        return try render(width: image.width, height: image.height) { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    private func rgbaContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private func write(_ image: CGImage, format: ConvertTarget, quality: Double, to url: URL) throws {
        let type = utType(format)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
        var properties: [CFString: Any] = [:]
        switch format {
        case .jpeg, .heic, .webp:
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0.05), 1)
        default:
            break
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
    }

    private func writePDF(_ image: CGImage, to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
    }

    private func utType(_ format: ConvertTarget) -> UTType {
        switch format {
        case .jpeg: .jpeg
        case .png: .png
        case .webp: .webP
        case .heic: .heic
        case .tiff: .tiff
        case .bmp: .bmp
        case .gif: .gif
        case .pdf: .pdf
        case .mp4, .mov, .m4a: .data
        }
    }
}
