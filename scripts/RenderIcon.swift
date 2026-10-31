import AppKit
import CoreGraphics
import Foundation

let output = URL(
    fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset",
    isDirectory: true
)
let sourceURL = URL(
    fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Configuration/AppIcon.png"
)
guard let source = NSImage(contentsOf: sourceURL),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Could not read \(sourceURL.path)\n", stderr)
    exit(1)
}
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
    guard let image = render(pixels, from: sourceCG),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fputs("Could not render \(name)\n", stderr)
        exit(1)
    }
    try data.write(to: output.appendingPathComponent(name))
}

func render(_ pixels: Int, from source: CGImage) -> CGImage? {
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
    context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return context.makeImage()
}
