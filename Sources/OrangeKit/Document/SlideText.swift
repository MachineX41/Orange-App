import AppKit
import CoreText
import Foundation

// MARK: Style model

enum TextSpacing {
    case percent(CGFloat)
    case points(CGFloat)

    init?(_ node: XMLElement?) {
        guard let node else { return nil }
        if let pct = node.kid("spcPct") {
            self = .percent(pct.number("val") / 100_000)
        } else if let pts = node.kid("spcPts") {
            self = .points(pts.number("val") / 100)
        } else {
            return nil
        }
    }
}

enum BulletKind {
    case none
    case character(String)
    case number(scheme: String, start: Int)
}

struct RunStyle {
    var size: CGFloat?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var strike: Bool?
    var baseline: CGFloat?
    var caps: String?
    var spacing: CGFloat?
    var font: String?
    var symbolFont: String?
    var color: NSColor?
    var highlight: NSColor?
    var link: URL?

    mutating func apply(_ node: XMLElement?, palette: DrawingPalette) {
        guard let node else { return }
        if let value = node.optionalNumber("sz") { size = min(max(value / 100, 1), 400) }
        if let value = node.flag("b") { bold = value }
        if let value = node.flag("i") { italic = value }
        if let value = node.attr("u") { underline = value != "none" }
        if let value = node.attr("strike") { strike = value != "noStrike" }
        if let value = node.optionalNumber("baseline") { baseline = value / 100_000 }
        if let value = node.attr("cap") { caps = value }
        if let value = node.optionalNumber("spc") { spacing = value / 100 }
        if let face = node.kid("latin")?.attr("typeface") ?? node.kid("ea")?.attr("typeface") ?? node.kid("cs")?.attr("typeface"),
           let resolved = palette.theme.font(face) {
            font = resolved
        }
        if let face = node.kid("sym")?.attr("typeface") { symbolFont = palette.theme.font(face) }
        if let fill = node.kid("solidFill"), let resolved = palette.color(in: fill) {
            color = resolved
        } else if let gradient = node.kid("gradFill"), let stop = gradient.kid("gsLst")?.kids("gs").first,
                  let resolved = palette.color(in: stop) {
            color = resolved
        } else if node.kid("noFill") != nil {
            color = .clear
        }
        if let mark = node.kid("highlight"), let resolved = palette.color(in: mark) { highlight = resolved }
    }
}

struct ParagraphStyle {
    var marginLeft: CGFloat?
    var indent: CGFloat?
    var align: String?
    var lineSpacing: TextSpacing?
    var spaceBefore: TextSpacing?
    var spaceAfter: TextSpacing?
    var bullet: BulletKind?
    var bulletFont: String?
    var bulletFollowsFont = true
    var bulletColor: NSColor?
    var bulletFollowsColor = true
    var bulletScale: CGFloat?
    var bulletPoints: CGFloat?
    var defaultTab: CGFloat?
    var tabs: [(position: CGFloat, align: String)]?
    var run = RunStyle()

    mutating func apply(_ node: XMLElement?, palette: DrawingPalette) {
        guard let node else { return }
        if let value = node.optionalNumber("defTabSz"), value > 0 { defaultTab = value / 12_700 }
        if let list = node.kid("tabLst") {
            tabs = list.kids("tab").map { ($0.number("pos") / 12_700, $0.attr("algn") ?? "l") }
        }
        if let value = node.optionalNumber("marL") { marginLeft = value / 12_700 }
        if let value = node.optionalNumber("indent") { indent = value / 12_700 }
        if let value = node.attr("algn") { align = value }
        if let value = TextSpacing(node.kid("lnSpc")) { lineSpacing = value }
        if let value = TextSpacing(node.kid("spcBef")) { spaceBefore = value }
        if let value = TextSpacing(node.kid("spcAft")) { spaceAfter = value }
        if node.kid("buNone") != nil { bullet = BulletKind.none }
        if let char = node.kid("buChar")?.attr("char") { bullet = .character(char) }
        if let number = node.kid("buAutoNum") {
            bullet = .number(scheme: number.attr("type") ?? "arabicPeriod", start: Int(number.attr("startAt") ?? "") ?? 1)
        }
        if node.kid("buFontTx") != nil { bulletFollowsFont = true; bulletFont = nil }
        if let face = node.kid("buFont")?.attr("typeface") { bulletFont = palette.theme.font(face); bulletFollowsFont = false }
        if node.kid("buClrTx") != nil { bulletFollowsColor = true; bulletColor = nil }
        if let color = palette.color(in: node.kid("buClr")) { bulletColor = color; bulletFollowsColor = false }
        if node.kid("buSzTx") != nil { bulletScale = nil; bulletPoints = nil }
        if let pct = node.kid("buSzPct") { bulletScale = pct.number("val") / 100_000; bulletPoints = nil }
        if let pts = node.kid("buSzPts") { bulletPoints = pts.number("val") / 100; bulletScale = nil }
        run.apply(node.kid("defRPr"), palette: palette)
    }
}

/// Nine outline levels of paragraph defaults, built up through the master, layout and shape.
struct TextStyleChain {
    var levels = Array(repeating: ParagraphStyle(), count: 9)

    mutating func apply(_ list: XMLElement?, palette: DrawingPalette) {
        guard let list else { return }
        if let all = list.kid("defPPr") {
            for index in levels.indices { levels[index].apply(all, palette: palette) }
        }
        for index in levels.indices {
            levels[index].apply(list.kid("lvl\(index + 1)pPr"), palette: palette)
        }
    }

    mutating func setColor(_ color: NSColor?) {
        guard let color else { return }
        for index in levels.indices { levels[index].run.color = color }
    }

    mutating func setFont(_ font: String?) {
        guard let font else { return }
        for index in levels.indices { levels[index].run.font = font }
    }

    func style(_ level: Int) -> ParagraphStyle { levels[min(max(level, 0), 8)] }
}

enum TextAutofit {
    case none
    case shrink(scale: CGFloat?, reduction: CGFloat)
    case grow
}

struct TextBody {
    var insets = NSEdgeInsets(top: 3.6, left: 7.2, bottom: 3.6, right: 7.2)
    var anchor = "t"
    var anchorCenter = false
    var wrap = true
    var vertical = "horz"
    var autofit = TextAutofit.none
    var columns = 1
    var upright = false

    mutating func apply(_ node: XMLElement?) {
        guard let node else { return }
        if let value = node.optionalNumber("lIns") { insets.left = value / 12_700 }
        if let value = node.optionalNumber("rIns") { insets.right = value / 12_700 }
        if let value = node.optionalNumber("tIns") { insets.top = value / 12_700 }
        if let value = node.optionalNumber("bIns") { insets.bottom = value / 12_700 }
        if let value = node.attr("anchor") { anchor = value }
        if let value = node.flag("anchorCtr") { anchorCenter = value }
        if let value = node.attr("wrap") { wrap = value != "none" }
        if let value = node.attr("vert") { vertical = value }
        if let value = node.flag("upright") { upright = value }
        if let value = node.optionalNumber("numCol") { columns = max(Int(value), 1) }
        if node.kid("noAutofit") != nil { autofit = .none }
        if node.kid("spAutoFit") != nil { autofit = .grow }
        if let fit = node.kid("normAutofit") {
            autofit = .shrink(
                scale: fit.optionalNumber("fontScale").map { $0 / 100_000 },
                reduction: fit.number("lnSpcReduction") / 100_000
            )
        }
    }
}

// MARK: Content

struct TextRun {
    var text: String
    var style: RunStyle
}

struct TextParagraph {
    var style: ParagraphStyle
    var level: Int
    var runs: [TextRun]
    var endStyle: RunStyle
}

enum TextContent {
    /// Reads paragraphs from `txBody`, resolving every run against the style chain.
    static func paragraphs(
        _ body: XMLElement,
        chain: TextStyleChain,
        palette: DrawingPalette,
        slideNumber: Int,
        link: (String?) -> URL?
    ) -> [TextParagraph] {
        var output: [TextParagraph] = []
        for paragraph in body.kids("p") {
            let properties = paragraph.kid("pPr")
            let level = Int(properties?.attr("lvl") ?? "") ?? 0
            var style = chain.style(level)
            style.apply(properties, palette: palette)
            var runs: [TextRun] = []
            func collect(_ node: XMLElement) {
                for child in node.elements {
                    switch child.localName {
                    case "r", "fld":
                        var runStyle = style.run
                        let props = child.kid("rPr")
                        runStyle.apply(props, palette: palette)
                        if let click = props?.kid("hlinkClick"), let url = link(click.relAttr("id")) {
                            runStyle.link = url
                            if props?.kid("solidFill") == nil, let color = palette.scheme("hlink") { runStyle.color = color }
                            if runStyle.underline == nil { runStyle.underline = true }
                        }
                        var text = child.kids("t").compactMap(\.stringValue).joined()
                        if child.localName == "fld", child.attr("type") == "slidenum" { text = String(slideNumber) }
                        if !text.isEmpty { runs.append(TextRun(text: text, style: runStyle)) }
                    case "br":
                        var runStyle = style.run
                        runStyle.apply(child.kid("rPr"), palette: palette)
                        runs.append(TextRun(text: "\u{2028}", style: runStyle))
                    case "AlternateContent":
                        if let branch = child.kid("Fallback") ?? child.kids("Choice").last { collect(branch) }
                    default:
                        break
                    }
                }
            }
            collect(paragraph)
            var endStyle = style.run
            endStyle.apply(paragraph.kid("endParaRPr"), palette: palette)
            output.append(TextParagraph(style: style, level: level, runs: runs, endStyle: endStyle))
        }
        while let last = output.last, last.runs.isEmpty, output.count > 1 {
            output.removeLast()
        }
        return output
    }

    static func plainText(_ paragraphs: [TextParagraph]) -> String {
        paragraphs.map { $0.runs.map(\.text).joined().replacingOccurrences(of: "\u{2028}", with: "\n") }.joined(separator: "\n")
    }
}

// MARK: Layout

private let underlineKey = NSAttributedString.Key("OrangeUnderline")
private let strikeKey = NSAttributedString.Key("OrangeStrike")
private let highlightKey = NSAttributedString.Key("OrangeHighlight")
private let linkKey = NSAttributedString.Key("OrangeLink")
private let colorKey = NSAttributedString.Key("OrangeColor")

struct LaidOutLine {
    var line: CTLine
    var x: CGFloat
    var baseline: CGFloat
    var bullet: CTLine?
    var bulletX: CGFloat
}

struct TextLayout {
    var lines: [LaidOutLine] = []
    var height: CGFloat = 0
    var width: CGFloat = 0
}

enum TextLayoutEngine {
    static func layout(
        _ paragraphs: [TextParagraph],
        width: CGFloat,
        wrap: Bool,
        fontScale: CGFloat,
        spacingReduction: CGFloat,
        defaultColor: NSColor
    ) -> TextLayout {
        var result = TextLayout()
        var y: CGFloat = 0
        var counters: [Int: (scheme: String, value: Int)] = [:]
        let available = wrap ? max(width, 1) : 100_000

        for (index, paragraph) in paragraphs.enumerated() {
            let style = paragraph.style
            let hasText = paragraph.runs.contains { !$0.text.isEmpty }
            let endSize = (paragraph.endStyle.size ?? 18) * fontScale
            let firstSize = (paragraph.runs.first?.style.size ?? paragraph.endStyle.size ?? 18) * fontScale
            let maxSize = paragraph.runs.map { ($0.style.size ?? 18) * fontScale }.max() ?? endSize

            if let before = style.spaceBefore, index > 0 {
                y += spacing(before, size: maxSize, scale: fontScale)
            }

            // Bullets and numbering.
            for key in counters.keys where key > paragraph.level { counters[key] = nil }
            var bulletText: String?
            if hasText {
                switch style.bullet {
                case .character(let char)?:
                    let face = style.bulletFollowsFont ? (paragraph.runs.first?.style.font ?? "") : (style.bulletFont ?? "")
                    bulletText = MetafileText.map(char, face: face, charset: 0)
                case .number(let scheme, let start)?:
                    var counter = counters[paragraph.level]
                    if counter == nil || counter!.scheme != scheme { counter = (scheme, start) } else { counter!.value += 1 }
                    counters[paragraph.level] = counter
                    bulletText = numberLabel(counter!.value, scheme: scheme)
                default:
                    counters[paragraph.level] = nil
                }
            } else {
                counters[paragraph.level] = nil
            }

            let marginLeft = style.marginLeft ?? 0
            let indent = style.indent ?? 0
            var bulletLine: CTLine?
            var bulletWidth: CGFloat = 0
            if let bulletText, !bulletText.isEmpty {
                let first = paragraph.runs.first?.style ?? paragraph.endStyle
                var bulletStyle = first
                bulletStyle.underline = false
                bulletStyle.strike = false
                bulletStyle.link = nil
                bulletStyle.highlight = nil
                if !style.bulletFollowsFont, let face = style.bulletFont, !MetafileText.isSymbolFace(face) { bulletStyle.font = face }
                if !style.bulletFollowsColor, let color = style.bulletColor { bulletStyle.color = color }
                let baseSize = first.size ?? 18
                if let points = style.bulletPoints { bulletStyle.size = points } else if let scale = style.bulletScale { bulletStyle.size = baseSize * scale }
                let string = attributed([TextRun(text: bulletText, style: bulletStyle)], scale: fontScale, defaultColor: defaultColor)
                let line = CTLineCreateWithAttributedString(string)
                bulletLine = line
                bulletWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            }

            let bulletX = marginLeft + indent
            var firstX = marginLeft + indent
            if bulletLine != nil {
                firstX = indent < 0 ? max(marginLeft, bulletX + bulletWidth + 2) : bulletX + bulletWidth + max(firstSize * 0.3, 4)
            }

            let lineFactor: CGFloat
            var exactLine: CGFloat?
            switch style.lineSpacing {
            case .percent(let pct)?: lineFactor = max(pct - spacingReduction, 0.3)
            case .points(let pts)?: lineFactor = 1; exactLine = pts * fontScale
            case nil: lineFactor = max(1 - spacingReduction, 0.3)
            }

            if !hasText {
                let height = exactLine ?? endSize * 1.2 * lineFactor
                y += height
            } else {
                let string = NSMutableAttributedString(attributedString: attributed(paragraph.runs, scale: fontScale, defaultColor: defaultColor))
                if string.string.contains("\t") {
                    string.addAttribute(
                        NSAttributedString.Key(kCTParagraphStyleAttributeName as String),
                        value: tabStyle(style, origin: marginLeft),
                        range: NSRange(location: 0, length: string.length)
                    )
                }
                let typesetter = CTTypesetterCreateWithAttributedString(string)
                var start = 0
                var firstLine = true
                let length = string.length
                while start < length {
                    let x = firstLine ? firstX : marginLeft
                    let room = max(available - x, 4)
                    var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(room))
                    if count <= 0 { count = 1 }
                    let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                    let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
                    let trailing = CGFloat(CTLineGetTrailingWhitespaceWidth(line))
                    let size = lineFontSize(string, range: NSRange(location: start, length: count)) ?? maxSize
                    let natural = size * 1.2
                    let height = exactLine ?? natural * lineFactor
                    let ascentShare = ascent + descent > 0 ? ascent / (ascent + descent) : 0.8
                    let baseline = y + height - natural * (1 - ascentShare) * min(lineFactor, 1)
                    let visible = lineWidth - trailing
                    var drawX = x
                    let lineRoom = max(width, 1) - x
                    switch style.align {
                    case "ctr"?: drawX = x + (lineRoom - visible) / 2
                    case "r"?: drawX = x + lineRoom - visible
                    default: break
                    }
                    var placed = line
                    if style.align == "just" || style.align == "dist", wrap, start + count < length,
                       let justified = CTLineCreateJustifiedLine(line, 1, Double(lineRoom)) {
                        placed = justified
                    }
                    result.lines.append(LaidOutLine(
                        line: placed,
                        x: drawX,
                        baseline: baseline,
                        bullet: firstLine ? bulletLine : nil,
                        bulletX: bulletX
                    ))
                    result.width = max(result.width, drawX + visible)
                    y += height
                    start += count
                    firstLine = false
                }
            }

            if let after = style.spaceAfter {
                y += spacing(after, size: maxSize, scale: fontScale)
            }
        }
        result.height = y
        return result
    }

    /// Tab stops are measured from the text box edge, while lines start at the left margin.
    static func tabStyle(_ style: ParagraphStyle, origin: CGFloat) -> CTParagraphStyle {
        var interval = style.defaultTab ?? 72
        let stops: [CTTextTab] = (style.tabs ?? []).compactMap { tab in
            let location = tab.position - origin
            guard location > 0 else { return nil }
            let alignment: CTTextAlignment = tab.align == "r" ? .right : tab.align == "ctr" ? .center : .left
            return CTTextTabCreate(alignment, Double(location), nil)
        }
        var array = stops as CFArray
        return withUnsafeMutablePointer(to: &interval) { intervalPointer in
            withUnsafeMutablePointer(to: &array) { arrayPointer in
                let settings = [
                    CTParagraphStyleSetting(spec: .defaultTabInterval, valueSize: MemoryLayout<CGFloat>.size, value: intervalPointer),
                    CTParagraphStyleSetting(spec: .tabStops, valueSize: MemoryLayout<CFArray>.size, value: arrayPointer)
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
    }

    static func spacing(_ value: TextSpacing, size: CGFloat, scale: CGFloat) -> CGFloat {
        switch value {
        case .percent(let pct): return pct * size * 1.2
        case .points(let pts): return pts * scale
        }
    }

    static func lineFontSize(_ string: NSAttributedString, range: NSRange) -> CGFloat? {
        var size: CGFloat?
        string.enumerateAttribute(.font, in: range) { value, _, _ in
            guard let value else { return }
            let font = value as! CTFont
            size = max(size ?? 0, CTFontGetSize(font))
        }
        return size
    }

    static func numberLabel(_ value: Int, scheme: String) -> String {
        let body: String
        if scheme.hasPrefix("alphaLc") {
            body = alpha(value).lowercased()
        } else if scheme.hasPrefix("alphaUc") {
            body = alpha(value)
        } else if scheme.hasPrefix("romanLc") {
            body = roman(value).lowercased()
        } else if scheme.hasPrefix("romanUc") {
            body = roman(value)
        } else {
            body = String(value)
        }
        if scheme.hasSuffix("ParenBoth") { return "(\(body))" }
        if scheme.hasSuffix("ParenR") { return "\(body))" }
        if scheme.hasSuffix("Plain") { return body }
        return "\(body)."
    }

    static func alpha(_ value: Int) -> String {
        var n = max(value, 1)
        var output = ""
        while n > 0 {
            n -= 1
            output = String(UnicodeScalar(UInt8(65 + n % 26))) + output
            n /= 26
        }
        return output
    }

    static func roman(_ value: Int) -> String {
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = max(value, 1)
        var output = ""
        for (amount, letters) in table {
            while n >= amount { output += letters; n -= amount }
        }
        return output
    }

    /// Narrows stand-in fonts so lines break where they would with the Office font.
    static func substituteWidth(requested: String, resolved: String) -> CGFloat? {
        let wanted = requested.lowercased()
        guard wanted != resolved.lowercased() else { return nil }
        let factors: [String: CGFloat] = [
            "calibri": 0.9, "calibri light": 0.88, "aptos": 0.95, "aptos display": 0.93, "segoe ui": 0.97,
            "cambria": 0.93, "candara": 0.93, "corbel": 0.92, "consolas": 0.92, "gill sans mt": 0.95,
            "franklin gothic book": 0.95, "century gothic": 1.0, "tw cen mt": 0.85
        ]
        return factors[wanted]
    }

    static func attributed(_ runs: [TextRun], scale: CGFloat, defaultColor: NSColor) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for run in runs {
            let style = run.style
            var size = (style.size ?? 18) * scale
            var text = run.text
            if style.caps == "all" { text = text.uppercased() }
            if style.caps == "small" { text = text.uppercased(); size *= 0.8 }
            let baseline = style.baseline ?? 0
            if baseline != 0 { size *= 0.66 }
            let symbolic = style.font.map(MetafileText.isSymbolFace) ?? false
            if symbolic, let face = style.font { text = MetafileText.map(text, face: face, charset: 0) }
            let family = symbolic ? nil : style.font
            var font = FontResolver.font(family: family, size: max(size, 0.5), bold: style.bold ?? false, italic: style.italic ?? false) as CTFont
            if let family, let factor = substituteWidth(requested: family, resolved: CTFontCopyFamilyName(font) as String) {
                var matrix = CGAffineTransform(scaleX: factor, y: 1)
                font = CTFontCreateCopyWithAttributes(font, max(size, 0.5), &matrix, nil)
            }
            let color = style.color ?? defaultColor
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.srgbCG,
                colorKey: color
            ]
            if baseline != 0 {
                // Text is drawn with a flipped text matrix, so CoreText’s upward offset points down.
                attributes[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] = -baseline * (style.size ?? 18) * scale
            }
            if let spacing = style.spacing, spacing != 0 {
                attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = spacing * scale
            }
            if style.underline == true { attributes[underlineKey] = true }
            if style.strike == true { attributes[strikeKey] = true }
            if let highlight = style.highlight { attributes[highlightKey] = highlight }
            if let link = style.link { attributes[linkKey] = link }
            output.append(NSAttributedString(string: text, attributes: attributes))
        }
        return output
    }
}

// MARK: Drawing

struct TextLinkArea {
    var rect: CGRect
    var url: URL
}

enum TextPainter {
    /// Draws laid-out lines in a y-down context with `origin` as the top-left of the text.
    static func draw(_ layout: TextLayout, at origin: CGPoint, in context: CGContext, links: inout [TextLinkArea]) {
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for item in layout.lines {
            let baseline = origin.y + item.baseline
            if let bullet = item.bullet {
                context.textPosition = CGPoint(x: origin.x + item.bulletX, y: baseline)
                CTLineDraw(bullet, context)
            }
            let x = origin.x + item.x
            decorate(item.line, x: x, baseline: baseline, context: context, background: true, links: &links)
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(item.line, context)
            decorate(item.line, x: x, baseline: baseline, context: context, background: false, links: &links)
        }
        context.restoreGState()
    }

    private static func decorate(_ line: CTLine, x: CGFloat, baseline: CGFloat, context: CGContext, background: Bool, links: inout [TextLinkArea]) {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return }
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary as? [NSAttributedString.Key: Any] ?? [:]
            let underline = attributes[underlineKey] != nil
            let strike = attributes[strikeKey] != nil
            let highlight = attributes[highlightKey] as? NSColor
            let link = attributes[linkKey] as? URL
            guard underline || strike || highlight != nil || link != nil else { continue }
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil))
            let range = CTRunGetStringRange(run)
            let start = x + CTLineGetOffsetForStringIndex(line, range.location, nil)
            let font = attributes[.font].map { $0 as! CTFont }
            let size = font.map { CTFontGetSize($0) } ?? 12
            let color = (attributes[colorKey] as? NSColor) ?? .black
            if background {
                if let highlight {
                    context.setFillColor(highlight.srgbCG)
                    context.fill(CGRect(x: start, y: baseline - ascent, width: width, height: ascent + descent))
                }
                if let link {
                    links.append(TextLinkArea(rect: CGRect(x: start, y: baseline - ascent, width: width, height: ascent + descent), url: link))
                }
                continue
            }
            context.setFillColor(color.srgbCG)
            let thickness = max(size * 0.06, 0.5)
            if underline {
                let offset = font.map { -CTFontGetUnderlinePosition($0) } ?? size * 0.1
                context.fill(CGRect(x: start, y: baseline + max(offset, size * 0.08), width: width, height: thickness))
            }
            if strike {
                context.fill(CGRect(x: start, y: baseline - size * 0.3, width: width, height: thickness))
            }
        }
    }
}
