import AppKit
import Foundation

/// Shared reading of Office Open XML packages: parts, relationships, themes and DrawingML colors.
struct OOXMLRelationship {
    var type: String
    var target: String
    var external: Bool
}

final class OOXMLPackage {
    let root: URL
    private var xmlCache: [URL: XMLElement] = [:]
    private var missing: Set<URL> = []
    private var relCache: [URL: [String: OOXMLRelationship]] = [:]

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func xml(_ url: URL) -> XMLElement? {
        if let cached = xmlCache[url] { return cached }
        if missing.contains(url) { return nil }
        guard let document = try? XMLDocument(contentsOf: url, options: [.nodePreserveWhitespace]),
              let element = document.rootElement() else {
            missing.insert(url)
            return nil
        }
        xmlCache[url] = element
        return element
    }

    func relationships(for part: URL) -> [String: OOXMLRelationship] {
        if let cached = relCache[part] { return cached }
        let url = part.deletingLastPathComponent()
            .appendingPathComponent("_rels")
            .appendingPathComponent(part.lastPathComponent + ".rels")
        var map: [String: OOXMLRelationship] = [:]
        for node in xml(url)?.kids("Relationship") ?? [] {
            guard let id = node.attr("Id"), let target = node.attr("Target") else { continue }
            map[id] = OOXMLRelationship(
                type: node.attr("Type") ?? "",
                target: target,
                external: node.attr("TargetMode")?.lowercased() == "external"
            )
        }
        relCache[part] = map
        return map
    }

    func target(_ id: String?, from part: URL) -> URL? {
        guard let id, let relation = relationships(for: part)[id], !relation.external else { return nil }
        return resolve(relation.target, from: part)
    }

    func externalLink(_ id: String?, from part: URL) -> URL? {
        guard let id, let relation = relationships(for: part)[id] else { return nil }
        guard relation.external, let url = URL(string: relation.target), let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return nil }
        return url
    }

    func related(_ part: URL, type suffix: String) -> URL? {
        let matches = relationships(for: part).filter { !$0.value.external && $0.value.type.hasSuffix("/" + suffix) }
        guard let first = matches.sorted(by: { $0.key < $1.key }).first else { return nil }
        return resolve(first.value.target, from: part)
    }

    /// Keeps every resolved part inside the unpacked package.
    func resolve(_ target: String, from part: URL) -> URL? {
        let cleaned = (target.removingPercentEncoding ?? target).replacingOccurrences(of: "\\", with: "/")
        guard !cleaned.isEmpty, !cleaned.contains("://") else { return nil }
        let url = cleaned.hasPrefix("/")
            ? root.appendingPathComponent(String(cleaned.dropFirst()))
            : part.deletingLastPathComponent().appendingPathComponent(cleaned)
        let standard = url.standardizedFileURL
        let path = standard.path
        guard path == root.path || path.hasPrefix(root.path + "/") else { return nil }
        return standard
    }
}

// MARK: Theme and colors

struct DrawingTheme {
    var colors: [String: NSColor] = [
        "dk1": NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
        "lt1": NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        "dk2": NSColor(srgbRed: 0.27, green: 0.33, blue: 0.42, alpha: 1),
        "lt2": NSColor(srgbRed: 0.91, green: 0.91, blue: 0.91, alpha: 1),
        "accent1": NSColor(srgbRed: 0.27, green: 0.45, blue: 0.77, alpha: 1),
        "accent2": NSColor(srgbRed: 0.93, green: 0.49, blue: 0.19, alpha: 1),
        "accent3": NSColor(srgbRed: 0.65, green: 0.65, blue: 0.65, alpha: 1),
        "accent4": NSColor(srgbRed: 1.0, green: 0.75, blue: 0.0, alpha: 1),
        "accent5": NSColor(srgbRed: 0.36, green: 0.61, blue: 0.84, alpha: 1),
        "accent6": NSColor(srgbRed: 0.44, green: 0.68, blue: 0.28, alpha: 1),
        "hlink": NSColor(srgbRed: 0.02, green: 0.39, blue: 0.76, alpha: 1),
        "folHlink": NSColor(srgbRed: 0.58, green: 0.27, blue: 0.53, alpha: 1)
    ]
    var majorFont = ""
    var minorFont = ""
    var fillStyles: [XMLElement] = []
    var lineStyles: [XMLElement] = []
    var effectStyles: [XMLElement] = []
    var backgroundFills: [XMLElement] = []

    static func load(_ root: XMLElement?) -> DrawingTheme {
        var theme = DrawingTheme()
        guard let root else { return theme }
        if let scheme = root.deep("clrScheme") {
            let palette = DrawingPalette(theme: theme)
            for child in scheme.elements {
                guard let name = child.localName, let color = palette.color(in: child) else { continue }
                theme.colors[name] = color
            }
        }
        if let fonts = root.deep("fontScheme") {
            theme.majorFont = fonts.kid("majorFont")?.kid("latin")?.attr("typeface") ?? ""
            theme.minorFont = fonts.kid("minorFont")?.kid("latin")?.attr("typeface") ?? ""
        }
        if let format = root.deep("fmtScheme") {
            theme.fillStyles = format.kid("fillStyleLst")?.elements ?? []
            theme.lineStyles = format.kid("lnStyleLst")?.elements ?? []
            theme.effectStyles = format.kid("effectStyleLst")?.elements ?? []
            theme.backgroundFills = format.kid("bgFillStyleLst")?.elements ?? []
        }
        return theme
    }

    func font(_ typeface: String?) -> String? {
        guard let typeface, !typeface.isEmpty else { return nil }
        switch typeface {
        case "+mj-lt", "+mj-ea", "+mj-cs": return majorFont.isEmpty ? nil : majorFont
        case "+mn-lt", "+mn-ea", "+mn-cs": return minorFont.isEmpty ? nil : minorFont
        default: return typeface
        }
    }
}

/// Resolves DrawingML colors through the theme, the slide’s color map and an optional placeholder color.
struct DrawingPalette {
    var theme: DrawingTheme
    var map: [String: String] = ["bg1": "lt1", "tx1": "dk1", "bg2": "lt2", "tx2": "dk2"]
    var placeholder: NSColor?

    func with(placeholder color: NSColor?) -> DrawingPalette {
        var copy = self
        copy.placeholder = color
        return copy
    }

    func scheme(_ name: String?) -> NSColor? {
        guard let name else { return nil }
        if name == "phClr" { return placeholder ?? theme.colors["dk1"] }
        let key = map[name] ?? name
        return theme.colors[key] ?? theme.colors[name]
    }

    var text: NSColor { scheme("tx1") ?? .black }

    /// Reads the color held by `element`, or by its first color child.
    func color(in element: XMLElement?) -> NSColor? {
        guard let element else { return nil }
        let names: Set<String> = ["srgbClr", "schemeClr", "sysClr", "prstClr", "scrgbClr", "hslClr"]
        let node = names.contains(element.localName ?? "") ? element : element.elements.first { names.contains($0.localName ?? "") }
        guard let node else { return nil }
        let base: NSColor?
        switch node.localName {
        case "srgbClr": base = NSColor(ooxmlHex: node.attr("val"))
        case "schemeClr": base = scheme(node.attr("val"))
        case "sysClr": base = NSColor(ooxmlHex: node.attr("lastClr")) ?? systemColor(node.attr("val"))
        case "prstClr": base = presetColor(node.attr("val"))
        case "scrgbClr":
            base = NSColor(
                srgbRed: linearToSRGB(node.number("r") / 100_000),
                green: linearToSRGB(node.number("g") / 100_000),
                blue: linearToSRGB(node.number("b") / 100_000),
                alpha: 1
            )
        case "hslClr":
            let rgb = hslToRGB(node.number("hue") / 21_600_000, node.number("sat") / 100_000, node.number("lum") / 100_000)
            base = NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        default: base = nil
        }
        guard let base else { return nil }
        return applyModifiers(base, node)
    }

    func applyModifiers(_ color: NSColor, _ node: XMLElement) -> NSColor {
        let source = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        var r = source.redComponent, g = source.greenComponent, b = source.blueComponent, a = source.alphaComponent
        for mod in node.elements {
            let value = mod.number("val") / 100_000
            switch mod.localName {
            case "lumMod", "lumOff", "satMod", "satOff", "hueMod", "hueOff":
                var (h, s, l) = rgbToHSL(r, g, b)
                switch mod.localName {
                case "lumMod": l *= value
                case "lumOff": l += value
                case "satMod": s *= value
                case "satOff": s += value
                case "hueMod": h = (h * value).truncatingRemainder(dividingBy: 1)
                default: h = (h + mod.number("val") / 21_600_000).truncatingRemainder(dividingBy: 1)
                }
                (r, g, b) = hslToRGB(h < 0 ? h + 1 : h, clamp01(s), clamp01(l))
            case "tint":
                r = linearToSRGB(1 - (1 - srgbToLinear(r)) * value)
                g = linearToSRGB(1 - (1 - srgbToLinear(g)) * value)
                b = linearToSRGB(1 - (1 - srgbToLinear(b)) * value)
            case "shade":
                r = linearToSRGB(srgbToLinear(r) * value)
                g = linearToSRGB(srgbToLinear(g) * value)
                b = linearToSRGB(srgbToLinear(b) * value)
            case "alpha": a = value
            case "alphaMod": a *= value
            case "alphaOff": a += value
            case "comp":
                var (h, s, l) = rgbToHSL(r, g, b)
                h = (h + 0.5).truncatingRemainder(dividingBy: 1)
                (r, g, b) = hslToRGB(h, s, l)
            case "inv": r = 1 - r; g = 1 - g; b = 1 - b
            case "gray":
                let y = 0.299 * r + 0.587 * g + 0.114 * b
                r = y; g = y; b = y
            default: break
            }
        }
        return NSColor(srgbRed: clamp01(r), green: clamp01(g), blue: clamp01(b), alpha: clamp01(a))
    }

    private func systemColor(_ name: String?) -> NSColor {
        switch name {
        case "window", "btnHighlight", "3dLight", "highlightText", "menu", "infoBk":
            return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case "btnFace", "menuBar", "3dFace":
            return NSColor(srgbRed: 0.94, green: 0.94, blue: 0.94, alpha: 1)
        case "grayText", "btnShadow":
            return NSColor(srgbRed: 0.43, green: 0.43, blue: 0.43, alpha: 1)
        case "highlight", "hotLight":
            return NSColor(srgbRed: 0, green: 0.47, blue: 0.84, alpha: 1)
        default:
            return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        }
    }
}

func presetColor(_ name: String?) -> NSColor? {
    let table: [String: UInt32] = [
        "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000, "lime": 0x00FF00,
        "blue": 0x0000FF, "yellow": 0xFFFF00, "orange": 0xFFA500, "purple": 0x800080, "gray": 0x808080,
        "grey": 0x808080, "ltGray": 0xD3D3D3, "dkGray": 0xA9A9A9, "silver": 0xC0C0C0, "navy": 0x000080,
        "teal": 0x008080, "maroon": 0x800000, "olive": 0x808000, "cyan": 0x00FFFF, "aqua": 0x00FFFF,
        "magenta": 0xFF00FF, "fuchsia": 0xFF00FF, "pink": 0xFFC0CB, "brown": 0xA52A2A, "gold": 0xFFD700,
        "darkBlue": 0x00008B, "dkBlue": 0x00008B, "darkRed": 0x8B0000, "dkRed": 0x8B0000,
        "darkGreen": 0x006400, "dkGreen": 0x006400, "lightBlue": 0xADD8E6, "ltBlue": 0xADD8E6,
        "skyBlue": 0x87CEEB, "violet": 0xEE82EE, "indigo": 0x4B0082, "tan": 0xD2B48C, "beige": 0xF5F5DC
    ]
    guard let name, let value = table[name] else { return nil }
    return NSColor(ooxmlRGB: value)
}

func clamp01(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }

func srgbToLinear(_ c: CGFloat) -> CGFloat {
    c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

func linearToSRGB(_ c: CGFloat) -> CGFloat {
    let v = clamp01(c)
    return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
}

func rgbToHSL(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    let maxV = max(r, g, b), minV = min(r, g, b)
    let l = (maxV + minV) / 2
    guard maxV != minV else { return (0, 0, l) }
    let d = maxV - minV
    let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
    var h: CGFloat
    if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) }
    else if maxV == g { h = (b - r) / d + 2 }
    else { h = (r - g) / d + 4 }
    h /= 6
    return (h, s, l)
}

func hslToRGB(_ h: CGFloat, _ s: CGFloat, _ l: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    guard s > 0 else { return (l, l, l) }
    func hue(_ p: CGFloat, _ q: CGFloat, _ t0: CGFloat) -> CGFloat {
        var t = t0
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1 / 6 { return p + (q - p) * 6 * t }
        if t < 1 / 2 { return q }
        if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
        return p
    }
    let q = l < 0.5 ? l * (1 + s) : l + s - l * s
    let p = 2 * l - q
    return (hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3))
}

extension NSColor {
    convenience init?(ooxmlHex: String?) {
        guard var hex = ooxmlHex, !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(ooxmlRGB: value)
    }

    convenience init(ooxmlRGB value: UInt32) {
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var srgbCG: CGColor {
        (usingColorSpace(.sRGB) ?? self).cgColor
    }

    func blended(with other: NSColor, fraction: CGFloat) -> NSColor {
        let a = usingColorSpace(.sRGB) ?? self
        let b = other.usingColorSpace(.sRGB) ?? other
        return NSColor(
            srgbRed: a.redComponent + (b.redComponent - a.redComponent) * fraction,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * fraction,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * fraction,
            alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * fraction
        )
    }
}

// MARK: XML helpers

extension XMLElement {
    var elements: [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }
    }

    func kids(_ local: String) -> [XMLElement] {
        elements.filter { $0.localName == local }
    }

    func kid(_ local: String) -> XMLElement? {
        elements.first { $0.localName == local }
    }

    func path(_ locals: String...) -> XMLElement? {
        var node: XMLElement? = self
        for local in locals { node = node?.kid(local) }
        return node
    }

    func deep(_ local: String) -> XMLElement? {
        if localName == local { return self }
        for child in elements {
            if let found = child.deep(local) { return found }
        }
        return nil
    }

    func deepAll(_ local: String) -> [XMLElement] {
        var output: [XMLElement] = []
        func walk(_ node: XMLElement) {
            if node.localName == local { output.append(node) }
            for child in node.elements { walk(child) }
        }
        walk(self)
        return output
    }

    func attr(_ name: String) -> String? {
        if let direct = attribute(forName: name)?.stringValue { return direct }
        for node in attributes ?? [] where node.localName == name && (node.name?.contains(":") ?? false) == false {
            return node.stringValue
        }
        return nil
    }

    /// Reads an attribute in the relationships namespace such as `r:id` or `r:embed`.
    func relAttr(_ local: String) -> String? {
        for node in attributes ?? [] where node.localName == local {
            let name = node.name ?? ""
            if name.contains(":") || (node.uri ?? "").contains("relationships") { return node.stringValue }
        }
        return nil
    }

    func number(_ name: String) -> CGFloat {
        optionalNumber(name) ?? 0
    }

    func optionalNumber(_ name: String) -> CGFloat? {
        guard let raw = attr(name), let value = Double(raw) else { return nil }
        return CGFloat(value)
    }

    func flag(_ name: String) -> Bool? {
        switch attr(name)?.lowercased() {
        case "1", "true", "on": return true
        case "0", "false", "off": return false
        default: return nil
        }
    }

    /// Expands `mc:AlternateContent` to the branch Orange can draw.
    var drawableChildren: [XMLElement] {
        var output: [XMLElement] = []
        for child in elements {
            if child.localName == "AlternateContent" {
                let branch = child.kid("Fallback") ?? child.kids("Choice").last
                output += branch?.drawableChildren ?? []
            } else {
                output.append(child)
            }
        }
        return output
    }
}
