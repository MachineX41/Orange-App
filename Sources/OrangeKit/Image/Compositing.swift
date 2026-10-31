import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation

// MARK: Background

public enum BackdropFill: Hashable, Codable, Sendable {
    case solid(RGBA)
    case gradient([RGBA])
    case image(String)
}

public struct BackdropStyle: Hashable, Codable, Sendable {
    public enum Aspect: String, CaseIterable, Codable, Sendable {
        case auto, square, landscape, portrait, story

        public var ratio: CGFloat? {
            switch self {
            case .auto: nil
            case .square: 1
            case .landscape: 16.0 / 9.0
            case .portrait: 4.0 / 5.0
            case .story: 9.0 / 16.0
            }
        }
    }

    public var fill: BackdropFill = .gradient([RGBA(hex: 0xFFC46B), RGBA(hex: 0xF0522B)])
    public var padding = 0.12
    public var cornerRadius = 0.04
    public var shadow = 0.5
    public var aspect: Aspect = .auto

    public init() {}
}

public enum Backdrop {
    public static func render(_ image: CGImage, style: BackdropStyle) throws -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let pad = max(width, height) * style.padding
        var canvasWidth = width + pad * 2
        var canvasHeight = height + pad * 2
        if let ratio = style.aspect.ratio {
            if canvasWidth / canvasHeight < ratio {
                canvasWidth = canvasHeight * ratio
            } else {
                canvasHeight = canvasWidth / ratio
            }
        }
        let canvas = CGRect(x: 0, y: 0, width: canvasWidth.rounded(), height: canvasHeight.rounded())
        return try ImageEngine.render(width: Int(canvas.width), height: Int(canvas.height)) { context in
            paint(style.fill, in: canvas, context: context)
            let rect = CGRect(
                x: (canvas.width - width) / 2,
                y: (canvas.height - height) / 2,
                width: width,
                height: height
            )
            let radius = min(width, height) * style.cornerRadius
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            if style.shadow > 0 {
                let side = max(width, height)
                context.saveGState()
                context.setShadow(
                    offset: CGSize(width: 0, height: -side * 0.018 * style.shadow),
                    blur: side * 0.06 * style.shadow,
                    color: CGColor(gray: 0, alpha: 0.42 * style.shadow)
                )
                context.addPath(path)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fillPath()
                context.restoreGState()
            }
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.draw(image, in: rect)
            context.restoreGState()
        }
    }

    public static func paint(_ fill: BackdropFill, in rect: CGRect, context: CGContext) {
        switch fill {
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case .gradient(let colors):
            let cg = colors.map(\.cgColor) as CFArray
            if let gradient = CGGradient(colorsSpace: ImageEngine.sRGB, colors: cg, locations: nil) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.minX, y: rect.maxY),
                    end: CGPoint(x: rect.maxX, y: rect.minY),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
        case .image(let path):
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(rect)
            if let image = try? ImageEngine.load(URL(fileURLWithPath: path), maxPixel: 4096) {
                context.saveGState()
                context.clip(to: rect)
                context.draw(image, in: Collage.aspectFill(CGSize(width: image.width, height: image.height), in: rect))
                context.restoreGState()
            }
        }
    }
}

// MARK: Redaction

public enum RedactStyle: String, CaseIterable, Codable, Sendable {
    case pixelate, blur, solid
}

public enum Redactor {
    public static func apply(_ regions: [CGRect], style: RedactStyle, to image: CIImage) -> CIImage {
        let extent = image.extent
        var output = image
        for region in regions {
            let pixels = CropMath.pixelRect(normalizedTopLeft: region, imageSize: extent.size)
                .offsetBy(dx: extent.minX, dy: extent.minY)
                .intersection(extent)
                .integral
            guard pixels.width >= 1, pixels.height >= 1 else { continue }
            let side = min(pixels.width, pixels.height)
            let patch: CIImage
            switch style {
            case .pixelate:
                let filter = CIFilter.pixellate()
                filter.inputImage = image.clampedToExtent()
                filter.scale = Float(max(6, side / 8))
                filter.center = CGPoint(x: pixels.minX, y: pixels.minY)
                patch = filter.outputImage ?? image
            case .blur:
                patch = image.clampedToExtent().applyingGaussianBlur(sigma: Double(max(10, side / 4)))
            case .solid:
                patch = CIImage(color: CIColor(red: 0.06, green: 0.06, blue: 0.07))
            }
            output = patch.cropped(to: pixels).composited(over: output)
        }
        return output.cropped(to: extent)
    }

    public static func render(_ regions: [CGRect], style: RedactStyle, image: CGImage) throws -> CGImage {
        let input = CIImage(cgImage: image)
        return try CoreImageKit.cgImage(apply(regions, style: style, to: input), extent: input.extent)
    }
}

// MARK: Collage

public struct CollageStyle: Hashable, Codable, Sendable {
    public var columns = 0
    public var spacing = 0.02
    public var cornerRadius = 0.04
    public var background = RGBA(1, 1, 1)
    public var cellAspect = 1.0
    public var width = 2400

    public init() {}
}

public enum Collage {
    public static func render(_ images: [CGImage], style: CollageStyle) throws -> CGImage {
        guard !images.isEmpty else { throw OrangeError.empty }
        let count = images.count
        let columns = style.columns > 0 ? min(style.columns, count) : Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let width = CGFloat(style.width)
        let gap = width * style.spacing
        let cellWidth = (width - gap * CGFloat(columns + 1)) / CGFloat(columns)
        let cellHeight = cellWidth / style.cellAspect
        let height = (cellHeight * CGFloat(rows) + gap * CGFloat(rows + 1)).rounded()
        return try ImageEngine.render(width: Int(width), height: Int(height)) { context in
            context.setFillColor(style.background.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for (index, image) in images.enumerated() {
                let row = index / columns
                let column = index % columns
                let inRow = row == rows - 1 ? count - row * columns : columns
                let offset = CGFloat(columns - inRow) * (cellWidth + gap) / 2
                let x = gap + CGFloat(column) * (cellWidth + gap) + offset
                let top = gap + CGFloat(row) * (cellHeight + gap)
                let cell = CGRect(x: x, y: height - top - cellHeight, width: cellWidth, height: cellHeight)
                let radius = min(cellWidth, cellHeight) * style.cornerRadius
                context.saveGState()
                context.addPath(CGPath(roundedRect: cell, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.clip()
                context.draw(image, in: aspectFill(CGSize(width: image.width, height: image.height), in: cell))
                context.restoreGState()
            }
        }
    }

    public static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: rect.midX - drawn.width / 2,
            y: rect.midY - drawn.height / 2,
            width: drawn.width,
            height: drawn.height
        )
    }
}

// MARK: Annotation

public enum MarkTool: String, CaseIterable, Codable, Sendable {
    case pen, highlighter, rectangle, ellipse, arrow, text
}

public struct Mark: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var tool: MarkTool
    /// Normalized points, top-left origin.
    public var points: [CGPoint]
    public var color: RGBA
    /// Fraction of the image’s shorter side.
    public var width: Double
    public var text: String

    public init(id: UUID = UUID(), tool: MarkTool, points: [CGPoint], color: RGBA, width: Double, text: String = "") {
        self.id = id
        self.tool = tool
        self.points = points
        self.color = color
        self.width = width
        self.text = text
    }
}

public enum AnnotationRenderer {
    public static func render(_ marks: [Mark], onto image: CGImage) throws -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        return try ImageEngine.render(width: image.width, height: image.height) { context in
            context.draw(image, in: CGRect(origin: .zero, size: size))
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            for mark in marks {
                draw(mark, in: context, size: size)
            }
        }
    }

    /// Draws into a context whose origin is top-left with y growing downward.
    public static func draw(_ mark: Mark, in context: CGContext, size: CGSize) {
        guard let first = mark.points.first else { return }
        let base = min(size.width, size.height)
        let points = mark.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let start = points[0]
        let end = points.last ?? start
        let lineWidth = max(1, mark.width * base)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(mark.color.cgColor)
        context.setLineWidth(lineWidth)
        switch mark.tool {
        case .pen:
            context.addLines(between: points)
            context.strokePath()
        case .highlighter:
            context.setBlendMode(.multiply)
            context.setStrokeColor(mark.color.withAlpha(0.42).cgColor)
            context.setLineWidth(lineWidth * 3.2)
            context.setLineCap(.square)
            context.addLines(between: points)
            context.strokePath()
        case .rectangle:
            context.stroke(CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
        case .ellipse:
            context.strokeEllipse(in: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
        case .arrow:
            let angle = atan2(end.y - start.y, end.x - start.x)
            let head = max(lineWidth * 4, base * 0.025)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
            context.setFillColor(mark.color.cgColor)
            context.move(to: end)
            context.addLine(to: CGPoint(x: end.x - head * cos(angle - .pi / 7), y: end.y - head * sin(angle - .pi / 7)))
            context.addLine(to: CGPoint(x: end.x - head * cos(angle + .pi / 7), y: end.y - head * sin(angle + .pi / 7)))
            context.closePath()
            context.fillPath()
        case .text:
            guard !mark.text.isEmpty else { break }
            let fontSize = max(8, lineWidth * 7)
            let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: mark.color.cgColor
            ]
            let string = CFAttributedStringCreate(nil, mark.text as CFString, attributes as CFDictionary)!
            let line = CTLineCreateWithAttributedString(string)
            let ascent = CTFontGetAscent(font)
            context.translateBy(x: first.x * size.width, y: first.y * size.height + ascent)
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}
