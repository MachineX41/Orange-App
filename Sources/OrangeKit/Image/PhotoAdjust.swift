import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

public struct PhotoAdjustments: Equatable, Hashable, Codable, Sendable {
    public var exposure = 0.0
    public var brightness = 0.0
    public var contrast = 0.0
    public var highlights = 0.0
    public var shadows = 0.0
    public var saturation = 0.0
    public var vibrance = 0.0
    public var warmth = 0.0
    public var tint = 0.0
    public var sharpness = 0.0
    public var vignette = 0.0

    public init() {}

    public var isIdentity: Bool { self == PhotoAdjustments() }
}

public enum CoreImageKit {
    public static let context = CIContext(options: [.cacheIntermediates: false])

    public static func cgImage(_ image: CIImage, extent: CGRect) throws -> CGImage {
        guard let output = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: ImageEngine.sRGB) else {
            throw OrangeError.writeFailed("image")
        }
        return output
    }
}

public enum PhotoAdjust {
    public static func apply(_ values: PhotoAdjustments, to input: CIImage) -> CIImage {
        let extent = input.extent
        var image = input

        if values.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = image
            filter.ev = Float(values.exposure)
            image = filter.outputImage ?? image
        }
        if values.brightness != 0 || values.contrast != 0 || values.saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.brightness = Float(values.brightness / 100 * 0.25)
            filter.contrast = Float(1 + values.contrast / 100 * 0.5)
            filter.saturation = Float(1 + values.saturation / 100)
            image = filter.outputImage ?? image
        }
        if values.vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = image
            filter.amount = Float(values.vibrance / 100)
            image = filter.outputImage ?? image
        }
        if values.highlights < 0 || values.shadows != 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = image
            filter.highlightAmount = Float(1 + min(values.highlights, 0) / 100)
            filter.shadowAmount = Float(values.shadows / 100)
            image = filter.outputImage ?? image
        }
        if values.highlights > 0 {
            let lift = CGFloat(values.highlights / 100 * 0.12)
            let filter = CIFilter.toneCurve()
            filter.inputImage = image
            filter.point0 = CGPoint(x: 0, y: 0)
            filter.point1 = CGPoint(x: 0.25, y: 0.25)
            filter.point2 = CGPoint(x: 0.5, y: 0.5 + lift * 0.3)
            filter.point3 = CGPoint(x: 0.75, y: 0.75 + lift)
            filter.point4 = CGPoint(x: 1, y: 1)
            image = filter.outputImage ?? image
        }
        if values.warmth != 0 || values.tint != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = image
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 6500 + CGFloat(values.warmth) * 30, y: CGFloat(values.tint))
            image = filter.outputImage ?? image
        }
        if values.sharpness > 0 {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = image
            filter.sharpness = Float(values.sharpness / 100 * 1.2)
            image = filter.outputImage ?? image
        }
        if values.vignette > 0 {
            let filter = CIFilter.vignette()
            filter.inputImage = image
            filter.intensity = Float(values.vignette / 100 * 1.5)
            filter.radius = 1.6
            image = filter.outputImage ?? image
        }
        return image.cropped(to: extent)
    }

    public static func render(_ values: PhotoAdjustments, image: CGImage) throws -> CGImage {
        let input = CIImage(cgImage: image)
        return try CoreImageKit.cgImage(apply(values, to: input), extent: input.extent)
    }
}
