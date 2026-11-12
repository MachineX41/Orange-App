import AppKit
import CoreText
import Foundation
import ImageIO

/// Renders PowerPoint decks on this Mac: masters and layouts, theme colors and fonts, text,
/// shapes, pictures (including WMF/EMF), tables, charts and SmartArt drawings.
public enum PresentationConverter {
    public static func convert(_ url: URL, into directory: URL? = nil) throws -> URL {
        try withDeck(url) { deck in
            let destination = UniqueDestination.url(
                in: directory ?? OutputLocation.directory(beside: url),
                baseName: OutputLocation.baseName(url),
                extension: "pdf"
            )
            try deck.renderPDF(to: destination, title: OutputLocation.baseName(url))
            return destination
        }
    }

    /// Slide text as a plain outline, one block per slide.
    public static func outline(_ url: URL) throws -> String {
        try withDeck(url) { $0.outline() }
    }

    static func withDeck<T>(_ url: URL, _ body: (Deck) throws -> T) throws -> T {
        guard Catalog.isPresentation(url) else { throw OrangeError.unsupported(url.pathExtension.uppercased()) }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("orange-pptx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let zip = scratch.appendingPathComponent("source.zip")
        try FileManager.default.copyItem(at: url, to: zip)
        let unpacked = try ArchiveToolkit.extract(archive: zip, into: scratch)
        guard let deck = Deck(root: unpacked) else { throw OrangeError.unreadable(url.lastPathComponent) }
        return try body(deck)
    }
}

let emuPerPoint: CGFloat = 12_700

enum PictureSource {
    case bitmap(CGImage)
    case vector(Metafile)
}

final class Deck {
    let package: OOXMLPackage
    let presentation: URL
    let size: CGSize
    let slides: [URL]
    let defaultTextStyle: XMLElement?
    let tableStyles: XMLElement?
    let firstNumber: Int
    private var themes: [URL: DrawingTheme] = [:]
    private var pictures: [URL: PictureSource?] = [:]

    init?(root: URL) {
        guard let presentation = Deck.findPresentation(in: root) else { return nil }
        let package = OOXMLPackage(root: presentation.deletingLastPathComponent().deletingLastPathComponent())
        guard let document = package.xml(presentation) else { return nil }
        self.package = package
        self.presentation = presentation
        let width = (document.kid("sldSz")?.optionalNumber("cx") ?? 12_192_000) / emuPerPoint
        let height = (document.kid("sldSz")?.optionalNumber("cy") ?? 6_858_000) / emuPerPoint
        guard width > 10, height > 10, width < 20_000, height < 20_000 else { return nil }
        size = CGSize(width: width, height: height)
        slides = (document.kid("sldIdLst")?.kids("sldId") ?? []).compactMap { package.target($0.relAttr("id"), from: presentation) }
        defaultTextStyle = document.kid("defaultTextStyle")
        tableStyles = package.related(presentation, type: "tableStyles").flatMap { package.xml($0) }
        firstNumber = Int(document.attr("firstSlideNum") ?? "") ?? 1
        guard !slides.isEmpty else { return nil }
    }

    static func findPresentation(in root: URL) -> URL? {
        let direct = root.appendingPathComponent("ppt/presentation.xml")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let file as URL in enumerator where file.lastPathComponent == "presentation.xml"
            && file.deletingLastPathComponent().lastPathComponent == "ppt" {
            return file
        }
        return nil
    }

    func theme(_ url: URL?) -> DrawingTheme {
        guard let url else { return DrawingTheme() }
        if let cached = themes[url] { return cached }
        let theme = DrawingTheme.load(package.xml(url))
        themes[url] = theme
        return theme
    }

    func picture(_ url: URL) -> PictureSource? {
        if let cached = pictures[url] { return cached }
        var loaded: PictureSource?
        if Metafile.isMetafile(url), let metafile = Metafile(url: url) {
            loaded = .vector(metafile)
        } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) {
            loaded = .bitmap(image)
        } else if let metafile = Metafile(url: url) {
            loaded = .vector(metafile)
        }
        pictures[url] = loaded
        return loaded
    }

    func parts(for slide: URL, number: Int) -> SlideParts? {
        guard let xml = package.xml(slide) else { return nil }
        let layout = package.related(slide, type: "slideLayout")
        let master = layout.flatMap { package.related($0, type: "slideMaster") }
        let masterXML = master.flatMap { package.xml($0) }
        let layoutXML = layout.flatMap { package.xml($0) }
        var palette = DrawingPalette(theme: theme(master.flatMap { package.related($0, type: "theme") }))
        if let map = masterXML?.kid("clrMap") { apply(map, to: &palette) }
        if let map = layoutXML?.kid("clrMapOvr")?.kid("overrideClrMapping") { apply(map, to: &palette) }
        if let map = xml.kid("clrMapOvr")?.kid("overrideClrMapping") { apply(map, to: &palette) }
        return SlideParts(
            slide: slide, slideXML: xml, layout: layout, layoutXML: layoutXML,
            master: master, masterXML: masterXML, palette: palette, number: number
        )
    }

    private func apply(_ map: XMLElement, to palette: inout DrawingPalette) {
        for attribute in map.attributes ?? [] {
            guard let name = attribute.localName, let value = attribute.stringValue else { continue }
            palette.map[name] = value
        }
    }

    func renderPDF(to destination: URL, title: String) throws {
        var page = CGRect(origin: .zero, size: size)
        let info: [String: Any] = [kCGPDFContextCreator as String: "Orange", kCGPDFContextTitle as String: title]
        guard let consumer = CGDataConsumer(url: destination as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &page, info as CFDictionary) else {
            throw OrangeError.writeFailed(destination.lastPathComponent)
        }
        var rendered = 0
        for (index, slide) in slides.enumerated() {
            guard let parts = parts(for: slide, number: firstNumber + index), parts.slideXML.flag("show") != false else { continue }
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .high
            let renderer = SlideRenderer(deck: self, parts: parts, context: context)
            renderer.draw()
            context.restoreGState()
            for link in renderer.links {
                context.setURL(link.url as CFURL, for: link.rect)
            }
            context.endPDFPage()
            rendered += 1
        }
        context.closePDF()
        guard rendered > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw OrangeError.empty
        }
    }

    func outline() -> String {
        var blocks: [String] = []
        for (index, slide) in slides.enumerated() {
            guard let parts = parts(for: slide, number: firstNumber + index), parts.slideXML.flag("show") != false,
                  let tree = parts.slideXML.path("cSld", "spTree") else { continue }
            var lines: [String] = []
            for body in tree.deepAll("txBody") {
                let paragraphs = TextContent.paragraphs(body, chain: TextStyleChain(), palette: parts.palette, slideNumber: parts.number) { _ in nil }
                for paragraph in paragraphs {
                    let text = paragraph.runs.map(\.text).joined().replacingOccurrences(of: "\u{2028}", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { continue }
                    lines.append(String(repeating: "  ", count: paragraph.level) + text)
                }
            }
            for cell in tree.deepAll("tc") {
                let text = cell.deepAll("t").compactMap(\.stringValue).joined().trimmingCharacters(in: .whitespaces)
                if !text.isEmpty, !lines.contains(text) { lines.append(text) }
            }
            if let notes = package.related(slide, type: "notesSlide").flatMap({ package.xml($0) }) {
                let text = notes.deepAll("sp").filter { $0.deep("ph")?.attr("type") == "body" }
                    .flatMap { $0.deepAll("p") }
                    .map { $0.deepAll("t").compactMap(\.stringValue).joined() }
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if !text.isEmpty {
                    lines.append("")
                    lines.append(Lang.t("Notes:", "Notlar:"))
                    lines += text
                }
            }
            blocks.append("— \(parts.number) —\n" + lines.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }
}

struct SlideParts {
    let slide: URL
    let slideXML: XMLElement
    let layout: URL?
    let layoutXML: XMLElement?
    let master: URL?
    let masterXML: XMLElement?
    let palette: DrawingPalette
    let number: Int
}

// MARK: Coordinate space

struct DrawingSpace {
    var sx: CGFloat = 1 / emuPerPoint
    var sy: CGFloat = 1 / emuPerPoint
    var tx: CGFloat = 0
    var ty: CGFloat = 0

    func rect(_ xfrm: XMLElement) -> CGRect {
        let off = xfrm.kid("off"), ext = xfrm.kid("ext")
        return CGRect(
            x: tx + (off?.number("x") ?? 0) * sx,
            y: ty + (off?.number("y") ?? 0) * sy,
            width: max((ext?.number("cx") ?? 0) * sx, 0),
            height: max((ext?.number("cy") ?? 0) * sy, 0)
        )
    }

    func child(_ xfrm: XMLElement) -> DrawingSpace {
        let off = xfrm.kid("off"), ext = xfrm.kid("ext")
        let chOff = xfrm.kid("chOff"), chExt = xfrm.kid("chExt")
        let cx = chExt?.number("cx") ?? 0, cy = chExt?.number("cy") ?? 0
        let kx = cx == 0 ? 1 : (ext?.number("cx") ?? 0) / cx
        let ky = cy == 0 ? 1 : (ext?.number("cy") ?? 0) / cy
        return DrawingSpace(
            sx: sx * kx,
            sy: sy * ky,
            tx: tx + ((off?.number("x") ?? 0) - (chOff?.number("x") ?? 0) * kx) * sx,
            ty: ty + ((off?.number("y") ?? 0) - (chOff?.number("y") ?? 0) * ky) * sy
        )
    }

    func offset(by point: CGPoint) -> DrawingSpace {
        DrawingSpace(sx: sx, sy: sy, tx: tx + point.x, ty: ty + point.y)
    }
}

// MARK: Paint

enum FillSpec {
    case none
    case solid(NSColor)
    case gradient(stops: [(CGFloat, NSColor)], angle: CGFloat, radial: Bool, focus: CGRect?)
    case picture(XMLElement, URL)
    case group
}

struct LineSpec {
    var color: NSColor?
    var width: CGFloat = 0.75
    var dash: String?
    var cap: CGLineCap = .butt
    var join: CGLineJoin = .round
    var head: XMLElement?
    var tail: XMLElement?
    var compound: String?
}

struct ShadowSpec {
    var offset: CGSize
    var blur: CGFloat
    var color: NSColor
}

// MARK: Slide renderer

final class SlideRenderer {
    let deck: Deck
    let parts: SlideParts
    let context: CGContext
    var palette: DrawingPalette
    var links: [TextLinkArea] = []

    init(deck: Deck, parts: SlideParts, context: CGContext) {
        self.deck = deck
        self.parts = parts
        self.context = context
        self.palette = parts.palette
    }

    var package: OOXMLPackage { deck.package }

    func draw() {
        drawBackground()
        let slideShowsMaster = parts.slideXML.flag("showMasterSp") != false
        let layoutShowsMaster = parts.layoutXML?.flag("showMasterSp") != false
        if slideShowsMaster, layoutShowsMaster, let master = parts.master, let tree = parts.masterXML?.path("cSld", "spTree") {
            drawTree(tree, part: master, space: DrawingSpace(), template: true, groupFill: nil, depth: 0)
        }
        if slideShowsMaster, let layout = parts.layout, let tree = parts.layoutXML?.path("cSld", "spTree") {
            drawTree(tree, part: layout, space: DrawingSpace(), template: true, groupFill: nil, depth: 0)
        }
        if let tree = parts.slideXML.path("cSld", "spTree") {
            drawTree(tree, part: parts.slide, space: DrawingSpace(), template: false, groupFill: nil, depth: 0)
        }
    }

    // MARK: Background

    func drawBackground() {
        let page = CGRect(origin: .zero, size: deck.size)
        context.setFillColor((palette.scheme("bg1") ?? .white).srgbCG)
        context.fill(page)
        let sources: [(XMLElement?, URL?)] = [(parts.slideXML, parts.slide), (parts.layoutXML, parts.layout), (parts.masterXML, parts.master)]
        for (xml, part) in sources {
            guard let background = xml?.path("cSld", "bg"), let part else { continue }
            var fill: FillSpec?
            if let properties = background.kid("bgPr") {
                fill = fillSpec(in: properties, part: part, palette: palette)
            } else if let reference = background.kid("bgRef") {
                fill = themeFill(reference, part: part)
            }
            if let fill {
                paint(fill, path: CGPath(rect: page, transform: nil), rect: page, evenOdd: false)
            }
            return
        }
    }

    // MARK: Tree

    func drawTree(_ tree: XMLElement, part: URL, space: DrawingSpace, template: Bool, groupFill: FillSpec?, depth: Int) {
        guard depth < 32 else { return }
        for node in tree.drawableChildren {
            if template, placeholder(of: node) != nil { continue }
            switch node.localName {
            case "sp", "cxnSp":
                drawShape(node, part: part, space: space, groupFill: groupFill, template: template)
            case "pic":
                drawPicture(node, part: part, space: space)
            case "grpSp":
                drawGroup(node, part: part, space: space, template: template, groupFill: groupFill, depth: depth)
            case "graphicFrame":
                drawFrame(node, part: part, space: space)
            default:
                break
            }
        }
    }

    func drawGroup(_ group: XMLElement, part: URL, space: DrawingSpace, template: Bool, groupFill: FillSpec?, depth: Int) {
        let properties = group.kid("grpSpPr")
        guard let xfrm = properties?.kid("xfrm") else {
            drawTree(group, part: part, space: space, template: template, groupFill: groupFill, depth: depth + 1)
            return
        }
        let rect = space.rect(xfrm)
        let fill = properties.flatMap { fillSpec(in: $0, part: part, palette: palette) } ?? groupFill
        context.saveGState()
        applyTransform(xfrm, rect: rect, mirrorText: true)
        drawTree(group, part: part, space: space.child(xfrm), template: template, groupFill: fill, depth: depth + 1)
        context.restoreGState()
    }

    func applyTransform(_ xfrm: XMLElement?, rect: CGRect, mirrorText: Bool, extraRotation: CGFloat = 0) {
        let rotation = (xfrm?.number("rot") ?? 0) / 60_000 + extraRotation
        let flipH = mirrorText && xfrm?.flag("flipH") == true
        var flipV = xfrm?.flag("flipV") == true
        var turn = rotation
        if !mirrorText, flipV { turn += 180; flipV = false }
        guard turn != 0 || flipH || flipV else { return }
        context.translateBy(x: rect.midX, y: rect.midY)
        if turn != 0 { context.rotate(by: turn * .pi / 180) }
        if flipH || flipV { context.scaleBy(x: flipH ? -1 : 1, y: flipV ? -1 : 1) }
        context.translateBy(x: -rect.midX, y: -rect.midY)
    }

    // MARK: Placeholders

    struct Placeholder {
        var type: String
        var index: String?
    }

    func placeholder(of node: XMLElement) -> Placeholder? {
        for container in ["nvSpPr", "nvPicPr", "nvGraphicFramePr", "nvCxnSpPr", "nvGrpSpPr"] {
            if let ph = node.kid(container)?.kid("nvPr")?.kid("ph") {
                return Placeholder(type: ph.attr("type") ?? "obj", index: ph.attr("idx"))
            }
        }
        return nil
    }

    static func family(_ type: String) -> String {
        switch type {
        case "title", "ctrTitle": return "title"
        case "body", "subTitle", "obj", "pic", "chart", "tbl", "clipArt", "dgm", "media": return "body"
        default: return type
        }
    }

    func match(_ holder: Placeholder, in tree: XMLElement?, byIndex: Bool) -> XMLElement? {
        guard let tree else { return nil }
        let candidates = tree.deepAll("sp") + tree.deepAll("pic") + tree.deepAll("graphicFrame")
        let holders = candidates.compactMap { node in placeholder(of: node).map { (node, $0) } }
        if byIndex, let index = holder.index {
            if let found = holders.first(where: { $0.1.index == index && $0.1.type == holder.type }) { return found.0 }
            if let found = holders.first(where: { $0.1.index == index && SlideRenderer.family($0.1.type) == SlideRenderer.family(holder.type) }) {
                return found.0
            }
            if let found = holders.first(where: { $0.1.index == index }) { return found.0 }
        }
        if let found = holders.first(where: { $0.1.type == holder.type }) { return found.0 }
        let family = SlideRenderer.family(holder.type)
        if family == "title" || family == "body" || !byIndex {
            if let found = holders.first(where: { SlideRenderer.family($0.1.type) == family }) { return found.0 }
        }
        return nil
    }

    /// The layout and master shapes a placeholder inherits from, oldest first.
    func ancestors(of node: XMLElement, template: Bool, part: URL) -> [XMLElement] {
        guard let holder = placeholder(of: node) else { return [] }
        if part == parts.slide {
            let layoutShape = match(holder, in: parts.layoutXML?.path("cSld", "spTree"), byIndex: true)
            let masterHolder = layoutShape.flatMap(placeholder(of:)) ?? holder
            let masterShape = match(masterHolder, in: parts.masterXML?.path("cSld", "spTree"), byIndex: false)
            return [masterShape, layoutShape].compactMap { $0 }
        }
        if part == parts.layout {
            return [match(holder, in: parts.masterXML?.path("cSld", "spTree"), byIndex: false)].compactMap { $0 }
        }
        return []
    }

    func properties(_ node: XMLElement) -> XMLElement? {
        node.kid("spPr") ?? node.kid("grpSpPr")
    }

    // MARK: Shapes

    func drawShape(_ shape: XMLElement, part: URL, space: DrawingSpace, groupFill: FillSpec?, template: Bool) {
        let chain = ancestors(of: shape, template: template, part: part) + [shape]
        let spPrs = chain.reversed().compactMap(properties)
        guard let xfrm = spPrs.lazy.compactMap({ $0.kid("xfrm") }).first else { return }
        let rect = space.rect(xfrm)
        let style = chain.reversed().lazy.compactMap { $0.kid("style") }.first
        let geometrySource = spPrs.first { $0.kid("prstGeom") != nil || $0.kid("custGeom") != nil }
        let emu = CGSize(width: xfrm.kid("ext")?.number("cx") ?? 0, height: xfrm.kid("ext")?.number("cy") ?? 0)
        let pieces = ShapeGeometry.parts(geometrySource, rect: rect, emuSize: emu, isConnector: shape.localName == "cxnSp")

        let fill = resolveFill(spPrs, style: style, part: part, groupFill: groupFill)
        let line = resolveLine(spPrs.reversed().compactMap { $0.kid("ln") }, style: style)
        let shadow = resolveShadow(spPrs, style: style)

        context.saveGState()
        applyTransform(xfrm, rect: rect, mirrorText: true)
        let hasFill: Bool = { if case .none = fill { return false }; return true }()
        if let shadow, hasFill || line?.color != nil {
            context.setShadow(offset: shadow.offset, blur: shadow.blur, color: shadow.color.srgbCG)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        for piece in pieces where piece.fill && !piece.open {
            paint(fill, path: piece.path, rect: rect, evenOdd: piece.evenOdd)
        }
        if let line, line.color != nil {
            for piece in pieces where piece.stroke {
                stroke(piece, line: line)
            }
        }
        if shadow != nil, hasFill || line?.color != nil {
            context.endTransparencyLayer()
        }
        context.restoreGState()

        guard let body = shape.kid("txBody") else { return }
        var textRect = rect
        var textXfrm = xfrm
        if let custom = shape.kid("txXfrm") {
            textRect = space.rect(custom)
            textXfrm = custom
        }
        if let inset = pieces.first?.textInset, inset > 0 {
            textRect = textRect.insetBy(dx: textRect.width * inset, dy: textRect.height * inset)
        }
        context.saveGState()
        applyTransform(textXfrm, rect: textRect, mirrorText: false)
        drawText(body, in: textRect, chain: chain, style: style, part: part)
        context.restoreGState()
    }

    func stroke(_ piece: GeometryPart, line: LineSpec) {
        guard let color = line.color else { return }
        context.saveGState()
        context.setStrokeColor(color.srgbCG)
        context.setLineWidth(line.width)
        context.setLineCap(line.cap)
        context.setLineJoin(line.join)
        if let pattern = dashPattern(line.dash, width: line.width) {
            context.setLineDash(phase: 0, lengths: pattern)
        }
        context.addPath(piece.path)
        context.strokePath()
        context.restoreGState()
        if let start = piece.start, let head = line.head { arrow(head, tip: start.tip, from: start.from, line: line) }
        if let end = piece.end, let tail = line.tail { arrow(tail, tip: end.tip, from: end.from, line: line) }
    }

    func dashPattern(_ name: String?, width: CGFloat) -> [CGFloat]? {
        let unit = max(width, 0.5)
        let pattern: [CGFloat]
        switch name {
        case "dash": pattern = [4, 3]
        case "sysDash": pattern = [3, 1]
        case "dot": pattern = [1, 3]
        case "sysDot": pattern = [1, 1]
        case "dashDot": pattern = [4, 3, 1, 3]
        case "sysDashDot": pattern = [3, 1, 1, 1]
        case "lgDash": pattern = [8, 3]
        case "lgDashDot": pattern = [8, 3, 1, 3]
        case "lgDashDotDot": pattern = [8, 3, 1, 3, 1, 3]
        case "sysDashDotDot": pattern = [3, 1, 1, 1, 1, 1]
        default: return nil
        }
        return pattern.map { $0 * unit }
    }

    func arrow(_ end: XMLElement, tip: CGPoint, from: CGPoint, line: LineSpec) {
        let type = end.attr("type") ?? "none"
        guard type != "none", let color = line.color else { return }
        func factor(_ raw: String?) -> CGFloat { raw == "sm" ? 2 : raw == "lg" ? 5 : 3 }
        let width = max(line.width, 1) * factor(end.attr("w"))
        let length = max(line.width, 1) * factor(end.attr("len"))
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        guard tip != from else { return }
        context.saveGState()
        context.translateBy(x: tip.x, y: tip.y)
        context.rotate(by: angle)
        context.setFillColor(color.srgbCG)
        context.setStrokeColor(color.srgbCG)
        context.setLineWidth(line.width)
        let path = CGMutablePath()
        switch type {
        case "oval":
            path.addEllipse(in: CGRect(x: -length / 2, y: -width / 2, width: length, height: width))
            context.addPath(path); context.fillPath()
        case "diamond":
            path.addLines(between: [CGPoint(x: length / 2, y: 0), CGPoint(x: 0, y: -width / 2), CGPoint(x: -length / 2, y: 0), CGPoint(x: 0, y: width / 2)])
            path.closeSubpath()
            context.addPath(path); context.fillPath()
        case "arrow":
            path.move(to: CGPoint(x: -length, y: -width / 2)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: -length, y: width / 2))
            context.addPath(path); context.strokePath()
        case "stealth":
            path.addLines(between: [.zero, CGPoint(x: -length, y: -width / 2), CGPoint(x: -length * 0.6, y: 0), CGPoint(x: -length, y: width / 2)])
            path.closeSubpath()
            context.addPath(path); context.fillPath()
        default:
            path.addLines(between: [.zero, CGPoint(x: -length, y: -width / 2), CGPoint(x: -length, y: width / 2)])
            path.closeSubpath()
            context.addPath(path); context.fillPath()
        }
        context.restoreGState()
    }

    // MARK: Fill resolution

    func fillSpec(in parent: XMLElement, part: URL, palette: DrawingPalette) -> FillSpec? {
        for child in parent.elements {
            if let spec = fillSpec(node: child, part: part, palette: palette) { return spec }
        }
        return nil
    }

    func fillSpec(node: XMLElement, part: URL, palette: DrawingPalette) -> FillSpec? {
        switch node.localName {
        case "noFill":
            return FillSpec.none
        case "solidFill":
            return palette.color(in: node).map(FillSpec.solid) ?? FillSpec.none
        case "grpFill":
            return .group
        case "gradFill":
            let stops = (node.kid("gsLst")?.kids("gs") ?? []).compactMap { stop -> (CGFloat, NSColor)? in
                guard let color = palette.color(in: stop) else { return nil }
                return (clamp01(stop.number("pos") / 100_000), color)
            }.sorted { $0.0 < $1.0 }
            guard !stops.isEmpty else { return FillSpec.none }
            if let path = node.kid("path") {
                let focus = path.kid("fillToRect").map {
                    CGRect(x: $0.number("l") / 100_000, y: $0.number("t") / 100_000,
                           width: 1 - $0.number("l") / 100_000 - $0.number("r") / 100_000,
                           height: 1 - $0.number("t") / 100_000 - $0.number("b") / 100_000)
                }
                return .gradient(stops: stops, angle: 0, radial: true, focus: focus)
            }
            return .gradient(stops: stops, angle: (node.kid("lin")?.number("ang") ?? 5_400_000) / 60_000, radial: false, focus: nil)
        case "blipFill":
            return .picture(node, part)
        case "pattFill":
            let fg = palette.color(in: node.kid("fgClr")) ?? .black
            let bg = palette.color(in: node.kid("bgClr")) ?? .white
            return .solid(bg.blended(with: fg, fraction: 0.35))
        default:
            return nil
        }
    }

    func themeFill(_ reference: XMLElement, part: URL) -> FillSpec? {
        let index = Int(reference.attr("idx") ?? "") ?? 0
        let tinted = palette.with(placeholder: palette.color(in: reference))
        let list: [XMLElement]
        let slot: Int
        if index >= 1001 {
            list = palette.theme.backgroundFills
            slot = index - 1001
        } else if index >= 1 {
            list = palette.theme.fillStyles
            slot = index - 1
        } else {
            return FillSpec.none
        }
        guard slot < list.count else { return palette.color(in: reference).map(FillSpec.solid) }
        return fillSpec(node: list[slot], part: part, palette: tinted)
    }

    func resolveFill(_ spPrs: [XMLElement], style: XMLElement?, part: URL, groupFill: FillSpec?) -> FillSpec {
        for properties in spPrs {
            if let spec = fillSpec(in: properties, part: part, palette: palette) {
                if case .group = spec { return groupFill ?? FillSpec.none }
                return spec
            }
        }
        if let reference = style?.kid("fillRef"), let spec = themeFill(reference, part: part) { return spec }
        return FillSpec.none
    }

    func resolveLine(_ lines: [XMLElement], style: XMLElement?, base: LineSpec? = nil) -> LineSpec? {
        var spec = base ?? LineSpec()
        var hasFill = base?.color != nil
        if base == nil, let reference = style?.kid("lnRef"), let index = Int(reference.attr("idx") ?? ""), index > 0 {
            let tinted = palette.with(placeholder: palette.color(in: reference))
            if index - 1 < palette.theme.lineStyles.count {
                apply(palette.theme.lineStyles[index - 1], to: &spec, hasFill: &hasFill, palette: tinted)
            } else if let color = tinted.color(in: reference) {
                spec.color = color
                hasFill = true
            }
        }
        for line in lines { apply(line, to: &spec, hasFill: &hasFill, palette: palette) }
        guard hasFill else { return nil }
        return spec
    }

    func apply(_ line: XMLElement, to spec: inout LineSpec, hasFill: inout Bool, palette: DrawingPalette) {
        if let width = line.optionalNumber("w") { spec.width = width / emuPerPoint }
        switch line.attr("cap") {
        case "rnd"?: spec.cap = .round
        case "sq"?: spec.cap = .square
        case "flat"?: spec.cap = .butt
        default: break
        }
        if line.kid("round") != nil { spec.join = .round }
        if line.kid("bevel") != nil { spec.join = .bevel }
        if line.kid("miter") != nil { spec.join = .miter }
        if let dash = line.kid("prstDash")?.attr("val") { spec.dash = dash == "solid" ? nil : dash }
        if let head = line.kid("headEnd") { spec.head = head }
        if let tail = line.kid("tailEnd") { spec.tail = tail }
        if line.kid("noFill") != nil { spec.color = nil; hasFill = true }
        if let solid = line.kid("solidFill") { spec.color = palette.color(in: solid); hasFill = true }
        if let stop = line.kid("gradFill")?.kid("gsLst")?.kids("gs").first { spec.color = palette.color(in: stop); hasFill = true }
        if line.kid("pattFill") != nil { spec.color = palette.color(in: line.kid("pattFill")?.kid("fgClr")); hasFill = true }
    }

    func resolveShadow(_ spPrs: [XMLElement], style: XMLElement?) -> ShadowSpec? {
        if let shadow = spPrs.lazy.compactMap({ $0.kid("effectLst")?.kid("outerShdw") ?? $0.kid("effectDag")?.deep("outerShdw") }).first {
            return shadowSpec(shadow, palette: palette)
        }
        if let reference = style?.kid("effectRef"), let index = Int(reference.attr("idx") ?? ""), index > 0,
           index - 1 < palette.theme.effectStyles.count {
            let container = palette.theme.effectStyles[index - 1]
            if let shadow = container.kid("effectLst")?.kid("outerShdw") ?? container.deep("outerShdw") {
                return shadowSpec(shadow, palette: palette.with(placeholder: palette.color(in: reference)))
            }
        }
        return nil
    }

    func shadowSpec(_ node: XMLElement, palette: DrawingPalette) -> ShadowSpec? {
        guard let color = palette.color(in: node) else { return nil }
        let distance = node.number("dist") / emuPerPoint
        let angle = node.number("dir") / 60_000 * .pi / 180
        let blur = node.number("blurRad") / emuPerPoint
        let ctm = context.ctm
        let dx = distance * cos(angle), dy = distance * sin(angle)
        let device = CGSize(width: dx * ctm.a + dy * ctm.c, height: dx * ctm.b + dy * ctm.d)
        return ShadowSpec(offset: device, blur: blur, color: color)
    }

    // MARK: Painting

    func paint(_ fill: FillSpec, path: CGPath, rect: CGRect, evenOdd: Bool) {
        switch fill {
        case .none, .group:
            return
        case .solid(let color):
            context.setFillColor(color.srgbCG)
            context.addPath(path)
            context.fillPath(using: evenOdd ? .evenOdd : .winding)
        case .gradient(let stops, let angle, let radial, let focus):
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: stops.map(\.1.srgbCG) as CFArray,
                locations: stops.map(\.0)
            ) else { return }
            context.saveGState()
            context.addPath(path)
            context.clip(using: evenOdd ? .evenOdd : .winding)
            if radial {
                let f = focus ?? CGRect(x: 0.5, y: 0.5, width: 0, height: 0)
                let center = CGPoint(x: rect.minX + (f.minX + f.width / 2) * rect.width, y: rect.minY + (f.minY + f.height / 2) * rect.height)
                let radius = hypot(max(center.x - rect.minX, rect.maxX - center.x), max(center.y - rect.minY, rect.maxY - center.y))
                context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                                           options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
            } else {
                let radians = angle * .pi / 180
                let direction = CGPoint(x: cos(radians), y: sin(radians))
                let half = (abs(rect.width * direction.x) + abs(rect.height * direction.y)) / 2
                let center = CGPoint(x: rect.midX, y: rect.midY)
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: center.x - direction.x * half, y: center.y - direction.y * half),
                    end: CGPoint(x: center.x + direction.x * half, y: center.y + direction.y * half),
                    options: [.drawsAfterEndLocation, .drawsBeforeStartLocation]
                )
            }
            context.restoreGState()
        case .picture(let blipFill, let part):
            guard let blip = blipFill.kid("blip"),
                  let url = package.target(blip.relAttr("embed"), from: part) ?? package.target(blip.relAttr("link"), from: part),
                  let source = deck.picture(url) else { return }
            context.saveGState()
            context.addPath(path)
            context.clip(using: evenOdd ? .evenOdd : .winding)
            if let alpha = blip.kid("alphaModFix")?.optionalNumber("amt") { context.setAlpha(clamp01(alpha / 100_000)) }
            var target = rect
            if let fillRect = blipFill.kid("stretch")?.kid("fillRect") {
                target = CGRect(
                    x: rect.minX + rect.width * fillRect.number("l") / 100_000,
                    y: rect.minY + rect.height * fillRect.number("t") / 100_000,
                    width: rect.width * (1 - (fillRect.number("l") + fillRect.number("r")) / 100_000),
                    height: rect.height * (1 - (fillRect.number("t") + fillRect.number("b")) / 100_000)
                )
            }
            if let crop = blipFill.kid("srcRect") { target = uncropped(target, crop: crop) }
            if blipFill.kid("tile") != nil, case .bitmap(let image) = source {
                tile(image, in: rect, tile: blipFill.kid("tile")!)
            } else {
                draw(source, in: target)
            }
            context.restoreGState()
        }
    }

    func uncropped(_ rect: CGRect, crop: XMLElement) -> CGRect {
        let l = crop.number("l") / 100_000, t = crop.number("t") / 100_000
        let r = crop.number("r") / 100_000, b = crop.number("b") / 100_000
        let visibleW = 1 - l - r, visibleH = 1 - t - b
        guard visibleW > 0.001, visibleH > 0.001 else { return rect }
        let width = rect.width / visibleW, height = rect.height / visibleH
        return CGRect(x: rect.minX - l * width, y: rect.minY - t * height, width: width, height: height)
    }

    func tile(_ image: CGImage, in rect: CGRect, tile: XMLElement) {
        let sx = (tile.optionalNumber("sx") ?? 100_000) / 100_000
        let sy = (tile.optionalNumber("sy") ?? 100_000) / 100_000
        // Office stores picture tiles at 96 dpi; convert pixels to PDF points.
        let width = max(CGFloat(image.width) * 72 / 96 * sx, 2)
        let height = max(CGFloat(image.height) * 72 / 96 * sy, 2)
        var y = rect.minY
        var count = 0
        while y < rect.maxY, count < 4_000 {
            var x = rect.minX
            while x < rect.maxX, count < 4_000 {
                draw(.bitmap(image), in: CGRect(x: x, y: y, width: width, height: height))
                x += width
                count += 1
            }
            y += height
        }
    }

    func draw(_ source: PictureSource, in rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        switch source {
        case .bitmap(let image):
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: rect.size))
            context.restoreGState()
        case .vector(let metafile):
            context.saveGState()
            context.clip(to: rect.insetBy(dx: -1, dy: -1))
            metafile.draw(in: context, rect: rect)
            context.restoreGState()
        }
    }

    // MARK: Pictures

    func drawPicture(_ picture: XMLElement, part: URL, space: DrawingSpace, fallback: CGRect? = nil) {
        let chain = ancestors(of: picture, template: false, part: part) + [picture]
        let spPrs = chain.reversed().compactMap(properties)
        let xfrm = spPrs.lazy.compactMap { $0.kid("xfrm") }.first
        guard let rect = xfrm.map(space.rect) ?? fallback, rect.width > 0, rect.height > 0 else { return }
        let style = picture.kid("style")
        let geometrySource = spPrs.first { $0.kid("prstGeom") != nil || $0.kid("custGeom") != nil }
        let emu = CGSize(width: rect.width * emuPerPoint, height: rect.height * emuPerPoint)
        let pieces = ShapeGeometry.parts(geometrySource, rect: rect, emuSize: emu)
        let shadow = resolveShadow(spPrs, style: style)

        context.saveGState()
        applyTransform(xfrm, rect: rect, mirrorText: true)
        if let shadow {
            context.setShadow(offset: shadow.offset, blur: shadow.blur, color: shadow.color.srgbCG)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        if let background = spPrs.lazy.compactMap({ self.fillSpec(in: $0, part: part, palette: self.palette) }).first {
            for piece in pieces where piece.fill { paint(background, path: piece.path, rect: rect, evenOdd: piece.evenOdd) }
        }
        if let blipFill = picture.kid("blipFill") {
            let path = CGMutablePath()
            for piece in pieces where !piece.open { path.addPath(piece.path) }
            paint(.picture(blipFill, part), path: path.isEmpty ? CGPath(rect: rect, transform: nil) : path, rect: rect, evenOdd: false)
        }
        if let line = resolveLine(spPrs.reversed().compactMap { $0.kid("ln") }, style: style) {
            for piece in pieces where piece.stroke { stroke(piece, line: line) }
        }
        if shadow != nil { context.endTransparencyLayer() }
        context.restoreGState()
    }

    // MARK: Graphic frames

    func drawFrame(_ frame: XMLElement, part: URL, space: DrawingSpace) {
        let chain = ancestors(of: frame, template: false, part: part) + [frame]
        guard let xfrm = chain.reversed().lazy.compactMap({ $0.kid("xfrm") }).first else { return }
        let rect = space.rect(xfrm)
        guard let data = frame.kid("graphic")?.kid("graphicData") else { return }
        let uri = data.attr("uri") ?? ""
        context.saveGState()
        applyTransform(xfrm, rect: rect, mirrorText: true)
        defer { context.restoreGState() }
        if let table = data.kid("tbl") {
            TableRenderer(renderer: self, table: table, part: part).draw(in: rect)
        } else if uri.hasSuffix("/chart"), let chartURL = package.target(data.deep("chart")?.relAttr("id"), from: part),
                  let chart = package.xml(chartURL) {
            ChartRenderer(space: chart, palette: palette, context: context).draw(in: rect)
        } else if uri.hasSuffix("/diagram") {
            drawDiagram(data, part: part, rect: rect)
        } else if let picture = data.deepAll("pic").last {
            let saved = palette
            drawPicture(picture, part: part, space: space, fallback: rect)
            palette = saved
        }
    }

    func drawDiagram(_ data: XMLElement, part: URL, rect: CGRect) {
        var drawingURL: URL?
        if let ids = data.deep("relIds"), let model = package.target(ids.relAttr("dm"), from: part),
           let relation = package.xml(model)?.deep("dataModelExt")?.attr("relId") {
            drawingURL = package.target(relation, from: part)
        }
        if drawingURL == nil {
            let drawings = package.relationships(for: part).filter { $0.value.type.hasSuffix("/diagramDrawing") }
            if drawings.count == 1 { drawingURL = package.resolve(drawings.first!.value.target, from: part) }
        }
        guard let drawingURL, let tree = package.xml(drawingURL)?.deep("spTree") else { return }
        drawTree(tree, part: drawingURL, space: DrawingSpace().offset(by: rect.origin), template: false, groupFill: nil, depth: 0)
    }

    // MARK: Text

    func textChain(for chain: [XMLElement], style: XMLElement?) -> TextStyleChain {
        var text = TextStyleChain()
        text.apply(deck.defaultTextStyle, palette: palette)
        if let holder = chain.last.flatMap(placeholder(of:)) {
            let styles = parts.masterXML?.kid("txStyles")
            switch SlideRenderer.family(holder.type) {
            case "title": text.apply(styles?.kid("titleStyle"), palette: palette)
            case "body": text.apply(styles?.kid("bodyStyle"), palette: palette)
            default: text.apply(styles?.kid("otherStyle"), palette: palette)
            }
        }
        if let reference = style?.kid("fontRef") {
            text.setColor(palette.color(in: reference))
            switch reference.attr("idx") {
            case "major"?: text.setFont(palette.theme.majorFont.isEmpty ? nil : palette.theme.majorFont)
            case "minor"?: text.setFont(palette.theme.minorFont.isEmpty ? nil : palette.theme.minorFont)
            default: break
            }
        }
        for node in chain { text.apply(node.kid("txBody")?.kid("lstStyle"), palette: palette) }
        return text
    }

    func drawText(_ body: XMLElement, in rect: CGRect, chain: [XMLElement], style: XMLElement?, part: URL) {
        var props = TextBody()
        for node in chain { props.apply(node.kid("txBody")?.kid("bodyPr")) }
        let styles = textChain(for: chain, style: style)
        drawText(body, in: rect, props: props, styles: styles, part: part)
    }

    func paragraphs(_ body: XMLElement, styles: TextStyleChain, part: URL) -> [TextParagraph] {
        TextContent.paragraphs(body, chain: styles, palette: palette, slideNumber: parts.number) { [package] id in
            package.externalLink(id, from: part)
        }
    }

    /// Lays text out inside the shape. Overflow shrinks a little, then clips so neighbouring shapes stay clean.
    func drawText(_ body: XMLElement, in rect: CGRect, props: TextBody, styles: TextStyleChain, part: URL) {
        let paragraphs = paragraphs(body, styles: styles, part: part)
        guard paragraphs.contains(where: { !$0.runs.isEmpty }) else { return }

        var frame = rect
        let vertical = ["vert", "eaVert", "wordArtVert", "mongolianVert", "vert270", "wordArtVertRtl"].contains(props.vertical)
        context.saveGState()
        defer { context.restoreGState() }
        if vertical {
            let turn: CGFloat = props.vertical == "vert270" ? -.pi / 2 : .pi / 2
            context.translateBy(x: rect.midX, y: rect.midY)
            context.rotate(by: turn)
            context.translateBy(x: -rect.midX, y: -rect.midY)
            frame = CGRect(x: rect.midX - rect.height / 2, y: rect.midY - rect.width / 2, width: rect.height, height: rect.width)
        }
        context.clip(to: frame.insetBy(dx: -0.5, dy: -0.5))
        let box = CGRect(
            x: frame.minX + props.insets.left,
            y: frame.minY + props.insets.top,
            width: max(frame.width - props.insets.left - props.insets.right, 1),
            height: max(frame.height - props.insets.top - props.insets.bottom, 1)
        )

        var scale: CGFloat = 1, reduction: CGFloat = 0
        if case .shrink(let fontScale, let lineReduction) = props.autofit {
            scale = fontScale ?? 1
            reduction = lineReduction
        }
        let columns = max(props.columns, 1)
        let gap: CGFloat = 12
        let columnWidth = columns == 1 ? box.width : max((box.width - gap * CGFloat(columns - 1)) / CGFloat(columns), 1)
        let defaultColor = palette.text

        func layouts(scale fontScale: CGFloat, reduction spacingReduction: CGFloat) -> [TextLayout] {
            if columns == 1 {
                return [TextLayoutEngine.layout(paragraphs, width: columnWidth, wrap: props.wrap, fontScale: fontScale, spacingReduction: spacingReduction, defaultColor: defaultColor)]
            }
            let heights = paragraphs.map {
                TextLayoutEngine.layout([$0], width: columnWidth, wrap: props.wrap, fontScale: fontScale, spacingReduction: spacingReduction, defaultColor: defaultColor).height
            }
            var buckets = Array(repeating: [TextParagraph](), count: columns)
            var used = Array(repeating: CGFloat(0), count: columns)
            for (index, paragraph) in paragraphs.enumerated() {
                let target = used.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
                buckets[target].append(paragraph)
                used[target] += heights[index]
            }
            return buckets.map {
                TextLayoutEngine.layout($0, width: columnWidth, wrap: props.wrap, fontScale: fontScale, spacingReduction: spacingReduction, defaultColor: defaultColor)
            }
        }

        var columnLayouts = layouts(scale: scale, reduction: reduction)
        let shouldShrink: Bool = {
            if case .shrink = props.autofit { return true }
            if case .grow = props.autofit { return false }
            return props.wrap
        }()
        if shouldShrink {
            var attempts = 0
            let floor = max(scale * 0.5, 0.35)
            while columnLayouts.map(\.height).max() ?? 0 > box.height * 1.01, scale > floor, attempts < 14 {
                scale *= 0.92
                reduction = min(reduction + 0.015, 0.25)
                columnLayouts = layouts(scale: scale, reduction: reduction)
                attempts += 1
            }
        }

        var found: [TextLinkArea] = []
        for (index, layout) in columnLayouts.enumerated() {
            let leftEdge = box.minX + CGFloat(index) * (columnWidth + gap)
            var top: CGFloat
            switch props.anchor {
            case "ctr": top = box.midY - layout.height / 2
            case "b": top = box.maxY - layout.height
            default: top = box.minY
            }
            var left = leftEdge
            if !props.wrap {
                let spill = layout.width - columnWidth
                if spill > 0 {
                    let align = paragraphs.first?.style.align
                    if align == "ctr" { left -= spill / 2 } else if align == "r" { left -= spill }
                }
            } else if props.anchorCenter {
                left = leftEdge + (columnWidth - layout.width) / 2
            }
            if layout.height > box.height, props.anchor != "b", props.anchor != "ctr" { top = box.minY }
            TextPainter.draw(layout, at: CGPoint(x: left, y: top), in: context, links: &found)
        }
        let ctm = context.ctm
        for link in found { links.append(TextLinkArea(rect: link.rect.applying(ctm), url: link.url)) }
    }
}

// MARK: Tables

struct TableRenderer {
    struct Part {
        var fill: FillSpec?
        var borders: [String: LineSpec?] = [:]
        var textColor: NSColor?
        var bold: Bool?
        var italic: Bool?
    }

    let renderer: SlideRenderer
    let table: XMLElement
    let part: URL

    var palette: DrawingPalette { renderer.palette }

    func styleParts() -> [String: Part] {
        let id = table.kid("tblPr")?.kid("tableStyleId")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"
        if let style = renderer.deck.tableStyles?.kids("tblStyle").first(where: { $0.attr("styleId") == id }) {
            var output: [String: Part] = [:]
            for node in style.elements {
                guard let name = node.localName else { continue }
                output[name] = parse(node)
            }
            return output
        }
        guard id == "{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}" else { return [:] }
        let accent = palette.scheme("accent1") ?? .systemBlue
        let light = palette.scheme("lt1") ?? .white
        let dark = palette.scheme("dk1") ?? .black
        let thin = LineSpec(color: light, width: 1)
        let thick = LineSpec(color: light, width: 3)
        return [
            "wholeTbl": Part(fill: .solid(accent.blended(with: .white, fraction: 0.8)),
                             borders: ["left": thin, "right": thin, "top": thin, "bottom": thin, "insideH": thin, "insideV": thin],
                             textColor: dark),
            "band1H": Part(fill: .solid(accent.blended(with: .white, fraction: 0.6))),
            "band1V": Part(fill: .solid(accent.blended(with: .white, fraction: 0.6))),
            "firstRow": Part(fill: .solid(accent), borders: ["bottom": thick], textColor: light, bold: true),
            "lastRow": Part(fill: .solid(accent), borders: ["top": thick], textColor: light, bold: true),
            "firstCol": Part(fill: .solid(accent), textColor: light, bold: true),
            "lastCol": Part(fill: .solid(accent), textColor: light, bold: true)
        ]
    }

    func parse(_ node: XMLElement) -> Part {
        var output = Part()
        if let text = node.kid("tcTxStyle") {
            if let value = text.attr("b") { output.bold = value == "on" }
            if let value = text.attr("i") { output.italic = value == "on" }
            output.textColor = palette.color(in: text) ?? text.kid("fontRef").flatMap { palette.color(in: $0) }
        }
        if let cell = node.kid("tcStyle") {
            if let fill = cell.kid("fill") {
                output.fill = renderer.fillSpec(in: fill, part: part, palette: palette)
            } else if let reference = cell.kid("fillRef") {
                output.fill = renderer.themeFill(reference, part: part)
            }
            for edge in cell.kid("tcBdr")?.elements ?? [] {
                guard let name = edge.localName else { continue }
                if let line = edge.kid("ln") {
                    output.borders[name] = .some(renderer.resolveLine([line], style: nil))
                } else if let reference = edge.kid("lnRef") {
                    let holder = XMLElement(name: "style")
                    holder.addChild(reference.copy() as! XMLElement)
                    output.borders[name] = .some(renderer.resolveLine([], style: holder))
                }
            }
        }
        return output
    }

    struct Cell {
        var node: XMLElement
        var row: Int
        var column: Int
        var rowSpan: Int
        var columnSpan: Int
    }

    func draw(in frame: CGRect) {
        let gridEMU = table.kid("tblGrid")?.kids("gridCol").map { $0.number("w") } ?? []
        let rows = table.kids("tr")
        guard !rows.isEmpty, !gridEMU.isEmpty else { return }
        let widths = gridEMU.map { $0 / emuPerPoint }
        var heights = rows.map { max($0.number("h") / emuPerPoint, 1) }
        let flags = table.kid("tblPr")
        let firstRow = flags?.flag("firstRow") == true, lastRow = flags?.flag("lastRow") == true
        let firstCol = flags?.flag("firstCol") == true, lastCol = flags?.flag("lastCol") == true
        let bandRow = flags?.flag("bandRow") == true, bandCol = flags?.flag("bandCol") == true
        let styles = styleParts()
        let rowCount = rows.count, columnCount = widths.count

        var cells: [Cell] = []
        for (r, row) in rows.enumerated() {
            var c = 0
            for node in row.kids("tc") {
                guard c < columnCount else { break }
                let columnSpan = max(Int(node.attr("gridSpan") ?? "") ?? 1, 1)
                if node.flag("hMerge") == true {
                    c += 1
                    continue
                }
                if node.flag("vMerge") == true {
                    c += columnSpan
                    continue
                }
                let rowSpan = max(Int(node.attr("rowSpan") ?? "") ?? 1, 1)
                cells.append(Cell(node: node, row: r, column: c, rowSpan: min(rowSpan, rowCount - r), columnSpan: min(columnSpan, columnCount - c)))
                c += columnSpan
            }
        }

        func regions(_ cell: Cell) -> [(Part, ClosedRange<Int>, ClosedRange<Int>)] {
            var output: [(Part, ClosedRange<Int>, ClosedRange<Int>)] = []
            func add(_ name: String, _ rows: ClosedRange<Int>, _ columns: ClosedRange<Int>) {
                if let part = styles[name] { output.append((part, rows, columns)) }
            }
            add("wholeTbl", 0...(rowCount - 1), 0...(columnCount - 1))
            let dataStart = firstRow ? 1 : 0
            if bandCol {
                let index = cell.column - (firstCol ? 1 : 0)
                if index >= 0 { add(index % 2 == 0 ? "band1V" : "band2V", 0...(rowCount - 1), cell.column...cell.column) }
            }
            if bandRow {
                let index = cell.row - dataStart
                if index >= 0 { add(index % 2 == 0 ? "band1H" : "band2H", cell.row...cell.row, 0...(columnCount - 1)) }
            }
            if firstCol, cell.column == 0 { add("firstCol", 0...(rowCount - 1), 0...0) }
            if lastCol, cell.column + cell.columnSpan == columnCount { add("lastCol", 0...(rowCount - 1), (columnCount - 1)...(columnCount - 1)) }
            if lastRow, cell.row + cell.rowSpan == rowCount { add("lastRow", (rowCount - 1)...(rowCount - 1), 0...(columnCount - 1)) }
            if firstRow, cell.row == 0 { add("firstRow", 0...0, 0...(columnCount - 1)) }
            return output
        }

        func textStyles(_ cell: Cell) -> TextStyleChain {
            var chain = TextStyleChain()
            chain.apply(renderer.deck.defaultTextStyle, palette: palette)
            for (part, _, _) in regions(cell) {
                chain.setColor(part.textColor)
                if let bold = part.bold { for index in chain.levels.indices { chain.levels[index].run.bold = bold } }
                if let italic = part.italic { for index in chain.levels.indices { chain.levels[index].run.italic = italic } }
            }
            chain.apply(cell.node.kid("txBody")?.kid("lstStyle"), palette: palette)
            return chain
        }

        func bodyProps(_ cell: Cell) -> TextBody {
            let tcPr = cell.node.kid("tcPr")
            var props = TextBody()
            props.insets = NSEdgeInsets(
                top: (tcPr?.optionalNumber("marT") ?? 45_720) / emuPerPoint,
                left: (tcPr?.optionalNumber("marL") ?? 91_440) / emuPerPoint,
                bottom: (tcPr?.optionalNumber("marB") ?? 45_720) / emuPerPoint,
                right: (tcPr?.optionalNumber("marR") ?? 91_440) / emuPerPoint
            )
            props.anchor = tcPr?.attr("anchor") ?? "t"
            props.vertical = tcPr?.attr("vert") ?? "horz"
            return props
        }

        func span(_ values: [CGFloat], _ start: Int, _ count: Int) -> CGFloat {
            values[start..<min(start + count, values.count)].reduce(0, +)
        }

        // Rows grow to fit their text, then the whole table is scaled back into the frame.
        for cell in cells where cell.rowSpan == 1 {
            guard let body = cell.node.kid("txBody") else { continue }
            let props = bodyProps(cell)
            let width = span(widths, cell.column, cell.columnSpan) - props.insets.left - props.insets.right
            let paragraphs = renderer.paragraphs(body, styles: textStyles(cell), part: part)
            guard paragraphs.contains(where: { !$0.runs.isEmpty }) else { continue }
            let layout = TextLayoutEngine.layout(paragraphs, width: max(width, 1), wrap: true, fontScale: 1, spacingReduction: 0, defaultColor: palette.text)
            heights[cell.row] = max(heights[cell.row], layout.height + props.insets.top + props.insets.bottom)
        }
        let natural = heights.reduce(0, +)
        if natural > frame.height, natural > 0 {
            let scale = frame.height / natural
            heights = heights.map { max($0 * scale, 1) }
        }

        renderer.context.saveGState()
        renderer.context.clip(to: frame.insetBy(dx: -0.5, dy: -0.5))
        defer { renderer.context.restoreGState() }

        var xs: [CGFloat] = [frame.minX]
        for width in widths { xs.append(xs.last! + width) }
        var ys: [CGFloat] = [frame.minY]
        for height in heights { ys.append(ys.last! + height) }
        func rect(_ cell: Cell) -> CGRect {
            CGRect(x: xs[cell.column], y: ys[cell.row],
                   width: xs[cell.column + cell.columnSpan] - xs[cell.column],
                   height: ys[cell.row + cell.rowSpan] - ys[cell.row])
        }

        for cell in cells {
            let area = rect(cell)
            var fill: FillSpec?
            for (part, _, _) in regions(cell) where part.fill != nil { fill = part.fill }
            if let tcPr = cell.node.kid("tcPr"), let own = renderer.fillSpec(in: tcPr, part: part, palette: palette) { fill = own }
            if let fill { renderer.paint(fill, path: CGPath(rect: area, transform: nil), rect: area, evenOdd: false) }
        }
        for cell in cells {
            guard let body = cell.node.kid("txBody") else { continue }
            renderer.drawText(body, in: rect(cell), props: bodyProps(cell), styles: textStyles(cell), part: part)
        }
        for cell in cells {
            let area = rect(cell)
            let tcPr = cell.node.kid("tcPr")
            let edges: [(String, String, CGPoint, CGPoint, Bool)] = [
                ("lnL", "left", CGPoint(x: area.minX, y: area.minY), CGPoint(x: area.minX, y: area.maxY), cell.column == 0),
                ("lnR", "right", CGPoint(x: area.maxX, y: area.minY), CGPoint(x: area.maxX, y: area.maxY), cell.column + cell.columnSpan == columnCount),
                ("lnT", "top", CGPoint(x: area.minX, y: area.minY), CGPoint(x: area.maxX, y: area.minY), cell.row == 0),
                ("lnB", "bottom", CGPoint(x: area.minX, y: area.maxY), CGPoint(x: area.maxX, y: area.maxY), cell.row + cell.rowSpan == rowCount)
            ]
            let cellRegions = regions(cell)
            for (own, edge, from, to, _) in edges {
                var line: LineSpec?
                for (stylePart, rowRange, columnRange) in cellRegions {
                    let boundary: Bool
                    switch edge {
                    case "left": boundary = cell.column == columnRange.lowerBound
                    case "right": boundary = cell.column + cell.columnSpan - 1 == columnRange.upperBound
                    case "top": boundary = cell.row == rowRange.lowerBound
                    default: boundary = cell.row + cell.rowSpan - 1 == rowRange.upperBound
                    }
                    let key = boundary ? edge : (edge == "left" || edge == "right" ? "insideV" : "insideH")
                    if let value = stylePart.borders[key] { line = value }
                }
                if let explicit = tcPr?.kid(own),
                   explicit.kid("noFill") != nil || explicit.kid("solidFill") != nil || explicit.kid("gradFill") != nil {
                    line = renderer.resolveLine([explicit], style: nil, base: LineSpec(color: nil))
                }
                guard let line, let color = line.color, line.width > 0 else { continue }
                renderer.context.saveGState()
                renderer.context.setStrokeColor(color.srgbCG)
                renderer.context.setLineWidth(line.width)
                if let pattern = renderer.dashPattern(line.dash, width: line.width) { renderer.context.setLineDash(phase: 0, lengths: pattern) }
                renderer.context.move(to: from)
                renderer.context.addLine(to: to)
                renderer.context.strokePath()
                renderer.context.restoreGState()
            }
        }
    }
}
