import AppKit
import CoreText
import Foundation
import ImageIO

/// Renders a PowerPoint deck to PDF on this Mac. Charts and SmartArt are left out;
/// slides, text, pictures, solid shapes and simple tables are drawn in place.
public enum PresentationConverter {
    public static func convert(_ url: URL) throws -> URL {
        guard Catalog.isPresentation(url) else { throw OrangeError.unsupported(url.pathExtension.uppercased()) }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("orange-pptx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let zip = scratch.appendingPathComponent("source.zip")
        try FileManager.default.copyItem(at: url, to: zip)
        let unpacked = try ArchiveToolkit.extract(archive: zip, into: scratch)
        guard let presentation = findPresentation(in: unpacked) else {
            throw OrangeError.unreadable(url.lastPathComponent)
        }
        let packageRoot = presentation.deletingLastPathComponent().deletingLastPathComponent()
        let document = try loadXML(presentation)
        let relations = relationships(for: presentation)
        let slides = (document.kid("sldIdLst")?.kids("sldId") ?? []).compactMap { node -> URL? in
            guard let id = relationshipID(node), let target = relations[id]?.target else { return nil }
            return resolve(target, from: presentation, root: packageRoot)
        }
        guard !slides.isEmpty else { throw OrangeError.unreadable(url.lastPathComponent) }

        let width = (document.kid("sldSz")?.optionalEmu("cx") ?? 12_192_000) / emuPerPoint
        let height = (document.kid("sldSz")?.optionalEmu("cy") ?? 6_858_000) / emuPerPoint
        guard width > 10, height > 10, width < 20_000, height < 20_000 else {
            throw OrangeError.unreadable(url.lastPathComponent)
        }

        let destination = UniqueDestination.url(
            in: OutputLocation.directory(beside: url),
            baseName: OutputLocation.baseName(url),
            extension: "pdf"
        )
        var page = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(url: destination as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &page, nil) else {
            throw OrangeError.writeFailed(destination.lastPathComponent)
        }
        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let renderer = DeckRenderer(context: context, pageWidth: width, pageHeight: height, packageRoot: packageRoot)
        var rendered = 0
        for slide in slides {
            guard let root = try? loadXML(slide), flag(root.attr("show")) != false else { continue }
            context.beginPDFPage(nil)
            renderer.drawSlide(root, file: slide)
            context.endPDFPage()
            rendered += 1
        }
        context.closePDF()
        guard rendered > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw OrangeError.unreadable(url.lastPathComponent)
        }
        return destination
    }
}

private let emuPerPoint: CGFloat = 12_700

private final class DeckRenderer {
    let context: CGContext
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let packageRoot: URL
    var themes: [URL: Theme] = [:]

    init(context: CGContext, pageWidth: CGFloat, pageHeight: CGFloat, packageRoot: URL) {
        self.context = context
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
        self.packageRoot = packageRoot
    }

    func drawSlide(_ root: XMLElement, file: URL) {
        let theme = theme(for: file)
        drawBackground(of: file, theme: theme)
        guard let tree = root.kid("cSld")?.kid("spTree") else { return }
        let placeholders = placeholderStyles(for: file, theme: theme)
        let relations = relationships(for: file)
        drawTree(tree, space: .identity, file: file, relations: relations, theme: theme, placeholders: placeholders, depth: 0)
    }

    func drawBackground(of file: URL, theme: Theme) {
        let page = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        var color = NSColor.white
        var image: CGImage?
        if let source = backgroundSource(of: file) {
            if let found = backdropColor(source.element, theme: theme) { color = found }
            let relations = relationships(for: source.file)
            if let blip = source.element.kid("bgPr")?.kid("blipFill")?.kid("blip"),
               let picture = loadPicture(blip, relations: relations, file: source.file) {
                image = picture
            }
        }
        context.setFillColor(pdfColor(color))
        context.fill(page)
        if let image { draw(image, in: page) }
    }

    func backgroundSource(of file: URL) -> (element: XMLElement, file: URL)? {
        var files = [file]
        if let layout = related(file, kind: "slideLayout") { files.append(layout) }
        if let master = files.last.flatMap({ related($0, kind: "slideMaster") }), master != file { files.append(master) }
        for candidate in files {
            guard let xml = try? loadXML(candidate), let background = xml.kid("cSld")?.kid("bg") else { continue }
            return (background, candidate)
        }
        return nil
    }

    func drawTree(
        _ tree: XMLElement,
        space: Space,
        file: URL,
        relations: [String: Relationship],
        theme: Theme,
        placeholders: [String: TextStyle],
        depth: Int
    ) {
        guard depth < 40 else { return }
        let childSpace = tree.xfrm().map { space.nested($0) } ?? space
        for node in tree.drawables() {
            switch node.localName {
            case "grpSp":
                drawTree(node, space: childSpace, file: file, relations: relations, theme: theme, placeholders: placeholders, depth: depth + 1)
            case "graphicFrame":
                drawTable(node, space: childSpace, theme: theme, placeholders: placeholders)
            default:
                drawShape(node, space: childSpace, file: file, relations: relations, theme: theme, placeholders: placeholders)
            }
        }
    }

    func drawShape(
        _ shape: XMLElement,
        space: Space,
        file: URL,
        relations: [String: Relationship],
        theme: Theme,
        placeholders: [String: TextStyle]
    ) {
        guard let xfrm = shape.xfrm() else { return }
        let rect = pdfRect(space.rect(of: xfrm))
        guard rect.width > 0.5, rect.height > 0.5 else { return }
        let rotation = CGFloat(Double(xfrm.attr("rot") ?? "") ?? 0) / 60_000
        let flipH = flag(xfrm.attr("flipH")) == true
        let flipV = flag(xfrm.attr("flipV")) == true

        context.saveGState()
        if rotation != 0 || flipH || flipV {
            context.translateBy(x: rect.midX, y: rect.midY)
            if rotation != 0 { context.rotate(by: -rotation * .pi / 180) }
            if flipH || flipV { context.scaleBy(x: flipH ? -1 : 1, y: flipV ? -1 : 1) }
            context.translateBy(x: -rect.midX, y: -rect.midY)
        }

        let properties = shape.kid("spPr")
        if let fill = fillColor(properties, shape: shape, theme: theme) {
            context.setFillColor(pdfColor(fill))
            addPath(properties, rect: rect)
            context.fillPath()
        }
        if let blip = shape.kid("blipFill")?.kid("blip") ?? properties?.kid("blipFill")?.kid("blip"),
           let picture = loadPicture(blip, relations: relations, file: file) {
            draw(picture, in: rect)
        }
        if let stroke = stroke(properties, shape: shape, theme: theme) {
            context.setStrokeColor(pdfColor(stroke.color))
            context.setLineWidth(stroke.width)
            addPath(properties, rect: rect)
            context.strokePath()
        }
        if let body = shape.kid("txBody") {
            drawText(body, in: rect, shape: shape, theme: theme, placeholders: placeholders)
        }
        context.restoreGState()
    }

    func drawTable(_ frame: XMLElement, space: Space, theme: Theme, placeholders: [String: TextStyle]) {
        guard let xfrm = frame.xfrm(), let table = frame.deep("tbl") else { return }
        let bounds = pdfRect(space.rect(of: xfrm))
        guard bounds.width > 1, bounds.height > 1 else { return }
        let columns = table.kid("tblGrid")?.kids("gridCol").map { $0.emu("w") } ?? []
        let rows = table.kids("tr")
        guard !rows.isEmpty else { return }
        let columnSum = columns.reduce(0, +)
        let widths: [CGFloat] = columnSum > 0
            ? columns.map { $0 / emuPerPoint * bounds.width / (columnSum / emuPerPoint) }
            : [bounds.width]
        let naturalHeight = rows.reduce(CGFloat(0)) { $0 + $1.emu("h") } / emuPerPoint
        let heightScale = naturalHeight > bounds.height && naturalHeight > 0 ? bounds.height / naturalHeight : 1
        var y = bounds.maxY
        for row in rows {
            let rowHeight = max((row.optionalEmu("h") ?? (bounds.height / CGFloat(rows.count) * emuPerPoint)) / emuPerPoint * heightScale, 1)
            y -= rowHeight
            var x = bounds.minX
            var column = 0
            for cell in row.kids("tc") {
                if cell.attr("hMerge") == "1" {
                    if column < widths.count { x += widths[column] }
                    column += 1
                    continue
                }
                let span = max(Int(cell.attr("gridSpan") ?? "") ?? 1, 1)
                var width: CGFloat = 0
                for _ in 0..<span {
                    width += column < widths.count ? widths[column] : 0
                    column += 1
                }
                let cellRect = CGRect(x: x, y: y, width: max(width, 1), height: rowHeight)
                x += width
                if cell.attr("vMerge") == "1" { continue }
                if let fill = cell.kid("tcPr")?.kid("solidFill").flatMap({ readColor($0, theme: theme) }) {
                    context.setFillColor(pdfColor(fill))
                    context.fill(cellRect)
                }
                if let body = cell.kid("txBody") {
                    drawText(body, in: cellRect, shape: cell, theme: theme, placeholders: placeholders)
                }
            }
        }
    }

    func drawText(_ body: XMLElement, in rect: CGRect, shape: XMLElement, theme: Theme, placeholders: [String: TextStyle]) {
        let defaults = textDefaults(shape, body: body, theme: theme, placeholders: placeholders)
        let paragraphs = paragraphs(in: body, defaults: defaults, theme: theme)
        guard !paragraphs.isEmpty else { return }
        let props = body.kid("bodyPr")
        let left = (props?.optionalEmu("lIns") ?? 91_440) / emuPerPoint
        let right = (props?.optionalEmu("rIns") ?? 91_440) / emuPerPoint
        let top = (props?.optionalEmu("tIns") ?? 45_720) / emuPerPoint
        let bottom = (props?.optionalEmu("bIns") ?? 45_720) / emuPerPoint
        let box = CGRect(
            x: rect.minX + left,
            y: rect.minY + bottom,
            width: rect.width - left - right,
            height: rect.height - top - bottom
        )
        guard box.width > 2, box.height > 2 else { return }

        let text = attributed(paragraphs)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        var fit = CFRange()
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: text.length),
            nil,
            CGSize(width: box.width, height: .greatestFiniteMagnitude),
            &fit
        )
        let used = min(box.height, max(ceil(suggested.height), 1))
        let y: CGFloat = switch defaults.anchor {
        case .top: box.maxY - used
        case .middle: box.minY + (box.height - used) / 2
        case .bottom: box.minY
        }
        let frameRect = CGRect(x: box.minX, y: y, width: box.width, height: max(used, 1))
        context.saveGState()
        context.clip(to: rect)
        let path = CGPath(rect: frameRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    func addPath(_ properties: XMLElement?, rect: CGRect) {
        switch properties?.kid("prstGeom")?.attr("prst") {
        case "ellipse":
            context.addEllipse(in: rect)
        case "roundRect":
            let fraction = cornerFraction(properties?.kid("prstGeom"))
            let radius = min(rect.width, rect.height) * fraction
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        default:
            context.addRect(rect)
        }
    }

    func draw(_ image: CGImage, in rect: CGRect) {
        context.draw(image, in: rect)
    }

    func pdfRect(_ emu: CGRect) -> CGRect {
        CGRect(
            x: emu.minX / emuPerPoint,
            y: pageHeight - (emu.minY + emu.height) / emuPerPoint,
            width: emu.width / emuPerPoint,
            height: emu.height / emuPerPoint
        )
    }

    func loadPicture(_ blip: XMLElement, relations: [String: Relationship], file: URL) -> CGImage? {
        guard let id = embedID(blip), let target = relations[id]?.target,
              let url = resolve(target, from: file, root: packageRoot),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func theme(for file: URL) -> Theme {
        let url = themeURL(for: file) ?? packageRoot.appendingPathComponent("ppt/theme/theme1.xml")
        if let cached = themes[url] { return cached }
        let loaded = Theme.load(url)
        themes[url] = loaded
        return loaded
    }

    func themeURL(for file: URL) -> URL? {
        let layout = related(file, kind: "slideLayout")
        let master = layout.flatMap { related($0, kind: "slideMaster") } ?? related(file, kind: "slideMaster")
        if let master, let theme = related(master, kind: "theme") { return theme }
        return nil
    }

    func related(_ file: URL, kind: String) -> URL? {
        guard let target = relationships(for: file).values.first(where: { $0.type.hasSuffix(kind) })?.target else { return nil }
        return resolve(target, from: file, root: packageRoot)
    }

    func placeholderStyles(for file: URL, theme: Theme) -> [String: TextStyle] {
        var styles: [String: TextStyle] = [:]
        let layout = related(file, kind: "slideLayout")
        let master = layout.flatMap { related($0, kind: "slideMaster") }
        for source in [master, layout].compactMap({ $0 }) {
            guard let xml = try? loadXML(source), let tree = xml.kid("cSld")?.kid("spTree") else { continue }
            for shape in tree.shapes() {
                guard let placeholder = placeholder(in: shape) else { continue }
                styles["\(placeholder.type)#\(placeholder.index)"] = textStyle(shape, type: placeholder.type, theme: theme)
            }
        }
        return styles
    }
}

private struct Relationship {
    var type: String
    var target: String
}

private struct Space {
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0

    static let identity = Space()

    func rect(of xfrm: XMLElement) -> CGRect {
        let origin = xfrm.point("off")
        let size = xfrm.point("ext")
        return CGRect(
            x: offsetX + origin.x * scaleX,
            y: offsetY + origin.y * scaleY,
            width: max(size.x * scaleX, 0),
            height: max(size.y * scaleY, 0)
        )
    }

    func nested(_ xfrm: XMLElement) -> Space {
        let origin = xfrm.point("off")
        let size = xfrm.point("ext")
        let childOrigin = xfrm.point("chOff")
        let childSize = xfrm.point("chExt")
        let scaleChildX = childSize.x == 0 ? 1 : size.x / childSize.x
        let scaleChildY = childSize.y == 0 ? 1 : size.y / childSize.y
        return Space(
            scaleX: scaleX * scaleChildX,
            scaleY: scaleY * scaleChildY,
            offsetX: offsetX + (origin.x - childOrigin.x * scaleChildX) * scaleX,
            offsetY: offsetY + (origin.y - childOrigin.y * scaleChildY) * scaleY
        )
    }
}

private enum VerticalAnchor { case top, middle, bottom }

private struct TextStyle {
    var size: CGFloat = 18
    var bold = false
    var italic = false
    var color: NSColor?
    var fontName: String?
    var align: NSTextAlignment = .left
    var anchor: VerticalAnchor = .top
    var bullet = false

    static func builtin(_ type: String) -> TextStyle {
        var style = TextStyle()
        switch type {
        case "ctrTitle":
            style.size = 40
            style.align = .center
        case "title":
            style.size = 36
            style.bold = true
        case "subTitle":
            style.size = 20
        case "body", "obj":
            style.size = 18
            style.bullet = true
        default:
            break
        }
        return style
    }
}

private struct Paragraph {
    var runs: [(text: String, style: TextStyle)]
    var style: TextStyle
    var level: Int
}

private struct Theme {
    var colors: [String: NSColor] = [
        "dk1": .black,
        "lt1": .white,
        "dk2": NSColor(srgbRed: 0.15, green: 0.15, blue: 0.15, alpha: 1),
        "lt2": NSColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 1),
        "bg1": .white,
        "tx1": .black,
        "bg2": NSColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 1),
        "tx2": NSColor(srgbRed: 0.15, green: 0.15, blue: 0.15, alpha: 1)
    ]
    var majorFont = ""
    var minorFont = ""

    static func load(_ url: URL) -> Theme {
        guard let root = try? loadXML(url) else { return Theme() }
        var theme = Theme()
        if let scheme = root.deep("clrScheme") {
            for case let child as XMLElement in scheme.children ?? [] {
                guard let name = child.localName, let color = readColor(child, theme: theme) else { continue }
                theme.colors[name] = color
            }
        }
        theme.colors["bg1"] = theme.colors["lt1"]
        theme.colors["tx1"] = theme.colors["dk1"]
        theme.colors["bg2"] = theme.colors["lt2"]
        theme.colors["tx2"] = theme.colors["dk2"]
        theme.majorFont = root.deep("majorFont")?.kid("latin")?.attr("typeface") ?? ""
        theme.minorFont = root.deep("minorFont")?.kid("latin")?.attr("typeface") ?? ""
        return theme
    }

    func color(_ name: String?) -> NSColor? {
        guard let name else { return nil }
        return colors[name]
    }

    func resolve(_ typeface: String?) -> String? {
        switch typeface {
        case "+mj-lt", "+mj-ea", "+mj-cs": majorFont.isEmpty ? nil : majorFont
        case "+mn-lt", "+mn-ea", "+mn-cs": minorFont.isEmpty ? nil : minorFont
        case let face?: face.isEmpty ? nil : face
        default: nil
        }
    }
}

private struct Stroke {
    var color: NSColor
    var width: CGFloat
}

private func findPresentation(in root: URL) -> URL? {
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
    for case let file as URL in enumerator {
        if file.lastPathComponent == "presentation.xml", file.deletingLastPathComponent().lastPathComponent == "ppt" {
            return file
        }
    }
    return nil
}

private func loadXML(_ url: URL) throws -> XMLElement {
    let document: XMLDocument
    do {
        document = try XMLDocument(contentsOf: url, options: [.nodePreserveWhitespace])
    } catch {
        throw OrangeError.unreadable(url.lastPathComponent)
    }
    guard let root = document.rootElement() else { throw OrangeError.unreadable(url.lastPathComponent) }
    return root
}

private func relationships(for file: URL) -> [String: Relationship] {
    let url = file.deletingLastPathComponent()
        .appendingPathComponent("_rels")
        .appendingPathComponent(file.lastPathComponent + ".rels")
    guard let root = try? loadXML(url) else { return [:] }
    var map: [String: Relationship] = [:]
    for node in root.kids("Relationship") {
        guard let id = node.attr("Id") ?? node.attr("ID"), let target = node.attr("Target") else { continue }
        map[id] = Relationship(type: node.attr("Type") ?? "", target: target)
    }
    return map
}

private func resolve(_ target: String, from file: URL, root: URL) -> URL? {
    let cleaned = (target.removingPercentEncoding ?? target).replacingOccurrences(of: "\\", with: "/")
    guard !cleaned.contains("://"), !cleaned.isEmpty else { return nil }
    let url = cleaned.hasPrefix("/")
        ? root.appendingPathComponent(String(cleaned.dropFirst()))
        : file.deletingLastPathComponent().appendingPathComponent(cleaned)
    let standard = url.standardizedFileURL
    let rootPath = root.standardizedFileURL.path
    let path = standard.path
    guard path == rootPath || path.hasPrefix(rootPath + "/") else { return nil }
    return standard
}

private func relationshipID(_ element: XMLElement) -> String? {
    for node in element.attributes ?? [] {
        let name = node.name ?? ""
        if node.localName == "id", (node.uri ?? "").contains("relationships") || name.contains(":") {
            return node.stringValue
        }
    }
    return element.attribute(forName: "r:id")?.stringValue
}

private func embedID(_ element: XMLElement) -> String? {
    for node in element.attributes ?? [] {
        let name = node.name ?? ""
        if node.localName == "embed", (node.uri ?? "").contains("relationships") || name.contains(":") {
            return node.stringValue
        }
    }
    return element.attribute(forName: "r:embed")?.stringValue
}

private func flag(_ raw: String?) -> Bool? {
    switch raw?.lowercased() {
    case "1", "true", "on": true
    case "0", "false", "off": false
    default: nil
    }
}

private func placeholder(in shape: XMLElement) -> (type: String, index: String)? {
    let holder = shape.kid("nvSpPr")?.kid("nvPr")?.kid("ph") ?? shape.kid("nvPicPr")?.kid("nvPr")?.kid("ph")
    guard let holder else { return nil }
    return (holder.attr("type") ?? "body", holder.attr("idx") ?? "0")
}

private func textStyle(_ shape: XMLElement, type: String, theme: Theme) -> TextStyle {
    var style = TextStyle.builtin(type)
    if let body = shape.kid("txBody") {
        if let anchor = body.kid("bodyPr")?.attr("anchor") { style.anchor = verticalAnchor(anchor) }
        let list = body.kid("lstStyle")
        apply(list?.kid("lvl1pPr")?.kid("defRPr") ?? list?.deep("defRPr"), to: &style, theme: theme)
    }
    if style.color == nil, let font = shape.kid("style")?.kid("fontRef") {
        style.color = readColor(font, theme: theme)
    }
    return style
}

private func textDefaults(_ shape: XMLElement, body: XMLElement, theme: Theme, placeholders: [String: TextStyle]) -> TextStyle {
    let slot = placeholder(in: shape)
    var style = slot.flatMap { placeholders["\($0.type)#\($0.index)"] ?? placeholders["\($0.type)#0"] }
        ?? TextStyle.builtin(slot?.type ?? "")
    if let anchor = body.kid("bodyPr")?.attr("anchor") { style.anchor = verticalAnchor(anchor) }
    let list = body.kid("lstStyle")
    apply(list?.kid("lvl1pPr")?.kid("defRPr") ?? list?.deep("defRPr"), to: &style, theme: theme)
    if style.color == nil, let font = shape.kid("style")?.kid("fontRef") {
        style.color = readColor(font, theme: theme)
    }
    return style
}

private func verticalAnchor(_ raw: String?) -> VerticalAnchor {
    switch raw {
    case "ctr": .middle
    case "b": .bottom
    default: .top
    }
}

private func alignment(_ raw: String?) -> NSTextAlignment {
    switch raw {
    case "ctr": .center
    case "r": .right
    case "just": .justified
    default: .left
    }
}

private func apply(_ props: XMLElement?, to style: inout TextStyle, theme: Theme) {
    guard let props else { return }
    if let size = Double(props.attr("sz") ?? "") {
        style.size = min(max(CGFloat(size) / 100, 1), 200)
    }
    if let bold = flag(props.attr("b")) { style.bold = bold }
    if let italic = flag(props.attr("i")) { style.italic = italic }
    let face = props.kid("latin")?.attr("typeface") ?? props.kid("cs")?.attr("typeface") ?? props.kid("ea")?.attr("typeface")
    if let resolved = theme.resolve(face) { style.fontName = resolved }
    if let color = props.kid("solidFill").flatMap({ readColor($0, theme: theme) }) { style.color = color }
}

private func paragraphs(in body: XMLElement, defaults: TextStyle, theme: Theme) -> [Paragraph] {
    var output: [Paragraph] = []
    for paragraph in body.kids("p") {
        var style = defaults
        let properties = paragraph.kid("pPr")
        apply(paragraph.kid("endParaRPr"), to: &style, theme: theme)
        apply(properties?.kid("defRPr"), to: &style, theme: theme)
        if let align = properties?.attr("algn") { style.align = alignment(align) }
        if properties?.kid("buNone") != nil { style.bullet = false }
        if properties?.kid("buChar") != nil || properties?.kid("buAutoNum") != nil || properties?.kid("buFont") != nil {
            style.bullet = true
        }
        let level = Int(properties?.attr("lvl") ?? "") ?? 0
        var runs: [(text: String, style: TextStyle)] = []
        for case let child as XMLElement in paragraph.children ?? [] {
            switch child.localName {
            case "br":
                runs.append(("\n", style))
            case "tab":
                runs.append(("    ", style))
            case "r", "fld":
                var run = style
                apply(child.kid("rPr"), to: &run, theme: theme)
                let text = child.kids("t").compactMap(\.stringValue).joined()
                if !text.isEmpty { runs.append((text, run)) }
            default:
                break
            }
        }
        if runs.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            output.append(Paragraph(runs: runs, style: style, level: level))
        }
    }
    return output
}

private func attributed(_ paragraphs: [Paragraph]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for (index, paragraph) in paragraphs.enumerated() {
        let start = result.length
        let marker = paragraph.runs.first?.style ?? paragraph.style
        if paragraph.style.bullet { result.append(piece("• ", marker)) }
        for run in paragraph.runs { result.append(piece(run.text, run.style)) }
        if index < paragraphs.count - 1 { result.append(piece("\n", marker)) }
        guard result.length > start else { continue }
        let format = NSMutableParagraphStyle()
        format.alignment = paragraph.style.align
        let indent = CGFloat(paragraph.level) * 16
        format.firstLineHeadIndent = indent
        format.headIndent = indent + (paragraph.style.bullet ? 14 : 0)
        format.lineBreakMode = .byWordWrapping
        format.paragraphSpacing = 2
        result.addAttribute(.paragraphStyle, value: format, range: NSRange(location: start, length: result.length - start))
    }
    return result
}

private func piece(_ text: String, _ style: TextStyle) -> NSAttributedString {
    let size = max(style.size, 1)
    let base = style.fontName.flatMap { NSFont(name: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
    let font: NSFont
    if style.bold || style.italic {
        var traits = NSFontDescriptor.SymbolicTraits()
        if style.bold { traits.insert(.bold) }
        if style.italic { traits.insert(.italic) }
        let described = base.fontDescriptor.withSymbolicTraits(traits)
        font = NSFont(descriptor: described, size: size) ?? (style.bold ? NSFont.boldSystemFont(ofSize: size) : base)
    } else {
        font = base
    }
    return NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: style.color ?? .black
    ])
}

private func fillColor(_ properties: XMLElement?, shape: XMLElement, theme: Theme) -> NSColor? {
    if let properties {
        if properties.kid("noFill") != nil { return nil }
        if let solid = properties.kid("solidFill"), let color = readColor(solid, theme: theme) { return color }
        if let gradient = properties.kid("gradFill"),
           let stop = gradient.kid("gsLst")?.kid("gs") ?? gradient.kid("gs"),
           let color = readColor(stop, theme: theme) {
            return color
        }
    }
    if let reference = shape.kid("style")?.kid("fillRef") {
        if reference.attr("idx") == "0" { return nil }
        return readColor(reference, theme: theme)
    }
    return nil
}

private func stroke(_ properties: XMLElement?, shape: XMLElement, theme: Theme) -> Stroke? {
    guard let line = properties?.kid("ln"), line.kid("noFill") == nil else { return nil }
    let width = max((line.optionalEmu("w") ?? 9_525) / emuPerPoint, 0.25)
    let color = line.kid("solidFill").flatMap { readColor($0, theme: theme) }
        ?? shape.kid("style")?.kid("lnRef").flatMap { readColor($0, theme: theme) }
        ?? .black
    return Stroke(color: color, width: width)
}

private func backdropColor(_ background: XMLElement, theme: Theme) -> NSColor? {
    if let paint = background.kid("bgPr") {
        if paint.kid("solidFill") != nil || paint.kid("gradFill") != nil {
            return fillColor(paint, shape: background, theme: theme)
        }
    }
    if let reference = background.kid("bgRef") { return readColor(reference, theme: theme) }
    return nil
}

private func readColor(_ element: XMLElement, theme: Theme) -> NSColor? {
    let node: XMLElement?
    switch element.localName {
    case "srgbClr", "schemeClr", "sysClr", "prstClr":
        node = element
    default:
        node = element.kid("srgbClr") ?? element.kid("schemeClr") ?? element.kid("sysClr") ?? element.kid("prstClr")
    }
    guard let node else { return nil }
    let base: NSColor?
    switch node.localName {
    case "srgbClr":
        base = NSColor(hex: node.attr("val"))
    case "schemeClr":
        base = theme.color(node.attr("val"))
    case "sysClr":
        base = NSColor(hex: node.attr("lastClr")) ?? (node.attr("val") == "window" ? .white : .black)
    case "prstClr":
        base = presetColor(node.attr("val"))
    default:
        base = nil
    }
    guard let base else { return nil }
    return adjusted(base, mods: node)
}

private func adjusted(_ color: NSColor, mods: XMLElement) -> NSColor {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    let source = color.usingColorSpace(.sRGB) ?? color
    source.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
    source.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    var shiftedBrightness = false
    var shiftedRGB = false
    for case let child as XMLElement in mods.children ?? [] {
        guard let amount = child.attr("val").flatMap(Double.init).map({ CGFloat($0 / 100_000) }) else { continue }
        switch child.localName {
        case "lumMod":
            brightness = clamp(brightness * amount)
            shiftedBrightness = true
        case "lumOff":
            brightness = clamp(brightness + amount)
            shiftedBrightness = true
        case "shade":
            red = clamp(red * amount)
            green = clamp(green * amount)
            blue = clamp(blue * amount)
            shiftedRGB = true
        case "tint":
            red = clamp(red * amount + (1 - amount))
            green = clamp(green * amount + (1 - amount))
            blue = clamp(blue * amount + (1 - amount))
            shiftedRGB = true
        case "alpha":
            alpha = clamp(amount)
            shiftedRGB = true
        default:
            break
        }
    }
    if shiftedBrightness && !shiftedRGB {
        return NSColor(hue: hue, saturation: saturation, brightness: clamp(brightness), alpha: alpha)
    }
    return NSColor(srgbRed: clamp(red), green: clamp(green), blue: clamp(blue), alpha: clamp(alpha))
}

private func presetColor(_ name: String?) -> NSColor? {
    switch name {
    case "black": NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    case "white": NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    case "red": NSColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)
    case "green": NSColor(srgbRed: 0.1, green: 0.6, blue: 0.2, alpha: 1)
    case "blue": NSColor(srgbRed: 0.1, green: 0.3, blue: 0.85, alpha: 1)
    case "yellow": NSColor(srgbRed: 0.95, green: 0.8, blue: 0.1, alpha: 1)
    case "orange": NSColor(srgbRed: 0.95, green: 0.42, blue: 0.11, alpha: 1)
    case "gray", "grey", "ltGray", "dkGray": NSColor(srgbRed: 0.55, green: 0.55, blue: 0.55, alpha: 1)
    default: nil
    }
}

private func cornerFraction(_ geometry: XMLElement?) -> CGFloat {
    let formula = geometry?.deep("gd")?.attr("fmla") ?? ""
    let raw = formula.split(separator: " ").last.flatMap { Double($0) } ?? 16_667
    return min(max(CGFloat(raw / 100_000), 0), 0.5)
}

private func pdfColor(_ color: NSColor) -> CGColor {
    (color.usingColorSpace(.sRGB) ?? color).cgColor
}

private func clamp(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }

private extension XMLElement {
    func kids(_ local: String) -> [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == local }
    }

    func kid(_ local: String) -> XMLElement? { kids(local).first }

    func deep(_ local: String) -> XMLElement? {
        if localName == local { return self }
        for child in (children ?? []).compactMap({ $0 as? XMLElement }) {
            if let found = child.deep(local) { return found }
        }
        return nil
    }

    func attr(_ name: String) -> String? { attribute(forName: name)?.stringValue }

    func emu(_ name: String) -> CGFloat { optionalEmu(name) ?? 0 }

    func optionalEmu(_ name: String) -> CGFloat? {
        guard let raw = attr(name), let value = Double(raw) else { return nil }
        return CGFloat(value)
    }

    func point(_ name: String) -> CGPoint {
        guard let node = kid(name) else { return .zero }
        if name == "ext" || name == "chExt" { return CGPoint(x: node.emu("cx"), y: node.emu("cy")) }
        return CGPoint(x: node.emu("x"), y: node.emu("y"))
    }

    func xfrm() -> XMLElement? {
        if let direct = kid("xfrm") { return direct }
        return kid("spPr")?.kid("xfrm") ?? kid("grpSpPr")?.kid("xfrm")
    }

    func drawables() -> [XMLElement] {
        var output: [XMLElement] = []
        for case let child as XMLElement in children ?? [] {
            switch child.localName {
            case "AlternateContent":
                let host = child.kid("Fallback") ?? child.kid("Choice")
                if let host { output += host.drawables() }
            case "sp", "pic", "grpSp", "graphicFrame":
                output.append(child)
            default:
                break
            }
        }
        return output
    }

    func shapes() -> [XMLElement] {
        drawables().flatMap { node -> [XMLElement] in
            if node.localName == "grpSp" { return node.shapes() }
            return node.localName == "sp" ? [node] : []
        }
    }
}

private extension NSColor {
    convenience init?(hex: String?) {
        guard var hex, !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
