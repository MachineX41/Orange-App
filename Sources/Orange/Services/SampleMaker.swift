import CoreGraphics
import Foundation
import ImageIO
import OrangeKit
import UniformTypeIdentifiers

enum SampleMaker {
    static func write() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Orange/Samples", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Orange Sample.png")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let width = 1600
        let height = 1000
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw OrangeError.writeFailed("sample")
        }
        let colors = [
            CGColor(srgbRed: 0.98, green: 0.93, blue: 0.86, alpha: 1),
            CGColor(srgbRed: 0.95, green: 0.42, blue: 0.12, alpha: 1)
        ] as CFArray
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        )
        if let gradient {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: height),
                end: CGPoint(x: width, y: 0),
                options: []
            )
        }
        context.setFillColor(CGColor(gray: 1, alpha: 0.92))
        context.fillEllipse(in: CGRect(x: 620, y: 250, width: 360, height: 360))
        context.setStrokeColor(CGColor(srgbRed: 0.89, green: 0.32, blue: 0.06, alpha: 1))
        context.setLineWidth(28)
        context.strokeEllipse(in: CGRect(x: 700, y: 330, width: 200, height: 200))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw OrangeError.writeFailed("sample")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw OrangeError.writeFailed("sample")
        }
        return url
    }
}
