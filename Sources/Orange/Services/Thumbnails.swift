import AppKit
import OrangeKit
import QuickLookThumbnailing
import SwiftUI

@MainActor
final class Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL, side: CGFloat) async -> NSImage {
        let key = "\(url.path)|\(Int(side))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: .thumbnail
        )
        let image: NSImage
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = representation.nsImage
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

struct FileThumbnail: View {
    var url: URL
    var side: CGFloat = 64
    var radius: CGFloat = 12
    @State var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.quaternary)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: url) {
            image = await Thumbnails.shared.image(for: url, side: side)
        }
    }
}

/// Loads a downscaled CGImage off the main thread.
enum PreviewLoader {
    static func image(_ url: URL, maxPixel: Int = 1800) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            try? ImageEngine.load(url, maxPixel: maxPixel)
        }.value
    }
}
