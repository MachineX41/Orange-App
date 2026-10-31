import CoreGraphics
import Foundation
import libwebp

/// ImageIO reads WebP but cannot write it, so encoding goes through libwebp.
public enum WebPEncoder {
    public static let maxDimension = 16383

    public static func encode(_ image: CGImage, quality: Double, lossless: Bool = false) throws -> Data {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width <= maxDimension, height <= maxDimension else {
            throw OrangeError.writeFailed("WEBP")
        }
        let stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: stride,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw OrangeError.writeFailed("WEBP") }
        unpremultiply(&pixels)

        var output: UnsafeMutablePointer<UInt8>?
        let size = pixels.withUnsafeBufferPointer { rgba -> Int in
            if lossless {
                return WebPEncodeLosslessRGBA(rgba.baseAddress, Int32(width), Int32(height), Int32(stride), &output)
            }
            let q = Float(min(max(quality, 0.05), 1) * 100)
            return WebPEncodeRGBA(rgba.baseAddress, Int32(width), Int32(height), Int32(stride), q, &output)
        }
        guard size > 0, let output else { throw OrangeError.writeFailed("WEBP") }
        defer { WebPFree(output) }
        return Data(bytes: output, count: size)
    }

    private static func unpremultiply(_ pixels: inout [UInt8]) {
        var index = 0
        while index < pixels.count {
            let alpha = Int(pixels[index + 3])
            if alpha > 0 && alpha < 255 {
                for channel in 0..<3 {
                    pixels[index + channel] = UInt8(min(255, (Int(pixels[index + channel]) * 255 + alpha / 2) / alpha))
                }
            }
            index += 4
        }
    }
}
