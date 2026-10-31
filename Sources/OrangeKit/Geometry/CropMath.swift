import CoreGraphics
import Foundation

public enum CropMath {
    public static func fittedRect(imageSize: CGSize, in viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return .zero
        }
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (viewSize.width - drawn.width) / 2,
            y: (viewSize.height - drawn.height) / 2
        )
        return CGRect(origin: origin, size: drawn)
    }

    /// Selection uses the view's top-left origin. The result is normalized to the fitted image, top-left origin.
    public static func normalizedRect(selection: CGRect, imageSize: CGSize, viewSize: CGSize) -> CGRect {
        let fitted = fittedRect(imageSize: imageSize, in: viewSize)
        guard fitted.width > 0, fitted.height > 0 else { return .zero }
        let clipped = selection.intersection(fitted)
        guard !clipped.isNull, clipped.width > 0.5, clipped.height > 0.5 else { return .zero }
        return CGRect(
            x: (clipped.minX - fitted.minX) / fitted.width,
            y: (clipped.minY - fitted.minY) / fitted.height,
            width: clipped.width / fitted.width,
            height: clipped.height / fitted.height
        )
    }

    /// Converts a top-left normalized rect into Core Graphics pixel space (bottom-left origin).
    public static func pixelRect(normalizedTopLeft: CGRect, imageSize: CGSize) -> CGRect {
        let width = normalizedTopLeft.width * imageSize.width
        let height = normalizedTopLeft.height * imageSize.height
        let x = normalizedTopLeft.origin.x * imageSize.width
        let y = (1 - normalizedTopLeft.origin.y) * imageSize.height - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
