import AppKit
import CoreGraphics
import Foundation

let output = URL(
    fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset",
    isDirectory: true
)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let sizes = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in sizes {
    guard let image = render(pixels),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fputs("Could not render \(name)\n", stderr)
        exit(1)
    }
    try data.write(to: output.appendingPathComponent(name))
}

func render(_ pixels: Int) -> CGImage? {
    let size = CGFloat(pixels)
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    let colors = [
        CGColor(srgbRed: 1, green: 0.62, blue: 0.30, alpha: 1),
        CGColor(srgbRed: 0.86, green: 0.24, blue: 0.04, alpha: 1)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: size * 0.15, y: size * 0.9),
            end: CGPoint(x: size * 0.9, y: size * 0.1),
            options: []
        )
    }
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.96))
    context.setLineWidth(max(size * 0.055, 1))
    let inset = size * 0.30
    context.strokeEllipse(in: CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: inset, dy: inset))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    let hub = size * 0.085
    context.fillEllipse(in: CGRect(x: (size - hub) / 2, y: (size - hub) / 2, width: hub, height: hub))
    return context.makeImage()
}
