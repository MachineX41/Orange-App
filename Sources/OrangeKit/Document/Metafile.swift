import AppKit
import CoreText
import Foundation
import ImageIO

/// Draws Windows metafiles (WMF and EMF) as vectors. macOS has no decoder for them, and older
/// Office documents use them for equations, charts and diagrams.
public final class Metafile {
    enum Kind { case wmf, emf }

    let bytes: [UInt8]
    let kind: Kind
    /// Natural size in points.
    public let size: CGSize

    public convenience init?(url: URL) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        self.init(data: data)
    }

    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 40 else { return nil }
        let reader = ByteReader(bytes)
        if reader.u32(0) == 1, reader.u32(40) == 0x464D_4520 {
            kind = .emf
            let frame = reader.rect32(24)
            let width = CGFloat(frame.right - frame.left) / 100 / 25.4 * 72
            let height = CGFloat(frame.bottom - frame.top) / 100 / 25.4 * 72
            guard width > 0.5, height > 0.5 else { return nil }
            size = CGSize(width: width, height: height)
        } else if reader.u32(0) == 0x9AC6_CDD7 {
            kind = .wmf
            let left = reader.i16(6), top = reader.i16(8), right = reader.i16(10), bottom = reader.i16(12)
            let inch = max(CGFloat(reader.u16(14)), 1)
            let width = abs(CGFloat(right) - CGFloat(left)) / inch * 72
            let height = abs(CGFloat(bottom) - CGFloat(top)) / inch * 72
            guard width > 0.5, height > 0.5 else { return nil }
            size = CGSize(width: width, height: height)
        } else if reader.u16(0) == 1 || reader.u16(0) == 2, reader.u16(2) == 9 {
            kind = .wmf
            let window = WMFPlayer.scanWindow(reader, start: 0) ?? CGRect(x: 0, y: 0, width: 800, height: 600)
            size = CGSize(width: abs(window.width) * 72 / 96, height: abs(window.height) * 72 / 96)
        } else {
            return nil
        }
        self.bytes = bytes
    }

    /// Draws into `rect` of a context whose y axis points down.
    public func draw(in context: CGContext, rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        context.clip(to: rect.insetBy(dx: -rect.width * 0.02 - 1, dy: -rect.height * 0.02 - 1))
        let painter = GDIPainter(context: context)
        switch kind {
        case .emf:
            var player = EMFPlayer(reader: ByteReader(bytes), painter: painter, target: rect)
            player.play()
        case .wmf:
            var player = WMFPlayer(reader: ByteReader(bytes), painter: painter, target: rect)
            player.play()
        }
        context.restoreGState()
    }

    /// Renders the drawing at `scale` pixels per point on a white or transparent background.
    public func image(scale: CGFloat = 2, opaque: Bool = false) throws -> CGImage {
        let width = max(Int((size.width * scale).rounded()), 1)
        let height = max(Int((size.height * scale).rounded()), 1)
        guard width * height < 12_000 * 12_000 else { throw OrangeError.unsupported("WMF") }
        return try ImageEngine.render(width: width, height: height) { context in
            if opaque {
                context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: scale, y: -scale)
            draw(in: context, rect: CGRect(origin: .zero, size: size))
        }
    }

    public func writePDF(to url: URL) throws {
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextCreator as String: "Orange"] as CFDictionary) else {
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
        context.beginPDFPage(nil)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        draw(in: context, rect: box)
        context.endPDFPage()
        context.closePDF()
    }

    public static func isMetafile(_ url: URL) -> Bool {
        ["wmf", "emf"].contains(url.pathExtension.lowercased())
    }
}

// MARK: Reader

struct ByteReader {
    let bytes: [UInt8]
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var count: Int { bytes.count }

    func u8(_ offset: Int) -> UInt8 {
        offset >= 0 && offset < bytes.count ? bytes[offset] : 0
    }

    func u16(_ offset: Int) -> UInt16 {
        UInt16(u8(offset)) | UInt16(u8(offset + 1)) << 8
    }

    func i16(_ offset: Int) -> Int16 { Int16(bitPattern: u16(offset)) }

    func u32(_ offset: Int) -> UInt32 {
        UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16
    }

    func i32(_ offset: Int) -> Int32 { Int32(bitPattern: u32(offset)) }

    func f32(_ offset: Int) -> CGFloat { CGFloat(Float(bitPattern: u32(offset))) }

    func rect32(_ offset: Int) -> (left: Int32, top: Int32, right: Int32, bottom: Int32) {
        (i32(offset), i32(offset + 4), i32(offset + 8), i32(offset + 12))
    }

    func slice(_ offset: Int, _ length: Int) -> [UInt8] {
        guard offset >= 0, length > 0, offset < bytes.count else { return [] }
        return Array(bytes[offset..<min(offset + length, bytes.count)])
    }
}

// MARK: GDI state

struct GDIPen {
    var style: UInt32 = 0
    var width: CGFloat = 0
    var color = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    var visible: Bool { style & 0x0F != 5 }
}

struct GDIBrush {
    var style: UInt32 = 0
    var color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    var hatch: UInt32 = 0
    var visible: Bool { style != 1 }
}

struct GDIFont {
    var height: CGFloat = -12
    var escapement: CGFloat = 0
    var weight: Int = 400
    var italic = false
    var underline = false
    var strike = false
    var charset: UInt8 = 0
    var face = "Arial"
}

enum GDIObject {
    case pen(GDIPen)
    case brush(GDIBrush)
    case font(GDIFont)
    case other
}

struct GDIState {
    var pen = GDIPen()
    var brush = GDIBrush()
    var font = GDIFont()
    var textColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    var backColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    var opaqueBackground = false
    var textAlign: UInt32 = 0
    var evenOdd = true
    var position = CGPoint.zero
    var mapMode: UInt32 = 1
    var windowOrigin = CGPoint.zero
    var windowExtent = CGSize(width: 1, height: 1)
    var viewportOrigin = CGPoint.zero
    var viewportExtent = CGSize(width: 1, height: 1)
    var windowSet = false
    var world = CGAffineTransform.identity
    var clipRect: CGRect?
    var clipPath: CGPath?
    var arcClockwise = false
}

/// Shared drawing back end for both metafile formats. Geometry arrives in logical units and is
/// mapped to the target with `transform`.
final class GDIPainter {
    let context: CGContext
    var state = GDIState()
    var stack: [GDIState] = []
    var transform = CGAffineTransform.identity
    /// Target points per device pixel, for cosmetic pens.
    var devicePixel: CGFloat = 0.75
    var bracket: CGMutablePath?

    init(context: CGContext) {
        self.context = context
    }

    func color(_ ref: UInt32) -> CGColor {
        CGColor(
            srgbRed: CGFloat(ref & 0xFF) / 255,
            green: CGFloat((ref >> 8) & 0xFF) / 255,
            blue: CGFloat((ref >> 16) & 0xFF) / 255,
            alpha: 1
        )
    }

    func save() { stack.append(state) }

    func restore(_ relative: Int) {
        guard !stack.isEmpty else { return }
        let steps = relative < 0 ? -relative : max(stack.count - relative, 1)
        for _ in 0..<min(steps, stack.count) { state = stack.removeLast() }
    }

    var scale: CGFloat {
        let t = transform
        return sqrt(abs(t.a * t.d - t.b * t.c))
    }

    var penWidth: CGFloat {
        let logical = state.pen.width
        let geometric = state.pen.style & 0x10000 != 0
        let width = logical <= 0 || (!geometric && logical <= 1) ? devicePixel : logical * scale
        return max(width, 0.25)
    }

    // MARK: Primitives

    func fillAndStroke(_ logicalPath: CGPath, fill: Bool, stroke: Bool) {
        var t = transform
        guard let path = logicalPath.copy(using: &t) else { return }
        if bracket != nil {
            bracket?.addPath(path)
            return
        }
        paint(path, fill: fill, stroke: stroke)
    }

    func paint(_ path: CGPath, fill: Bool, stroke: Bool) {
        guard !path.isEmpty else { return }
        context.saveGState()
        applyClip()
        if fill, state.brush.visible {
            context.addPath(path)
            var color = state.brush.color
            if state.brush.style == 2 { color = color.copy(alpha: 0.35) ?? color }
            context.setFillColor(color)
            context.fillPath(using: state.evenOdd ? .evenOdd : .winding)
        }
        if stroke, state.pen.visible {
            context.addPath(path)
            applyPen()
            context.strokePath()
        }
        context.restoreGState()
    }

    func applyPen() {
        let width = penWidth
        context.setLineWidth(width)
        context.setStrokeColor(state.pen.color)
        let style = state.pen.style
        let geometric = style & 0x10000 != 0
        switch style & 0xF00 {
        case 0x100: context.setLineCap(.square)
        case 0x200: context.setLineCap(.butt)
        default: context.setLineCap(geometric ? .round : .round)
        }
        switch style & 0xF000 {
        case 0x1000: context.setLineJoin(.bevel)
        case 0x2000: context.setLineJoin(.miter)
        default: context.setLineJoin(.round)
        }
        let unit = max(width, devicePixel)
        let pattern: [CGFloat]
        switch style & 0x0F {
        case 1: pattern = [6, 2]
        case 2: pattern = [1, 2]
        case 3: pattern = [6, 2, 1, 2]
        case 4: pattern = [6, 2, 1, 2, 1, 2]
        default: pattern = []
        }
        if !pattern.isEmpty {
            context.setLineCap(.butt)
            context.setLineDash(phase: 0, lengths: pattern.map { $0 * unit * 1.5 })
        }
    }

    func applyClip() {
        if let rect = state.clipRect { context.clip(to: rect) }
        if let path = state.clipPath {
            context.addPath(path)
            context.clip()
        }
    }

    func polyline(_ points: [CGPoint], closed: Bool) {
        guard points.count >= 2 else { return }
        let path = CGMutablePath()
        path.addLines(between: points)
        if closed { path.closeSubpath() }
        fillAndStroke(path, fill: closed, stroke: true)
    }

    func polyPolygon(_ polygons: [[CGPoint]]) {
        let path = CGMutablePath()
        for polygon in polygons where polygon.count >= 2 {
            path.addLines(between: polygon)
            path.closeSubpath()
        }
        fillAndStroke(path, fill: true, stroke: true)
    }

    func bezier(_ points: [CGPoint], from start: CGPoint?) {
        let path = CGMutablePath()
        var index = 0
        if let start {
            path.move(to: start)
        } else {
            guard let first = points.first else { return }
            path.move(to: first)
            index = 1
        }
        while index + 2 < points.count {
            path.addCurve(to: points[index + 2], control1: points[index], control2: points[index + 1])
            index += 3
        }
        fillAndStroke(path, fill: false, stroke: true)
    }

    func line(to point: CGPoint) {
        if let path = bracket {
            if path.isEmpty { path.move(to: state.position.applying(transform)) }
            path.addLine(to: point.applying(transform))
        } else {
            let path = CGMutablePath()
            path.move(to: state.position)
            path.addLine(to: point)
            fillAndStroke(path, fill: false, stroke: true)
        }
        state.position = point
    }

    func move(to point: CGPoint) {
        state.position = point
        if bracket != nil { bracket!.move(to: point.applying(transform)) }
    }

    func rectangle(_ rect: CGRect) {
        fillAndStroke(CGPath(rect: rect.standardized, transform: nil), fill: true, stroke: true)
    }

    func roundRect(_ rect: CGRect, corner: CGSize) {
        let r = rect.standardized
        let w = min(abs(corner.width) / 2, r.width / 2), h = min(abs(corner.height) / 2, r.height / 2)
        fillAndStroke(CGPath(roundedRect: r, cornerWidth: w, cornerHeight: h, transform: nil), fill: true, stroke: true)
    }

    func ellipse(_ rect: CGRect) {
        fillAndStroke(CGPath(ellipseIn: rect.standardized, transform: nil), fill: true, stroke: true)
    }

    /// `kind` 0 = arc, 1 = chord, 2 = pie.
    func arc(_ rect: CGRect, start: CGPoint, end: CGPoint, kind: Int) {
        let r = rect.standardized
        guard r.width > 0, r.height > 0 else { return }
        let center = CGPoint(x: r.midX, y: r.midY)
        let rx = r.width / 2, ry = r.height / 2
        let a1 = atan2((start.y - center.y) / ry, (start.x - center.x) / rx)
        var a2 = atan2((end.y - center.y) / ry, (end.x - center.x) / rx)
        let flippedY = transform.d < 0
        let visualCounterClockwise = !state.arcClockwise
        let decreasing = visualCounterClockwise != flippedY
        if decreasing {
            while a2 >= a1 { a2 -= 2 * .pi }
        } else {
            while a2 <= a1 { a2 += 2 * .pi }
        }
        let path = CGMutablePath()
        let unit = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: rx, y: ry)
        if kind == 2 { path.move(to: center) }
        path.addRelativeArc(center: .zero, radius: 1, startAngle: a1, delta: a2 - a1, transform: unit)
        if kind > 0 { path.closeSubpath() }
        fillAndStroke(path, fill: kind > 0, stroke: true)
    }

    // MARK: Paths

    func beginPath() { bracket = CGMutablePath() }

    func endPath() {}

    func closeFigure() { bracket?.closeSubpath() }

    func finishPath(fill: Bool, stroke: Bool) {
        guard let path = bracket else { return }
        bracket = nil
        paint(path, fill: fill, stroke: stroke)
    }

    func clipToPath() {
        guard let path = bracket else { return }
        bracket = nil
        state.clipPath = path
    }

    func intersectClip(_ logical: CGRect) {
        let rect = logical.standardized.applying(transform).standardized
        state.clipRect = state.clipRect.map { $0.intersection(rect) } ?? rect
    }

    func resetClip() {
        state.clipRect = nil
        state.clipPath = nil
    }

    // MARK: Text

    func text(_ raw: String, at logical: CGPoint, advances: [CGFloat]?, opaqueRect: CGRect?) {
        var origin = logical
        if state.textAlign & 1 != 0 { origin = state.position }
        let font = state.font
        let string = MetafileText.map(raw, face: font.face, charset: font.charset)
        if let opaqueRect, state.opaqueBackground {
            context.saveGState()
            context.setFillColor(state.backColor)
            context.fill(opaqueRect.standardized.applying(transform))
            context.restoreGState()
        }
        guard !string.isEmpty else { return }

        let t = transform
        let vertical = hypot(t.c, t.d)
        let horizontal = hypot(t.a, t.b)
        var logicalHeight = abs(font.height)
        if logicalHeight == 0 { logicalHeight = 12 / max(vertical, 0.0001) }
        let ctFont0 = MetafileText.font(face: font.face, size: 100, bold: font.weight >= 600, italic: font.italic)
        let em: CGFloat
        if font.height > 0 {
            let cell = (CTFontGetAscent(ctFont0) + CTFontGetDescent(ctFont0)) / 100
            em = logicalHeight / max(cell, 0.5)
        } else {
            em = logicalHeight
        }
        let size = max(em * vertical, 0.5)
        let ctFont = MetafileText.font(face: font.face, size: size, bold: font.weight >= 600, italic: font.italic)
        let point = origin.applying(t)
        let angle = -font.escapement / 10 * .pi / 180
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): state.textColor
        ]

        let characters = Array(string)
        var positions: [CGFloat] = []
        var total: CGFloat = 0
        if let advances, advances.count >= characters.count {
            for index in characters.indices {
                positions.append(total)
                total += advances[index] * horizontal
            }
        } else {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
            total = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        let ascent = CTFontGetAscent(ctFont), descent = CTFontGetDescent(ctFont)
        var dx: CGFloat = 0
        switch state.textAlign & 6 {
        case 6: dx = -total / 2
        case 2: dx = -total
        default: dx = 0
        }
        var baseline: CGFloat = 0
        switch state.textAlign & 24 {
        case 24: baseline = 0
        case 8: baseline = descent
        default: baseline = -ascent
        }

        context.saveGState()
        applyClip()
        context.translateBy(x: point.x, y: point.y)
        context.rotate(by: angle)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        if positions.isEmpty {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
            context.textPosition = CGPoint(x: dx, y: baseline)
            CTLineDraw(line, context)
        } else {
            for (index, character) in characters.enumerated() where !character.isWhitespace {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(character), attributes: attributes))
                context.textPosition = CGPoint(x: dx + positions[index], y: baseline)
                CTLineDraw(line, context)
            }
        }
        if font.underline || font.strike {
            context.setStrokeColor(state.textColor)
            context.setLineWidth(max(size / 16, 0.4))
            if font.underline {
                context.move(to: CGPoint(x: dx, y: baseline - size * 0.1))
                context.addLine(to: CGPoint(x: dx + total, y: baseline - size * 0.1))
            }
            if font.strike {
                context.move(to: CGPoint(x: dx, y: baseline + size * 0.3))
                context.addLine(to: CGPoint(x: dx + total, y: baseline + size * 0.3))
            }
            context.strokePath()
        }
        context.restoreGState()
        if state.textAlign & 1 != 0 {
            state.position = CGPoint(x: origin.x + total / max(horizontal, 0.0001), y: origin.y)
        }
    }

    // MARK: Bitmaps

    func bitmap(_ image: CGImage?, destination logical: CGRect, source: CGRect?, rop: UInt32) {
        let corners = [
            CGPoint(x: logical.minX, y: logical.minY).applying(transform),
            CGPoint(x: logical.maxX, y: logical.maxY).applying(transform)
        ]
        let target = CGRect(
            x: corners[0].x, y: corners[0].y,
            width: corners[1].x - corners[0].x, height: corners[1].y - corners[0].y
        )
        switch rop {
        case 0x00AA_0029: return
        case 0x0000_0042, 0x00FF_0062:
            context.saveGState()
            applyClip()
            context.setFillColor(rop == 0x42 ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(target.standardized)
            context.restoreGState()
            return
        default: break
        }
        guard let image else {
            if state.brush.visible {
                context.saveGState()
                applyClip()
                context.setFillColor(state.brush.color)
                context.fill(target.standardized)
                context.restoreGState()
            }
            return
        }
        var picture = image
        if let source, source.width > 0, source.height > 0,
           source.integral != CGRect(x: 0, y: 0, width: image.width, height: image.height),
           let cropped = image.cropping(to: source.integral) {
            picture = cropped
        }
        context.saveGState()
        applyClip()
        switch rop {
        case 0x0088_00C6: context.setBlendMode(.multiply)
        case 0x00EE_0086: context.setBlendMode(.lighten)
        case 0x0066_0046: context.setBlendMode(.difference)
        default: break
        }
        context.interpolationQuality = .high
        context.translateBy(x: target.minX, y: target.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(picture, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        context.restoreGState()
    }

    /// Wraps a device-independent bitmap in a BMP file so ImageIO can decode every bit depth and RLE mode.
    static func dib(_ reader: ByteReader, header offset: Int, headerSize: Int, bits: Int, bitsSize: Int) -> CGImage? {
        guard headerSize >= 12, offset > 0 else { return nil }
        let info = reader.slice(offset, headerSize)
        let pixels = reader.slice(bits, bitsSize)
        return dib(info: info, pixels: pixels)
    }

    static func dib(info: [UInt8], pixels: [UInt8]) -> CGImage? {
        guard info.count >= 12, !pixels.isEmpty else { return nil }
        let header = ByteReader(info)
        let compression = info.count >= 20 ? header.u32(16) : 0
        if compression == 4 || compression == 5 {
            guard let source = CGImageSourceCreateWithData(Data(pixels) as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        var file = [UInt8]()
        let total = 14 + info.count + pixels.count
        let offset = 14 + info.count
        file += [0x42, 0x4D]
        file += withUnsafeBytes(of: UInt32(total).littleEndian, Array.init)
        file += [0, 0, 0, 0]
        file += withUnsafeBytes(of: UInt32(offset).littleEndian, Array.init)
        file += info
        file += pixels
        guard let source = CGImageSourceCreateWithData(Data(file) as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return opaqueIfBlank(image)
    }

    /// 32-bit bitmaps in metafiles often leave alpha at zero; treat a fully transparent bitmap as opaque.
    static func opaqueIfBlank(_ image: CGImage) -> CGImage {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst,
              image.width * image.height <= 4_000_000 else { return image }
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return image }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var anyAlpha = false
        for index in stride(from: 3, to: width * height * 4, by: 4) where buffer[index] != 0 {
            anyAlpha = true
            break
        }
        if anyAlpha { return image }
        let rawInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let provider = image.dataProvider,
              let copy = CGImage(
                width: width, height: height, bitsPerComponent: image.bitsPerComponent,
                bitsPerPixel: image.bitsPerPixel, bytesPerRow: image.bytesPerRow,
                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: (image.bitmapInfo.rawValue & ~CGBitmapInfo.alphaInfoMask.rawValue) | rawInfo.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return image }
        return copy
    }
}

// MARK: Text helpers

enum MetafileText {
    static let symbol: [UInt32: String] = [
        0x22: "∀", 0x24: "∃", 0x27: "∋", 0x2A: "∗", 0x2D: "−", 0x40: "≅",
        0x41: "Α", 0x42: "Β", 0x43: "Χ", 0x44: "Δ", 0x45: "Ε", 0x46: "Φ", 0x47: "Γ", 0x48: "Η", 0x49: "Ι",
        0x4A: "ϑ", 0x4B: "Κ", 0x4C: "Λ", 0x4D: "Μ", 0x4E: "Ν", 0x4F: "Ο", 0x50: "Π", 0x51: "Θ", 0x52: "Ρ",
        0x53: "Σ", 0x54: "Τ", 0x55: "Υ", 0x56: "ς", 0x57: "Ω", 0x58: "Ξ", 0x59: "Ψ", 0x5A: "Ζ", 0x5C: "∴",
        0x5E: "⊥", 0x60: "‾",
        0x61: "α", 0x62: "β", 0x63: "χ", 0x64: "δ", 0x65: "ε", 0x66: "φ", 0x67: "γ", 0x68: "η", 0x69: "ι",
        0x6A: "ϕ", 0x6B: "κ", 0x6C: "λ", 0x6D: "μ", 0x6E: "ν", 0x6F: "ο", 0x70: "π", 0x71: "θ", 0x72: "ρ",
        0x73: "σ", 0x74: "τ", 0x75: "υ", 0x76: "ϖ", 0x77: "ω", 0x78: "ξ", 0x79: "ψ", 0x7A: "ζ", 0x7E: "∼",
        0xA1: "ϒ", 0xA2: "′", 0xA3: "≤", 0xA4: "⁄", 0xA5: "∞", 0xA6: "ƒ", 0xA7: "♣", 0xA8: "♦", 0xA9: "♥",
        0xAA: "♠", 0xAB: "↔", 0xAC: "←", 0xAD: "↑", 0xAE: "→", 0xAF: "↓", 0xB0: "°", 0xB1: "±", 0xB2: "″",
        0xB3: "≥", 0xB4: "×", 0xB5: "∝", 0xB6: "∂", 0xB7: "•", 0xB8: "÷", 0xB9: "≠", 0xBA: "≡", 0xBB: "≈",
        0xBC: "…", 0xBD: "⏐", 0xBE: "⎯", 0xBF: "↵", 0xC0: "ℵ", 0xC1: "ℑ", 0xC2: "ℜ", 0xC3: "℘", 0xC4: "⊗",
        0xC5: "⊕", 0xC6: "∅", 0xC7: "∩", 0xC8: "∪", 0xC9: "⊃", 0xCA: "⊇", 0xCB: "⊄", 0xCC: "⊂", 0xCD: "⊆",
        0xCE: "∈", 0xCF: "∉", 0xD0: "∠", 0xD1: "∇", 0xD2: "®", 0xD3: "©", 0xD4: "™", 0xD5: "∏", 0xD6: "√",
        0xD7: "⋅", 0xD8: "¬", 0xD9: "∧", 0xDA: "∨", 0xDB: "⇔", 0xDC: "⇐", 0xDD: "⇑", 0xDE: "⇒", 0xDF: "⇓",
        0xE0: "◊", 0xE1: "〈", 0xE2: "®", 0xE3: "©", 0xE4: "™", 0xE5: "∑", 0xE6: "⎛", 0xE7: "⎜", 0xE8: "⎝",
        0xE9: "⎡", 0xEA: "⎢", 0xEB: "⎣", 0xEC: "⎧", 0xED: "⎨", 0xEE: "⎩", 0xEF: "⎪", 0xF1: "〉", 0xF2: "∫",
        0xF3: "⌠", 0xF4: "⎮", 0xF5: "⌡", 0xF6: "⎞", 0xF7: "⎟", 0xF8: "⎠", 0xF9: "⎤", 0xFA: "⎥", 0xFB: "⎦",
        0xFC: "⎫", 0xFD: "⎬", 0xFE: "⎭"
    ]

    static let mtExtra: [UInt32: String] = [
        0x4C: "…", 0x4D: "⋯", 0x4E: "⋮", 0x4F: "⋰", 0x50: "⋱", 0x6C: "ℓ", 0x26: "∕", 0x3C: "◃", 0x3E: "▹",
        0x5E: "^", 0x7E: "~", 0x2A: "∗", 0x2B: "∔", 0x2D: "∸", 0x41: "⃖", 0x42: "⃗"
    ]

    static let wingdings: [UInt32: String] = [
        0x6C: "●", 0x6E: "■", 0x6F: "□", 0x71: "❑", 0x75: "◆", 0x76: "❖", 0x77: "⬥", 0x9F: "•", 0xA7: "▪",
        0xA8: "◻", 0xD8: "➢", 0xD7: "➢", 0xE0: "➔", 0xE8: "➔", 0xF0: "⇨", 0xFC: "✔", 0xFB: "✘", 0xFE: "☑",
        0x4A: "☺", 0x4C: "☹", 0x46: "☞", 0x43: "👍", 0xB2: "✧", 0xAB: "★", 0x7C: "✓", 0xA1: "○", 0xA4: "◉",
        0x6D: "❍", 0x70: "◻", 0x73: "◆", 0x74: "⧫", 0xDF: "←", 0xE1: "↑", 0xE2: "↓", 0xF3: "⇦"
    ]

    static func isSymbolFace(_ face: String) -> Bool {
        let lower = face.lowercased()
        return lower == "symbol" || lower.hasPrefix("wingdings") || lower == "webdings" || lower == "mt extra"
            || lower.hasPrefix("monotype sorts") || lower == "zapfdingbats"
    }

    static func map(_ text: String, face: String, charset: UInt8) -> String {
        let lower = face.lowercased()
        let table: [UInt32: String]?
        if lower == "symbol" || charset == 2 && !lower.hasPrefix("wingdings") && lower != "mt extra" {
            table = symbol
        } else if lower.hasPrefix("wingdings") || lower == "webdings" || lower.hasPrefix("monotype sorts") {
            table = wingdings
        } else if lower == "mt extra" {
            table = mtExtra
        } else {
            table = nil
        }
        var output = ""
        for scalar in text.unicodeScalars {
            var value = scalar.value
            if value >= 0xF000, value <= 0xF0FF { value -= 0xF000 }
            if let table {
                if let mapped = table[value] { output += mapped; continue }
                if lower == "symbol" || charset == 2 {
                    if value < 0x80, let ascii = Unicode.Scalar(value) { output.unicodeScalars.append(ascii); continue }
                    output += "•"
                    continue
                }
                if value < 0x20 { continue }
                if lower.hasPrefix("wingdings") { output += "•"; continue }
            }
            if let plain = Unicode.Scalar(value) { output.unicodeScalars.append(plain) }
        }
        return output
    }

    static func substitute(_ face: String) -> String {
        let lower = face.lowercased()
        if isSymbolFace(face) { return "Times New Roman" }
        let mapping: [String: String] = [
            "ms sans serif": "Helvetica", "ms serif": "Times New Roman", "system": "Helvetica",
            "fixedsys": "Menlo", "terminal": "Menlo", "courier": "Courier New", "helv": "Helvetica",
            "tms rmn": "Times New Roman", "calibri": "Helvetica Neue", "cambria": "Times New Roman",
            "cambria math": "STIX Two Math", "consolas": "Menlo", "segoe ui": "Helvetica Neue",
            "arial narrow": "Arial Narrow", "century gothic": "Avenir Next", "garamond": "Times New Roman",
            "book antiqua": "Palatino", "lucida console": "Menlo", "ms gothic": "Hiragino Sans",
            "ms mincho": "Hiragino Mincho ProN", "ms pgothic": "Hiragino Sans", "ｍｓ ｐゴシック": "Hiragino Sans",
            "simsun": "Songti SC", "mingliu": "Songti TC", "batang": "AppleMyungjo", "gulim": "Apple SD Gothic Neo"
        ]
        return mapping[lower] ?? face
    }

    private static var cache: [String: CTFont] = [:]
    private static let lock = NSLock()

    static func font(face: String, size: CGFloat, bold: Bool, italic: Bool) -> CTFont {
        let key = "\(face)|\(bold)|\(italic)"
        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached { return CTFontCreateCopyWithAttributes(cached, size, nil, nil) }
        let resolved = FontResolver.font(family: substitute(face), size: 12, bold: bold, italic: italic) as CTFont
        lock.lock()
        cache[key] = resolved
        lock.unlock()
        return CTFontCreateCopyWithAttributes(resolved, size, nil, nil)
    }

    static func decode(_ bytes: [UInt8], charset: UInt8) -> String {
        let encoding: String.Encoding
        switch charset {
        case 162: encoding = .windowsCP1254
        case 161: encoding = .windowsCP1253
        case 204: encoding = .windowsCP1251
        case 238: encoding = .windowsCP1250
        case 128: encoding = .shiftJIS
        case 2: return String(bytes.map { Character(Unicode.Scalar($0)) })
        default: encoding = .windowsCP1252
        }
        return String(bytes: bytes, encoding: encoding) ?? String(bytes.map { Character(Unicode.Scalar($0)) })
    }
}

/// Finds an installed font for an Office family name, falling back to similar Mac fonts.
enum FontResolver {
    private static let families: Set<String> = Set(NSFontManager.shared.availableFontFamilies.map { $0.lowercased() })
    private static var cache: [String: NSFont] = [:]
    private static let lock = NSLock()

    static let fallbacks: [String: String] = [
        "calibri": "Helvetica Neue", "calibri light": "Helvetica Neue", "aptos": "Helvetica Neue",
        "aptos display": "Helvetica Neue", "aptos narrow": "Arial Narrow", "segoe ui": "Helvetica Neue",
        "segoe ui light": "Helvetica Neue", "segoe ui semibold": "Helvetica Neue", "candara": "Optima",
        "corbel": "Avenir Next", "tw cen mt": "Futura", "century gothic": "Avenir Next", "franklin gothic book": "Avenir Next",
        "franklin gothic medium": "Avenir Next", "gill sans mt": "Gill Sans", "open sans": "Helvetica Neue",
        "lato": "Helvetica Neue", "roboto": "Helvetica Neue", "montserrat": "Avenir Next", "poppins": "Avenir Next",
        "source sans pro": "Helvetica Neue", "noto sans": "Helvetica Neue", "inter": "Helvetica Neue",
        "cambria": "Georgia", "cambria math": "STIX Two Math", "constantia": "Georgia", "garamond": "Times New Roman",
        "book antiqua": "Palatino", "palatino linotype": "Palatino", "century schoolbook": "Times New Roman",
        "bookman old style": "Georgia", "noto serif": "Georgia", "source serif pro": "Georgia", "merriweather": "Georgia",
        "playfair display": "Didot", "consolas": "Menlo", "lucida console": "Menlo", "source code pro": "Menlo",
        "cascadia code": "Menlo", "cascadia mono": "Menlo", "fira code": "Menlo", "roboto mono": "Menlo",
        "ms gothic": "Hiragino Sans", "ms pgothic": "Hiragino Sans", "ｍｓ ｐゴシック": "Hiragino Sans", "meiryo": "Hiragino Sans",
        "yu gothic": "Hiragino Sans", "microsoft yahei": "PingFang SC", "simsun": "Songti SC", "malgun gothic": "Apple SD Gothic Neo",
        "arial black": "Arial Black", "impact": "Impact", "symbol": "Times New Roman", "wingdings": "Zapf Dingbats"
    ]

    static func family(_ requested: String) -> String? {
        let name = requested.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if families.contains(name.lowercased()) { return name }
        let lower = name.lowercased()
        if let mapped = fallbacks[lower], families.contains(mapped.lowercased()) { return mapped }
        for (prefix, mapped) in fallbacks where lower.hasPrefix(prefix) && families.contains(mapped.lowercased()) {
            return mapped
        }
        if lower.contains("serif") && !lower.contains("sans") { return "Georgia" }
        if lower.contains("mono") || lower.contains("code") { return "Menlo" }
        return nil
    }

    static func font(family requested: String?, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let key = "\(requested ?? "")|\(bold)|\(italic)"
        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached { return NSFont(descriptor: cached.fontDescriptor, size: size) ?? cached }

        var requestedName = requested ?? ""
        var wantsBold = bold
        let lower = requestedName.lowercased()
        for suffix in [" bold", " semibold", " extrabold", " black", " heavy"] where lower.hasSuffix(suffix) {
            requestedName = String(requestedName.dropLast(suffix.count))
            wantsBold = true
        }
        for suffix in [" light", " medium", " regular", " thin"] where requestedName.lowercased().hasSuffix(suffix) {
            requestedName = String(requestedName.dropLast(suffix.count))
        }
        var traits: NSFontTraitMask = []
        if wantsBold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        var result: NSFont?
        if let family = family(requestedName) ?? family(requested ?? "") {
            result = NSFontManager.shared.font(withFamily: family, traits: traits, weight: wantsBold ? 9 : 5, size: 12)
            if result == nil, let base = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12) {
                result = NSFontManager.shared.convert(base, toHaveTrait: traits)
            }
        }
        if result == nil, let named = NSFont(name: requested ?? "", size: 12) {
            result = traits.isEmpty ? named : NSFontManager.shared.convert(named, toHaveTrait: traits)
        }
        if result == nil {
            let base = NSFont(name: "Helvetica Neue", size: 12) ?? NSFont.systemFont(ofSize: 12)
            result = traits.isEmpty ? base : NSFontManager.shared.convert(base, toHaveTrait: traits)
        }
        let font = result ?? NSFont.systemFont(ofSize: 12)
        lock.lock()
        cache[key] = font
        lock.unlock()
        return NSFont(descriptor: font.fontDescriptor, size: size) ?? font
    }
}

// MARK: EMF

struct EMFPlayer {
    let reader: ByteReader
    let painter: GDIPainter
    let target: CGRect
    var objects: [UInt32: GDIObject] = [:]
    var devicePerMM = CGSize(width: 3.78, height: 3.78)
    var frameDevice = CGRect(x: 0, y: 0, width: 1, height: 1)

    init(reader: ByteReader, painter: GDIPainter, target: CGRect) {
        self.reader = reader
        self.painter = painter
        self.target = target
        let frame = reader.rect32(24)
        let device = CGSize(width: CGFloat(reader.i32(72)), height: CGFloat(reader.i32(76)))
        let millimeters = CGSize(width: CGFloat(reader.i32(80)), height: CGFloat(reader.i32(84)))
        if device.width > 0, device.height > 0, millimeters.width > 0, millimeters.height > 0 {
            devicePerMM = CGSize(width: device.width / millimeters.width, height: device.height / millimeters.height)
        }
        let x0 = CGFloat(frame.left) / 100 * devicePerMM.width
        let y0 = CGFloat(frame.top) / 100 * devicePerMM.height
        let x1 = CGFloat(frame.right) / 100 * devicePerMM.width
        let y1 = CGFloat(frame.bottom) / 100 * devicePerMM.height
        frameDevice = CGRect(x: x0, y: y0, width: max(x1 - x0, 1), height: max(y1 - y0, 1))
    }

    var deviceToTarget: CGAffineTransform {
        CGAffineTransform(translationX: -frameDevice.minX, y: -frameDevice.minY)
            .concatenating(CGAffineTransform(scaleX: target.width / frameDevice.width, y: target.height / frameDevice.height))
            .concatenating(CGAffineTransform(translationX: target.minX, y: target.minY))
    }

    func pageToDevice(_ s: GDIState) -> CGAffineTransform {
        var sx: CGFloat = 1, sy: CGFloat = 1
        switch s.mapMode {
        case 2: sx = 0.1 * devicePerMM.width; sy = -0.1 * devicePerMM.height
        case 3: sx = 0.01 * devicePerMM.width; sy = -0.01 * devicePerMM.height
        case 4: sx = 0.254 * devicePerMM.width; sy = -0.254 * devicePerMM.height
        case 5: sx = 0.0254 * devicePerMM.width; sy = -0.0254 * devicePerMM.height
        case 6: sx = 25.4 / 1440 * devicePerMM.width; sy = -25.4 / 1440 * devicePerMM.height
        case 7, 8:
            let wx = s.windowExtent.width == 0 ? 1 : s.windowExtent.width
            let wy = s.windowExtent.height == 0 ? 1 : s.windowExtent.height
            sx = s.viewportExtent.width / wx
            sy = s.viewportExtent.height / wy
            if s.mapMode == 7 {
                let m = min(abs(sx), abs(sy))
                sx = sx < 0 ? -m : m
                sy = sy < 0 ? -m : m
            }
        default: break
        }
        return CGAffineTransform(translationX: -s.windowOrigin.x, y: -s.windowOrigin.y)
            .concatenating(CGAffineTransform(scaleX: sx, y: sy))
            .concatenating(CGAffineTransform(translationX: s.viewportOrigin.x, y: s.viewportOrigin.y))
    }

    func update() {
        let device = deviceToTarget
        painter.transform = painter.state.world.concatenating(pageToDevice(painter.state)).concatenating(device)
        painter.devicePixel = max(abs(device.a), 0.05)
    }

    func points16(_ offset: Int, count: Int) -> [CGPoint] {
        (0..<max(count, 0)).map { CGPoint(x: CGFloat(reader.i16(offset + $0 * 4)), y: CGFloat(reader.i16(offset + $0 * 4 + 2))) }
    }

    func points32(_ offset: Int, count: Int) -> [CGPoint] {
        (0..<max(count, 0)).map { CGPoint(x: CGFloat(reader.i32(offset + $0 * 8)), y: CGFloat(reader.i32(offset + $0 * 8 + 4))) }
    }

    func rect(_ offset: Int) -> CGRect {
        let r = reader.rect32(offset)
        return CGRect(x: CGFloat(r.left), y: CGFloat(r.top), width: CGFloat(r.right - r.left), height: CGFloat(r.bottom - r.top))
    }

    mutating func play() {
        update()
        var offset = 0
        var guardCount = 0
        while offset + 8 <= reader.count, guardCount < 2_000_000 {
            guardCount += 1
            let type = reader.u32(offset)
            let size = Int(reader.u32(offset + 4))
            guard size >= 8, offset + size <= reader.count + 4 else { break }
            if type == 14 { break }
            handle(type, at: offset, size: size)
            offset += size
        }
    }

    mutating func handle(_ type: UInt32, at o: Int, size: Int) {
        let p = painter
        switch type {
        case 2, 85, 88, 5:
            let count = Int(reader.u32(o + 24))
            let points = type == 2 || type == 5 ? points32(o + 28, count: count) : points16(o + 28, count: count)
            if type == 88 || type == 5 {
                p.bezier(points, from: p.state.position)
                if let last = points.last { p.state.position = last }
            } else {
                p.bezier(points, from: nil)
            }
        case 3, 86:
            let count = Int(reader.u32(o + 24))
            p.polyline(type == 3 ? points32(o + 28, count: count) : points16(o + 28, count: count), closed: true)
        case 4, 87:
            let count = Int(reader.u32(o + 24))
            p.polyline(type == 4 ? points32(o + 28, count: count) : points16(o + 28, count: count), closed: false)
        case 6, 89:
            let count = Int(reader.u32(o + 24))
            let points = type == 6 ? points32(o + 28, count: count) : points16(o + 28, count: count)
            for point in points { p.line(to: point) }
        case 7, 8, 90, 91:
            let polys = Int(reader.u32(o + 24))
            guard polys > 0, polys < 100_000 else { return }
            var counts: [Int] = []
            for index in 0..<polys { counts.append(Int(reader.u32(o + 32 + index * 4))) }
            var cursor = o + 32 + polys * 4
            var groups: [[CGPoint]] = []
            let wide = type == 7 || type == 8
            for count in counts {
                groups.append(wide ? points32(cursor, count: count) : points16(cursor, count: count))
                cursor += count * (wide ? 8 : 4)
            }
            if type == 8 || type == 91 {
                p.polyPolygon(groups)
            } else {
                for group in groups { p.polyline(group, closed: false) }
            }
        case 9:
            p.state.windowExtent = CGSize(width: CGFloat(reader.i32(o + 8)), height: CGFloat(reader.i32(o + 12)))
            update()
        case 10:
            p.state.windowOrigin = CGPoint(x: CGFloat(reader.i32(o + 8)), y: CGFloat(reader.i32(o + 12)))
            update()
        case 11:
            p.state.viewportExtent = CGSize(width: CGFloat(reader.i32(o + 8)), height: CGFloat(reader.i32(o + 12)))
            update()
        case 12:
            p.state.viewportOrigin = CGPoint(x: CGFloat(reader.i32(o + 8)), y: CGFloat(reader.i32(o + 12)))
            update()
        case 31, 32:
            let xNum = CGFloat(reader.i32(o + 8)), xDen = CGFloat(reader.i32(o + 12))
            let yNum = CGFloat(reader.i32(o + 16)), yDen = CGFloat(reader.i32(o + 20))
            guard xDen != 0, yDen != 0 else { return }
            if type == 31 {
                p.state.viewportExtent = CGSize(width: p.state.viewportExtent.width * xNum / xDen, height: p.state.viewportExtent.height * yNum / yDen)
            } else {
                p.state.windowExtent = CGSize(width: p.state.windowExtent.width * xNum / xDen, height: p.state.windowExtent.height * yNum / yDen)
            }
            update()
        case 17:
            p.state.mapMode = reader.u32(o + 8)
            update()
        case 18: p.state.opaqueBackground = reader.u32(o + 8) == 2
        case 19: p.state.evenOdd = reader.u32(o + 8) == 1
        case 22: p.state.textAlign = reader.u32(o + 8)
        case 24: p.state.textColor = p.color(reader.u32(o + 8))
        case 25: p.state.backColor = p.color(reader.u32(o + 8))
        case 27:
            p.move(to: CGPoint(x: CGFloat(reader.i32(o + 8)), y: CGFloat(reader.i32(o + 12))))
        case 30:
            p.intersectClip(rect(o + 8))
        case 33: p.save()
        case 34:
            p.restore(Int(reader.i32(o + 8)))
            update()
        case 35, 36:
            let m = CGAffineTransform(
                a: reader.f32(o + 8), b: reader.f32(o + 12), c: reader.f32(o + 16),
                d: reader.f32(o + 20), tx: reader.f32(o + 24), ty: reader.f32(o + 28)
            )
            if type == 35 {
                p.state.world = m
            } else {
                switch reader.u32(o + 32) {
                case 1: p.state.world = .identity
                case 2: p.state.world = m.concatenating(p.state.world)
                case 3: p.state.world = p.state.world.concatenating(m)
                case 4: p.state.world = m
                default: break
                }
            }
            update()
        case 37:
            let handle = reader.u32(o + 8)
            if handle & 0x8000_0000 != 0 {
                selectStock(handle & 0x7FFF_FFFF)
            } else if let object = objects[handle] {
                select(object)
            }
        case 38:
            var pen = GDIPen()
            pen.style = reader.u32(o + 12)
            pen.width = CGFloat(reader.i32(o + 16))
            pen.color = p.color(reader.u32(o + 24))
            objects[reader.u32(o + 8)] = .pen(pen)
        case 95:
            var pen = GDIPen()
            pen.style = reader.u32(o + 28)
            pen.width = CGFloat(reader.u32(o + 32))
            let brushStyle = reader.u32(o + 36)
            pen.color = p.color(reader.u32(o + 40))
            if brushStyle == 1 { pen.style = (pen.style & ~0x0F) | 5 }
            objects[reader.u32(o + 8)] = .pen(pen)
        case 39:
            var brush = GDIBrush()
            brush.style = reader.u32(o + 12)
            brush.color = p.color(reader.u32(o + 16))
            brush.hatch = reader.u32(o + 20)
            objects[reader.u32(o + 8)] = .brush(brush)
        case 93, 94:
            var brush = GDIBrush()
            brush.style = 0
            brush.color = CGColor(srgbRed: 0.6, green: 0.6, blue: 0.6, alpha: 1)
            objects[reader.u32(o + 8)] = .brush(brush)
        case 82:
            objects[reader.u32(o + 8)] = .font(logFont(o + 12))
        case 40:
            objects[reader.u32(o + 8)] = nil
        case 42:
            p.ellipse(rect(o + 8))
        case 43:
            p.rectangle(rect(o + 8))
        case 44:
            p.roundRect(rect(o + 8), corner: CGSize(width: CGFloat(reader.i32(o + 24)), height: CGFloat(reader.i32(o + 28))))
        case 45, 46, 47, 55:
            let start = CGPoint(x: CGFloat(reader.i32(o + 24)), y: CGFloat(reader.i32(o + 28)))
            let end = CGPoint(x: CGFloat(reader.i32(o + 32)), y: CGFloat(reader.i32(o + 36)))
            p.arc(rect(o + 8), start: start, end: end, kind: type == 47 ? 2 : type == 46 ? 1 : 0)
        case 54:
            p.line(to: CGPoint(x: CGFloat(reader.i32(o + 8)), y: CGFloat(reader.i32(o + 12))))
        case 57:
            p.state.arcClockwise = reader.u32(o + 8) == 2
        case 59: p.beginPath()
        case 60: p.endPath()
        case 61: p.closeFigure()
        case 62: p.finishPath(fill: true, stroke: false)
        case 63: p.finishPath(fill: true, stroke: true)
        case 64: p.finishPath(fill: false, stroke: true)
        case 67: p.clipToPath()
        case 68: p.bracket = nil
        case 75:
            let size = reader.u32(o + 8)
            let mode = reader.u32(o + 12)
            if size == 0 || mode == 5 && size < 32 {
                p.resetClip()
            } else {
                let count = Int(reader.u32(o + 16 + 8))
                var rects: [CGRect] = []
                for index in 0..<min(count, 4096) {
                    let r = rect(o + 16 + 32 + index * 16)
                    rects.append(r.applying(deviceToTarget).standardized)
                }
                if rects.isEmpty { p.resetClip() } else {
                    let path = CGMutablePath()
                    path.addRects(rects)
                    p.state.clipRect = nil
                    p.state.clipPath = path
                }
            }
        case 76, 77, 81, 80:
            bitmapRecord(type, at: o, size: size)
        case 83, 84:
            textRecord(at: o, wide: type == 84)
        default:
            break
        }
    }

    func logFont(_ o: Int) -> GDIFont {
        var font = GDIFont()
        font.height = CGFloat(reader.i32(o))
        font.escapement = CGFloat(reader.i32(o + 8))
        font.weight = Int(reader.i32(o + 16))
        font.italic = reader.u8(o + 20) != 0
        font.underline = reader.u8(o + 21) != 0
        font.strike = reader.u8(o + 22) != 0
        font.charset = reader.u8(o + 23)
        var units: [UInt16] = []
        for index in 0..<32 {
            let unit = reader.u16(o + 28 + index * 2)
            if unit == 0 { break }
            units.append(unit)
        }
        let face = String(decoding: units, as: UTF16.self)
        if !face.isEmpty { font.face = face }
        return font
    }

    func select(_ object: GDIObject) {
        switch object {
        case .pen(let pen): painter.state.pen = pen
        case .brush(let brush): painter.state.brush = brush
        case .font(let font): painter.state.font = font
        case .other: break
        }
    }

    func selectStock(_ index: UInt32) {
        let p = painter
        func gray(_ v: CGFloat) -> CGColor { CGColor(srgbRed: v, green: v, blue: v, alpha: 1) }
        switch index {
        case 0: p.state.brush = GDIBrush(style: 0, color: gray(1))
        case 1: p.state.brush = GDIBrush(style: 0, color: gray(0.75))
        case 2: p.state.brush = GDIBrush(style: 0, color: gray(0.5))
        case 3: p.state.brush = GDIBrush(style: 0, color: gray(0.25))
        case 4: p.state.brush = GDIBrush(style: 0, color: gray(0))
        case 5: p.state.brush = GDIBrush(style: 1)
        case 6: p.state.pen = GDIPen(style: 0, width: 0, color: gray(1))
        case 7: p.state.pen = GDIPen(style: 0, width: 0, color: gray(0))
        case 8: p.state.pen = GDIPen(style: 5)
        case 10, 11, 12, 13, 14, 16, 17: p.state.font = GDIFont()
        default: break
        }
    }

    func bitmapRecord(_ type: UInt32, at o: Int, size: Int) {
        let p = painter
        switch type {
        case 81:
            let x = CGFloat(reader.i32(o + 24)), y = CGFloat(reader.i32(o + 28))
            let xs = CGFloat(reader.i32(o + 32)), ys = CGFloat(reader.i32(o + 36))
            let cxs = CGFloat(reader.i32(o + 40)), cys = CGFloat(reader.i32(o + 44))
            let offBmi = Int(reader.u32(o + 48)), cbBmi = Int(reader.u32(o + 52))
            let offBits = Int(reader.u32(o + 56)), cbBits = Int(reader.u32(o + 60))
            let rop = reader.u32(o + 68)
            let cx = CGFloat(reader.i32(o + 72)), cy = CGFloat(reader.i32(o + 76))
            let image = cbBmi > 0 ? GDIPainter.dib(reader, header: o + offBmi, headerSize: cbBmi, bits: o + offBits, bitsSize: cbBits) : nil
            let source = image.map { sourceRect(xs, ys, cxs, cys, image: $0, header: o + offBmi) }
            p.bitmap(image, destination: CGRect(x: x, y: y, width: cx, height: cy), source: source, rop: rop)
        case 76, 77:
            let x = CGFloat(reader.i32(o + 24)), y = CGFloat(reader.i32(o + 28))
            let cx = CGFloat(reader.i32(o + 32)), cy = CGFloat(reader.i32(o + 36))
            let rop = reader.u32(o + 40)
            let xs = CGFloat(reader.i32(o + 44)), ys = CGFloat(reader.i32(o + 48))
            let offBmi = Int(reader.u32(o + 84)), cbBmi = Int(reader.u32(o + 88))
            let offBits = Int(reader.u32(o + 92)), cbBits = Int(reader.u32(o + 96))
            var cxs = cx, cys = cy
            if type == 77 {
                cxs = CGFloat(reader.i32(o + 100))
                cys = CGFloat(reader.i32(o + 104))
            }
            let image = cbBmi > 0 ? GDIPainter.dib(reader, header: o + offBmi, headerSize: cbBmi, bits: o + offBits, bitsSize: cbBits) : nil
            let source = image.map { sourceRect(xs, ys, cxs, cys, image: $0, header: o + offBmi) }
            p.bitmap(image, destination: CGRect(x: x, y: y, width: cx, height: cy), source: source, rop: image == nil && rop == 0x00F0_0021 ? 0x00F0_0021 : rop)
        case 80:
            let x = CGFloat(reader.i32(o + 24)), y = CGFloat(reader.i32(o + 28))
            let xs = CGFloat(reader.i32(o + 32)), ys = CGFloat(reader.i32(o + 36))
            let cxs = CGFloat(reader.i32(o + 40)), cys = CGFloat(reader.i32(o + 44))
            let offBmi = Int(reader.u32(o + 48)), cbBmi = Int(reader.u32(o + 52))
            let offBits = Int(reader.u32(o + 56)), cbBits = Int(reader.u32(o + 60))
            let image = GDIPainter.dib(reader, header: o + offBmi, headerSize: cbBmi, bits: o + offBits, bitsSize: cbBits)
            let source = image.map { sourceRect(xs, ys, cxs, cys, image: $0, header: o + offBmi) }
            p.bitmap(image, destination: CGRect(x: x, y: y, width: cxs, height: cys), source: source, rop: 0x00CC_0020)
        default:
            break
        }
    }

    func sourceRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, image: CGImage, header: Int) -> CGRect {
        let bottomUp = reader.i32(header + 8) > 0
        let top = bottomUp ? CGFloat(image.height) - y - h : y
        return CGRect(x: x, y: top, width: w, height: h)
    }

    func textRecord(at o: Int, wide: Bool) {
        let x = CGFloat(reader.i32(o + 36)), y = CGFloat(reader.i32(o + 40))
        let count = Int(reader.u32(o + 44))
        let offString = Int(reader.u32(o + 48))
        let options = reader.u32(o + 52)
        let clip = rect(o + 56)
        let offDx = Int(reader.u32(o + 72))
        guard count > 0, count < 100_000 else { return }
        let string: String
        if wide {
            var units: [UInt16] = []
            for index in 0..<count { units.append(reader.u16(o + offString + index * 2)) }
            string = String(decoding: units, as: UTF16.self)
        } else {
            string = MetafileText.decode(reader.slice(o + offString, count), charset: painter.state.font.charset)
        }
        var advances: [CGFloat]?
        if offDx > 0, o + offDx + count * 4 <= reader.count {
            let pdy = options & 0x2000 != 0
            advances = (0..<count).map { CGFloat(reader.i32(o + offDx + $0 * (pdy ? 8 : 4))) }
            if string.count != count { advances = nil }
        }
        painter.text(string, at: CGPoint(x: x, y: y), advances: advances, opaqueRect: options & 0x2 != 0 ? clip : nil)
    }
}

// MARK: WMF

struct WMFPlayer {
    let reader: ByteReader
    let painter: GDIPainter
    let target: CGRect
    var start = 0
    var objects: [GDIObject?] = []
    var bounds: CGRect?

    init(reader: ByteReader, painter: GDIPainter, target: CGRect) {
        self.reader = reader
        self.painter = painter
        self.target = target
        if reader.u32(0) == 0x9AC6_CDD7 {
            start = 22
            let left = CGFloat(reader.i16(6)), top = CGFloat(reader.i16(8))
            let right = CGFloat(reader.i16(10)), bottom = CGFloat(reader.i16(12))
            bounds = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
        let count = Int(reader.u16(start + 10))
        objects = Array(repeating: nil, count: max(count, 1))
    }

    static func scanWindow(_ reader: ByteReader, start: Int) -> CGRect? {
        var offset = start + Int(reader.u16(start + 2)) * 2
        var origin = CGPoint.zero
        var extent: CGSize?
        var steps = 0
        while offset + 6 <= reader.count, steps < 4000 {
            steps += 1
            let size = Int(reader.u32(offset)) * 2
            let function = reader.u16(offset + 4)
            guard size >= 6 else { break }
            if function == 0x020B { origin = CGPoint(x: CGFloat(reader.i16(offset + 8)), y: CGFloat(reader.i16(offset + 6))) }
            if function == 0x020C { extent = CGSize(width: CGFloat(reader.i16(offset + 8)), height: CGFloat(reader.i16(offset + 6))) }
            if function == 0 || extent != nil && function != 0x020B && function != 0x020C && steps > 40 { break }
            offset += size
        }
        guard let extent, extent.width != 0, extent.height != 0 else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    func update() {
        let s = painter.state
        var window = CGRect(origin: s.windowOrigin, size: s.windowExtent)
        if !s.windowSet, let bounds { window = bounds }
        let wx = window.width == 0 ? 1 : window.width
        let wy = window.height == 0 ? 1 : window.height
        let sx = target.width / wx, sy = target.height / wy
        painter.transform = CGAffineTransform(translationX: -window.minX, y: -window.minY)
            .concatenating(CGAffineTransform(scaleX: sx, y: sy))
            .concatenating(CGAffineTransform(translationX: target.minX, y: target.minY))
        painter.devicePixel = max(min(abs(sx), abs(sy)), 0.25)
        if abs(sx) > 1 || abs(sy) > 1 { painter.devicePixel = 0.5 }
    }

    func point(_ offset: Int) -> CGPoint {
        CGPoint(x: CGFloat(reader.i16(offset)), y: CGFloat(reader.i16(offset + 2)))
    }

    /// WMF stores parameters in reverse order: bottom, right, top, left.
    func rectReversed(_ offset: Int) -> CGRect {
        let bottom = CGFloat(reader.i16(offset)), right = CGFloat(reader.i16(offset + 2))
        let top = CGFloat(reader.i16(offset + 4)), left = CGFloat(reader.i16(offset + 6))
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    mutating func add(_ object: GDIObject) {
        if let index = objects.firstIndex(where: { $0 == nil }) {
            objects[index] = object
        } else {
            objects.append(object)
        }
    }

    mutating func play() {
        if let bounds {
            painter.state.windowOrigin = bounds.origin
            painter.state.windowExtent = bounds.size
        }
        update()
        let headerWords = Int(reader.u16(start + 2))
        var offset = start + max(headerWords, 9) * 2
        var steps = 0
        while offset + 6 <= reader.count, steps < 2_000_000 {
            steps += 1
            let size = Int(reader.u32(offset)) * 2
            let function = reader.u16(offset + 4)
            guard size >= 6 else { break }
            if function == 0 { break }
            handle(function, at: offset + 6, size: size - 6)
            offset += size
        }
    }

    mutating func handle(_ function: UInt16, at p: Int, size: Int) {
        let g = painter
        switch function {
        case 0x020B:
            g.state.windowOrigin = CGPoint(x: CGFloat(reader.i16(p + 2)), y: CGFloat(reader.i16(p)))
            g.state.windowSet = true
            update()
        case 0x020C:
            g.state.windowExtent = CGSize(width: CGFloat(reader.i16(p + 2)), height: CGFloat(reader.i16(p)))
            g.state.windowSet = true
            update()
        case 0x020F:
            g.state.windowOrigin.x += CGFloat(reader.i16(p + 2))
            g.state.windowOrigin.y += CGFloat(reader.i16(p))
            update()
        case 0x0410:
            let yDen = CGFloat(reader.i16(p)), yNum = CGFloat(reader.i16(p + 2))
            let xDen = CGFloat(reader.i16(p + 4)), xNum = CGFloat(reader.i16(p + 6))
            if xDen != 0, yDen != 0 {
                g.state.windowExtent = CGSize(width: g.state.windowExtent.width * xNum / xDen, height: g.state.windowExtent.height * yNum / yDen)
                update()
            }
        case 0x020D, 0x020E, 0x0211, 0x0412, 0x0103:
            if function == 0x0103 { g.state.mapMode = UInt32(reader.u16(p)) }
        case 0x001E: g.save()
        case 0x0127:
            g.restore(Int(reader.i16(p)))
            update()
        case 0x0201: g.state.backColor = g.color(reader.u32(p))
        case 0x0209: g.state.textColor = g.color(reader.u32(p))
        case 0x0102: g.state.opaqueBackground = reader.u16(p) == 2
        case 0x0106: g.state.evenOdd = reader.u16(p) == 1
        case 0x012E: g.state.textAlign = UInt32(reader.u16(p))
        case 0x0214:
            g.move(to: CGPoint(x: CGFloat(reader.i16(p + 2)), y: CGFloat(reader.i16(p))))
        case 0x0213:
            g.line(to: CGPoint(x: CGFloat(reader.i16(p + 2)), y: CGFloat(reader.i16(p))))
        case 0x0325, 0x0324:
            let count = Int(reader.i16(p))
            guard count > 0 else { return }
            let points = (0..<count).map { point(p + 2 + $0 * 4) }
            g.polyline(points, closed: function == 0x0324)
        case 0x0538:
            let polys = Int(reader.u16(p))
            guard polys > 0 else { return }
            let counts = (0..<polys).map { Int(reader.u16(p + 2 + $0 * 2)) }
            var cursor = p + 2 + polys * 2
            var groups: [[CGPoint]] = []
            for count in counts {
                groups.append((0..<count).map { point(cursor + $0 * 4) })
                cursor += count * 4
            }
            g.polyPolygon(groups)
        case 0x041B: g.rectangle(rectReversed(p))
        case 0x0418: g.ellipse(rectReversed(p))
        case 0x061C:
            let height = CGFloat(reader.i16(p)), width = CGFloat(reader.i16(p + 2))
            g.roundRect(rectReversed(p + 4), corner: CGSize(width: width, height: height))
        case 0x0817, 0x081A, 0x0830:
            let end = CGPoint(x: CGFloat(reader.i16(p + 2)), y: CGFloat(reader.i16(p)))
            let start = CGPoint(x: CGFloat(reader.i16(p + 6)), y: CGFloat(reader.i16(p + 4)))
            g.arc(rectReversed(p + 8), start: start, end: end, kind: function == 0x081A ? 2 : function == 0x0830 ? 1 : 0)
        case 0x061D:
            let height = CGFloat(reader.i16(p + 4)), width = CGFloat(reader.i16(p + 6))
            let y = CGFloat(reader.i16(p + 8)), x = CGFloat(reader.i16(p + 10))
            g.bitmap(nil, destination: CGRect(x: x, y: y, width: width, height: height), source: nil, rop: reader.u32(p))
        case 0x0521:
            let length = Int(reader.i16(p))
            guard length > 0 else { return }
            let padded = (length + 1) & ~1
            let bytes = reader.slice(p + 2, length)
            let y = CGFloat(reader.i16(p + 2 + padded)), x = CGFloat(reader.i16(p + 4 + padded))
            g.text(MetafileText.decode(bytes, charset: g.state.font.charset), at: CGPoint(x: x, y: y), advances: nil, opaqueRect: nil)
        case 0x0A32:
            let y = CGFloat(reader.i16(p)), x = CGFloat(reader.i16(p + 2))
            let length = Int(reader.i16(p + 4))
            let options = reader.u16(p + 6)
            var cursor = p + 8
            var clip: CGRect?
            if options & 0x6 != 0 {
                let left = CGFloat(reader.i16(cursor)), top = CGFloat(reader.i16(cursor + 2))
                let right = CGFloat(reader.i16(cursor + 4)), bottom = CGFloat(reader.i16(cursor + 6))
                clip = CGRect(x: left, y: top, width: right - left, height: bottom - top)
                cursor += 8
            }
            guard length > 0 else {
                if let clip, options & 0x2 != 0 { g.text("", at: CGPoint(x: x, y: y), advances: nil, opaqueRect: clip) }
                return
            }
            let bytes = reader.slice(cursor, length)
            cursor += (length + 1) & ~1
            let text = MetafileText.decode(bytes, charset: g.state.font.charset)
            var advances: [CGFloat]?
            if cursor + length * 2 <= p + size, text.count == length {
                advances = (0..<length).map { CGFloat(reader.i16(cursor + $0 * 2)) }
            }
            g.text(text, at: CGPoint(x: x, y: y), advances: advances, opaqueRect: options & 0x2 != 0 ? clip : nil)
        case 0x02FA:
            var pen = GDIPen()
            pen.style = UInt32(reader.u16(p))
            pen.width = CGFloat(reader.i16(p + 2))
            pen.color = g.color(reader.u32(p + 6))
            add(.pen(pen))
        case 0x02FC:
            var brush = GDIBrush()
            brush.style = UInt32(reader.u16(p))
            brush.color = g.color(reader.u32(p + 2))
            brush.hatch = UInt32(reader.u16(p + 6))
            add(.brush(brush))
        case 0x02FB:
            var font = GDIFont()
            font.height = CGFloat(reader.i16(p))
            font.escapement = CGFloat(reader.i16(p + 4))
            font.weight = Int(reader.i16(p + 8))
            font.italic = reader.u8(p + 10) != 0
            font.underline = reader.u8(p + 11) != 0
            font.strike = reader.u8(p + 12) != 0
            font.charset = reader.u8(p + 13)
            var nameBytes: [UInt8] = []
            for index in 0..<32 {
                let byte = reader.u8(p + 18 + index)
                if byte == 0 { break }
                nameBytes.append(byte)
            }
            let face = String(bytes: nameBytes, encoding: .windowsCP1252) ?? ""
            if !face.isEmpty { font.face = face }
            add(.font(font))
        case 0x00F7, 0x06FF, 0x01F9:
            add(.other)
        case 0x0142:
            var brush = GDIBrush()
            brush.color = CGColor(srgbRed: 0.6, green: 0.6, blue: 0.6, alpha: 1)
            add(.brush(brush))
        case 0x012D:
            let index = Int(reader.u16(p))
            guard index < objects.count, let object = objects[index] else { return }
            switch object {
            case .pen(let pen): g.state.pen = pen
            case .brush(let brush): g.state.brush = brush
            case .font(let font): g.state.font = font
            case .other: break
            }
        case 0x01F0:
            let index = Int(reader.u16(p))
            if index < objects.count { objects[index] = nil }
        case 0x0416:
            g.intersectClip(rectReversed(p))
        case 0x012C:
            g.resetClip()
        case 0x0F43:
            let rop = reader.u32(p)
            let srcHeight = CGFloat(reader.i16(p + 6)), srcWidth = CGFloat(reader.i16(p + 8))
            let ySrc = CGFloat(reader.i16(p + 10)), xSrc = CGFloat(reader.i16(p + 12))
            let destHeight = CGFloat(reader.i16(p + 14)), destWidth = CGFloat(reader.i16(p + 16))
            let yDst = CGFloat(reader.i16(p + 18)), xDst = CGFloat(reader.i16(p + 20))
            let image = dib(at: p + 22, end: p + size)
            let source = image.map { sourceRect(xSrc, ySrc, srcWidth, srcHeight, image: $0, header: p + 22) }
            g.bitmap(image, destination: CGRect(x: xDst, y: yDst, width: destWidth, height: destHeight), source: source, rop: rop)
        case 0x0B41, 0x0940:
            let rop = reader.u32(p)
            let stretch = function == 0x0B41
            let fieldCount = stretch ? 8 : 6
            let withBitmap = size > (fieldCount + 2) * 2 + 2
            var cursor = p + 4
            var srcHeight: CGFloat = 0, srcWidth: CGFloat = 0
            if stretch {
                srcHeight = CGFloat(reader.i16(cursor)); srcWidth = CGFloat(reader.i16(cursor + 2)); cursor += 4
            }
            let ySrc = CGFloat(reader.i16(cursor)), xSrc = CGFloat(reader.i16(cursor + 2))
            cursor += 4
            if !withBitmap { cursor += 2 }
            let destHeight = CGFloat(reader.i16(cursor)), destWidth = CGFloat(reader.i16(cursor + 2))
            let yDst = CGFloat(reader.i16(cursor + 4)), xDst = CGFloat(reader.i16(cursor + 6))
            cursor += 8
            if !stretch { srcHeight = destHeight; srcWidth = destWidth }
            let image = withBitmap ? dib(at: cursor, end: p + size) : nil
            let source = image.map { sourceRect(xSrc, ySrc, srcWidth, srcHeight, image: $0, header: cursor) }
            g.bitmap(image, destination: CGRect(x: xDst, y: yDst, width: destWidth, height: destHeight), source: source, rop: rop)
        default:
            break
        }
    }

    func dib(at offset: Int, end: Int) -> CGImage? {
        let headerSize = Int(reader.u32(offset))
        guard headerSize >= 12, headerSize <= 256, offset + headerSize <= end else { return nil }
        var colors = 0
        if headerSize >= 40 {
            let bitCount = Int(reader.u16(offset + 14))
            let used = Int(reader.u32(offset + 32))
            let compression = reader.u32(offset + 16)
            colors = used > 0 ? used : bitCount <= 8 ? 1 << bitCount : 0
            if compression == 3, headerSize == 40 { colors = 3 }
            let info = reader.slice(offset, headerSize + colors * 4)
            return GDIPainter.dib(info: info, pixels: reader.slice(offset + headerSize + colors * 4, end - offset - headerSize - colors * 4))
        }
        let bitCount = Int(reader.u16(offset + 10))
        colors = bitCount <= 8 ? 1 << bitCount : 0
        let info = reader.slice(offset, headerSize + colors * 3)
        return GDIPainter.dib(info: info, pixels: reader.slice(offset + headerSize + colors * 3, end - offset - headerSize - colors * 3))
    }

    func sourceRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, image: CGImage, header: Int) -> CGRect {
        let headerSize = Int(reader.u32(header))
        let height = headerSize >= 40 ? Int(reader.i32(header + 8)) : Int(reader.i16(header + 6))
        let top = height > 0 ? CGFloat(image.height) - y - h : y
        return CGRect(x: x, y: top, width: w, height: h)
    }
}
