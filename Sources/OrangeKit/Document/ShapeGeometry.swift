import CoreGraphics
import Foundation

/// One drawable piece of a DrawingML shape, in y-down coordinates.
struct GeometryPart {
    var path: CGPath
    var fill: Bool
    var stroke: Bool
    var open: Bool
    var start: (tip: CGPoint, from: CGPoint)?
    var end: (tip: CGPoint, from: CGPoint)?
    var evenOdd = false
    /// The part of the shape that holds text, when it is narrower than the bounds.
    var textInset: CGFloat = 0
}

enum ShapeGeometry {
    static let lineShapes: Set<String> = [
        "line", "straightConnector1", "bentConnector2", "bentConnector3", "bentConnector4", "bentConnector5",
        "curvedConnector2", "curvedConnector3", "curvedConnector4", "curvedConnector5", "arc",
        "leftBracket", "rightBracket", "leftBrace", "rightBrace", "bracketPair", "bracePair"
    ]

    /// Builds the geometry of `spPr` inside `rect`. `emuSize` is the shape size in EMU for custom guides.
    static func parts(_ spPr: XMLElement?, rect: CGRect, emuSize: CGSize, isConnector: Bool = false) -> [GeometryPart] {
        if let custom = spPr?.kid("custGeom") {
            let built = customParts(custom, rect: rect, emuSize: emuSize)
            if !built.isEmpty { return built }
        }
        let preset = spPr?.kid("prstGeom")
        let name = preset?.attr("prst") ?? (isConnector ? "line" : "rect")
        var adjust: [String: CGFloat] = [:]
        for guide in preset?.kid("avLst")?.kids("gd") ?? [] {
            if let key = guide.attr("name"), let formula = guide.attr("fmla"), formula.hasPrefix("val "),
               let value = Double(formula.dropFirst(4).trimmingCharacters(in: .whitespaces)) {
                adjust[key] = CGFloat(value)
            }
        }
        return [presetPart(name, rect: rect, adjust: adjust)]
    }

    static func presetPart(_ name: String, rect r: CGRect, adjust: [String: CGFloat]) -> GeometryPart {
        let w = r.width, h = r.height, ss = min(w, h)
        func adj(_ key: String, _ fallback: CGFloat) -> CGFloat { (adjust[key] ?? fallback) / 100_000 }
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x, y: r.minY + y) }
        func polygon(_ points: [CGPoint]) -> GeometryPart {
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            return GeometryPart(path: path, fill: true, stroke: true, open: false)
        }
        func open(_ build: (CGMutablePath) -> Void, start: (CGPoint, CGPoint)? = nil, end: (CGPoint, CGPoint)? = nil) -> GeometryPart {
            let path = CGMutablePath()
            build(path)
            return GeometryPart(
                path: path, fill: false, stroke: true, open: true,
                start: start.map { (tip: $0.0, from: $0.1) }, end: end.map { (tip: $0.0, from: $0.1) }
            )
        }

        switch name {
        case "line", "straightConnector1":
            return open({ $0.move(to: p(0, 0)); $0.addLine(to: p(w, h)) }, start: (p(0, 0), p(w, h)), end: (p(w, h), p(0, 0)))
        case "bentConnector2":
            return open({ $0.move(to: p(0, 0)); $0.addLine(to: p(w, 0)); $0.addLine(to: p(w, h)) },
                        start: (p(0, 0), p(w, 0)), end: (p(w, h), p(w, 0)))
        case "bentConnector3", "bentConnector4", "bentConnector5":
            let x = w * adj("adj1", 50_000)
            return open({ $0.move(to: p(0, 0)); $0.addLine(to: p(x, 0)); $0.addLine(to: p(x, h)); $0.addLine(to: p(w, h)) },
                        start: (p(0, 0), p(x, 0)), end: (p(w, h), p(x, h)))
        case "curvedConnector2":
            return open({ $0.move(to: p(0, 0)); $0.addQuadCurve(to: p(w, h), control: p(w, 0)) },
                        start: (p(0, 0), p(w, 0)), end: (p(w, h), p(w, 0)))
        case "curvedConnector3", "curvedConnector4", "curvedConnector5":
            let x = w * adj("adj1", 50_000)
            return open({ $0.move(to: p(0, 0)); $0.addCurve(to: p(w, h), control1: p(x, 0), control2: p(x, h)) },
                        start: (p(0, 0), p(x, 0)), end: (p(w, h), p(x, h)))
        case "arc":
            let a1 = adj("adj1", 1_620_000_000) * 100_000 / 60_000 * .pi / 180
            let a2 = adj("adj2", 0) * 100_000 / 60_000 * .pi / 180
            var sweep = a2 - a1
            if sweep <= 0 { sweep += 2 * .pi }
            return open { path in
                let t = CGAffineTransform(translationX: r.midX, y: r.midY).scaledBy(x: w / 2, y: h / 2)
                path.addRelativeArc(center: .zero, radius: 1, startAngle: a1, delta: sweep, transform: t)
            }
        case "leftBracket", "rightBracket":
            let k = min(h * adj("adj", 8_333), w)
            let left = name == "leftBracket"
            return open { path in
                if left {
                    path.move(to: p(w, 0)); path.addQuadCurve(to: p(0, k), control: p(0, 0))
                    path.addLine(to: p(0, h - k)); path.addQuadCurve(to: p(w, h), control: p(0, h))
                } else {
                    path.move(to: p(0, 0)); path.addQuadCurve(to: p(w, k), control: p(w, 0))
                    path.addLine(to: p(w, h - k)); path.addQuadCurve(to: p(0, h), control: p(w, h))
                }
            }
        case "leftBrace", "rightBrace":
            let left = name == "leftBrace"
            let m = h * adj("adj2", 50_000)
            return open { path in
                let x0: CGFloat = left ? w : 0, x1: CGFloat = w / 2, x2: CGFloat = left ? 0 : w
                path.move(to: p(x0, 0))
                path.addQuadCurve(to: p(x1, h * 0.08), control: p(x1, 0))
                path.addLine(to: p(x1, m - h * 0.08))
                path.addQuadCurve(to: p(x2, m), control: p(x1, m))
                path.addQuadCurve(to: p(x1, m + h * 0.08), control: p(x1, m))
                path.addLine(to: p(x1, h - h * 0.08))
                path.addQuadCurve(to: p(x0, h), control: p(x1, h))
            }
        case "bracketPair", "bracePair":
            let k = ss * 0.16
            return open { path in
                path.move(to: p(k, 0)); path.addQuadCurve(to: p(0, k), control: p(0, 0))
                path.addLine(to: p(0, h - k)); path.addQuadCurve(to: p(k, h), control: p(0, h))
                path.move(to: p(w - k, 0)); path.addQuadCurve(to: p(w, k), control: p(w, 0))
                path.addLine(to: p(w, h - k)); path.addQuadCurve(to: p(w - k, h), control: p(w, h))
            }
        case "ellipse", "flowChartConnector", "circle", "flowChartOr", "flowChartSummingJunction":
            return GeometryPart(path: CGPath(ellipseIn: r, transform: nil), fill: true, stroke: true, open: false, textInset: 0.146)
        case "heart":
            let path = CGMutablePath()
            path.move(to: p(w / 2, h * 0.28))
            path.addCurve(to: p(0, h * 0.28), control1: p(w / 2, h * 0.05), control2: p(0, h * 0.05))
            path.addCurve(to: p(w / 2, h), control1: p(0, h * 0.62), control2: p(w / 2, h * 0.78))
            path.addCurve(to: p(w, h * 0.28), control1: p(w / 2, h * 0.78), control2: p(w, h * 0.62))
            path.addCurve(to: p(w / 2, h * 0.28), control1: p(w, h * 0.05), control2: p(w / 2, h * 0.05))
            path.closeSubpath()
            return GeometryPart(path: path, fill: true, stroke: true, open: false, textInset: 0.18)
        case "teardrop":
            let path = CGMutablePath()
            path.move(to: p(w, 0))
            path.addCurve(to: p(w * 0.15, h * 0.35), control1: p(w, h * 0.35), control2: p(w * 0.55, h * 0.05))
            path.addCurve(to: p(w * 0.5, h), control1: p(w * -0.05, h * 0.65), control2: p(w * 0.15, h))
            path.addCurve(to: p(w * 0.85, h * 0.35), control1: p(w * 0.85, h), control2: p(w * 1.05, h * 0.65))
            path.addCurve(to: p(w, 0), control1: p(w * 0.7, h * 0.1), control2: p(w, h * 0.15))
            path.closeSubpath()
            return GeometryPart(path: path, fill: true, stroke: true, open: false, textInset: 0.16)
        case "moon":
            let path = CGMutablePath()
            path.addEllipse(in: r)
            let inset = ss * adj("adj", 50_000) * 0.55
            path.addEllipse(in: CGRect(x: r.minX + inset, y: r.minY + inset * 0.35, width: w - inset, height: h - inset * 0.7))
            return GeometryPart(path: path, fill: true, stroke: true, open: false, evenOdd: true, textInset: 0.2)
        case "sun":
            let path = CGMutablePath()
            let rays = regular(16, rect: r.insetBy(dx: ss * 0.02, dy: ss * 0.02), inner: 0.55)
            path.addLines(between: rays)
            path.closeSubpath()
            path.addEllipse(in: r.insetBy(dx: ss * 0.28, dy: ss * 0.28))
            return GeometryPart(path: path, fill: true, stroke: true, open: false, evenOdd: true, textInset: 0.32)
        case "cloud", "cloudCallout":
            let path = CGMutablePath()
            let bumps: [(CGFloat, CGFloat, CGFloat)] = [
                (0.22, 0.58, 0.22), (0.42, 0.38, 0.24), (0.66, 0.42, 0.23), (0.84, 0.58, 0.18), (0.55, 0.72, 0.2), (0.32, 0.72, 0.18)
            ]
            for bump in bumps {
                let radius = ss * bump.2
                path.addEllipse(in: CGRect(x: r.minX + w * bump.0 - radius, y: r.minY + h * bump.1 - radius, width: radius * 2, height: radius * 2))
            }
            if name == "cloudCallout" {
                path.move(to: p(w * 0.28, h * 0.78))
                path.addLine(to: p(w * 0.08, h))
                path.addLine(to: p(w * 0.42, h * 0.78))
                path.closeSubpath()
            }
            return GeometryPart(path: path, fill: true, stroke: true, open: false, textInset: 0.18)
        case "wedgeEllipseCallout":
            let path = CGMutablePath()
            path.addEllipse(in: r.insetBy(dx: 0, dy: h * 0.08))
            path.move(to: p(w * 0.35, h * 0.78))
            path.addLine(to: p(w * 0.05, h))
            path.addLine(to: p(w * 0.5, h * 0.78))
            path.closeSubpath()
            return GeometryPart(path: path, fill: true, stroke: true, open: false, textInset: 0.16)
        case "smileyFace":
            let path = CGMutablePath()
            path.addEllipse(in: r)
            let eye = ss * 0.08
            path.addEllipse(in: CGRect(x: r.minX + w * 0.3 - eye, y: r.minY + h * 0.35 - eye, width: eye * 2, height: eye * 2))
            path.addEllipse(in: CGRect(x: r.minX + w * 0.7 - eye, y: r.minY + h * 0.35 - eye, width: eye * 2, height: eye * 2))
            path.move(to: p(w * 0.28, h * 0.62))
            path.addQuadCurve(to: p(w * 0.72, h * 0.62), control: p(w / 2, h * 0.82))
            return GeometryPart(path: path, fill: true, stroke: true, open: false, evenOdd: true, textInset: 0.2)
        case "donut", "noSmoking":
            let path = CGMutablePath()
            path.addEllipse(in: r)
            let inset = ss * adj("adj", 25_000)
            path.addEllipse(in: r.insetBy(dx: inset, dy: inset))
            return GeometryPart(path: path, fill: true, stroke: true, open: false, evenOdd: true)
        case "frame":
            let path = CGMutablePath()
            path.addRect(r)
            let inset = ss * adj("adj1", 12_500)
            path.addRect(r.insetBy(dx: inset, dy: inset))
            return GeometryPart(path: path, fill: true, stroke: true, open: false, evenOdd: true)
        case "roundRect", "flowChartAlternateProcess", "wedgeRoundRectCallout":
            let radius = min(ss * adj("adj", 16_667), ss / 2)
            return GeometryPart(path: CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil), fill: true, stroke: true, open: false)
        case "flowChartTerminator":
            let radius = min(h / 2, w / 2)
            return GeometryPart(path: CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil), fill: true, stroke: true, open: false)
        case "round1Rect", "round2SameRect", "round2DiagRect":
            let radius = min(ss * adj("adj1", 16_667), ss / 2)
            let path = CGMutablePath()
            let top = name != "round2DiagRect"
            path.move(to: p(name == "round1Rect" ? 0 : radius, 0))
            path.addLine(to: p(w - radius, 0))
            path.addQuadCurve(to: p(w, radius), control: p(w, 0))
            path.addLine(to: p(w, h - (top ? 0 : radius)))
            if !top { path.addQuadCurve(to: p(w - radius, h), control: p(w, h)) }
            path.addLine(to: p(0, h))
            path.addLine(to: p(0, name == "round1Rect" ? 0 : radius))
            if name != "round1Rect" { path.addQuadCurve(to: p(radius, 0), control: p(0, 0)) }
            path.closeSubpath()
            return GeometryPart(path: path, fill: true, stroke: true, open: false)
        case "snip1Rect", "snip2SameRect", "snip2DiagRect", "snipRoundRect":
            let cut = ss * adj("adj1", 16_667)
            return polygon([p(0, 0), p(w - cut, 0), p(w, cut), p(w, h), p(0, h)])
        case "triangle", "flowChartExtract", "flowChartMerge":
            let x = w * adj("adj", 50_000)
            return name == "flowChartMerge" ? polygon([p(0, 0), p(w, 0), p(w / 2, h)]) : polygon([p(x, 0), p(w, h), p(0, h)])
        case "rtTriangle":
            return polygon([p(0, 0), p(w, h), p(0, h)])
        case "diamond", "flowChartDecision":
            return polygon([p(w / 2, 0), p(w, h / 2), p(w / 2, h), p(0, h / 2)])
        case "parallelogram", "flowChartInputOutput":
            let x = name == "parallelogram" ? ss * adj("adj", 25_000) : w / 5
            return polygon([p(x, 0), p(w, 0), p(w - x, h), p(0, h)])
        case "trapezoid", "flowChartManualOperation":
            let x = name == "trapezoid" ? ss * adj("adj", 25_000) : w / 5
            return name == "trapezoid"
                ? polygon([p(x, 0), p(w - x, 0), p(w, h), p(0, h)])
                : polygon([p(0, 0), p(w, 0), p(w - x, h), p(x, h)])
        case "flowChartManualInput":
            return polygon([p(0, h / 5), p(w, 0), p(w, h), p(0, h)])
        case "pentagon":
            return polygon([p(w / 2, 0), p(w, h * 0.38), p(w * 0.81, h), p(w * 0.19, h), p(0, h * 0.38)])
        case "hexagon", "flowChartPreparation":
            let x = min(ss * adj("adj", 25_000), w / 2)
            return polygon([p(x, 0), p(w - x, 0), p(w, h / 2), p(w - x, h), p(x, h), p(0, h / 2)])
        case "heptagon", "decagon", "dodecagon":
            let count = name == "heptagon" ? 7 : name == "decagon" ? 10 : 12
            return polygon(regular(count, rect: r, inner: nil))
        case "octagon":
            let c = min(ss * adj("adj", 29_289), ss / 2)
            return polygon([p(c, 0), p(w - c, 0), p(w, c), p(w, h - c), p(w - c, h), p(c, h), p(0, h - c), p(0, c)])
        case "homePlate", "flowChartOffpageConnector":
            if name == "flowChartOffpageConnector" { return polygon([p(0, 0), p(w, 0), p(w, h * 0.8), p(w / 2, h), p(0, h * 0.8)]) }
            let x = w - min(ss * adj("adj", 50_000), w)
            return polygon([p(0, 0), p(x, 0), p(w, h / 2), p(x, h), p(0, h)])
        case "chevron":
            let d = min(ss * adj("adj", 50_000), w)
            return polygon([p(0, 0), p(w - d, 0), p(w, h / 2), p(w - d, h), p(0, h), p(d, h / 2)])
        case "rightArrow", "leftArrow", "notchedRightArrow", "stripedRightArrow":
            let shaft = h * adj("adj1", 50_000)
            let head = min(ss * adj("adj2", 50_000), w)
            let y1 = (h - shaft) / 2, y2 = (h + shaft) / 2
            if name == "leftArrow" {
                return polygon([p(w, y1), p(head, y1), p(head, 0), p(0, h / 2), p(head, h), p(head, y2), p(w, y2)])
            }
            return polygon([p(0, y1), p(w - head, y1), p(w - head, 0), p(w, h / 2), p(w - head, h), p(w - head, y2), p(0, y2)])
        case "upArrow", "downArrow":
            let shaft = w * adj("adj1", 50_000)
            let head = min(ss * adj("adj2", 50_000), h)
            let x1 = (w - shaft) / 2, x2 = (w + shaft) / 2
            if name == "upArrow" {
                return polygon([p(x1, h), p(x1, head), p(0, head), p(w / 2, 0), p(w, head), p(x2, head), p(x2, h)])
            }
            return polygon([p(x1, 0), p(x1, h - head), p(0, h - head), p(w / 2, h), p(w, h - head), p(x2, h - head), p(x2, 0)])
        case "leftRightArrow":
            let shaft = h * adj("adj1", 50_000)
            let head = min(ss * adj("adj2", 50_000), w / 2)
            let y1 = (h - shaft) / 2, y2 = (h + shaft) / 2
            return polygon([p(0, h / 2), p(head, 0), p(head, y1), p(w - head, y1), p(w - head, 0), p(w, h / 2),
                            p(w - head, h), p(w - head, y2), p(head, y2), p(head, h)])
        case "upDownArrow":
            let shaft = w * adj("adj1", 50_000)
            let head = min(ss * adj("adj2", 50_000), h / 2)
            let x1 = (w - shaft) / 2, x2 = (w + shaft) / 2
            return polygon([p(w / 2, 0), p(w, head), p(x2, head), p(x2, h - head), p(w, h - head), p(w / 2, h),
                            p(0, h - head), p(x1, h - head), p(x1, head), p(0, head)])
        case "plus", "flowChartPunchedCard", "mathPlus":
            if name == "flowChartPunchedCard" { return polygon([p(w / 5, 0), p(w, 0), p(w, h), p(0, h), p(0, h / 5)]) }
            let c = ss * adj("adj", 25_000)
            return polygon([p(c, 0), p(w - c, 0), p(w - c, c), p(w, c), p(w, h - c), p(w - c, h - c), p(w - c, h),
                            p(c, h), p(c, h - c), p(0, h - c), p(0, c), p(c, c)])
        case "star4", "star5", "star6", "star7", "star8", "star10", "star12", "star16", "star24", "star32",
             "irregularSeal1", "irregularSeal2":
            let count = Int(name.dropFirst(4)) ?? 8
            let inner: CGFloat = count == 5 ? 0.38 : count == 4 ? 0.25 : 0.62
            return polygon(regular(count, rect: r, inner: inner))
        case "flowChartDocument", "flowChartMultidocument", "wave", "doubleWave":
            let path = CGMutablePath()
            path.move(to: p(0, 0)); path.addLine(to: p(w, 0)); path.addLine(to: p(w, h * 0.83))
            path.addCurve(to: p(0, h * 0.9), control1: p(w * 0.65, h * 0.7), control2: p(w * 0.35, h * 1.1))
            path.closeSubpath()
            return GeometryPart(path: path, fill: true, stroke: true, open: false)
        case "can", "flowChartMagneticDisk":
            let cap = min(h * adj("adj", 25_000), h / 2)
            let path = CGMutablePath()
            path.move(to: p(0, cap / 2))
            path.addLine(to: p(0, h - cap / 2))
            path.addCurve(to: p(w, h - cap / 2), control1: p(0, h + cap * 0.17), control2: p(w, h + cap * 0.17))
            path.addLine(to: p(w, cap / 2))
            path.closeSubpath()
            path.addEllipse(in: CGRect(x: r.minX, y: r.minY, width: w, height: cap))
            return GeometryPart(path: path, fill: true, stroke: true, open: false)
        case "pie", "chord", "blockArc":
            let a1 = adj("adj1", 0) * 100_000 / 60_000 * .pi / 180
            let a2 = adj("adj2", 1_620_000_000) * 100_000 / 60_000 * .pi / 180
            var sweep = a2 - a1
            if sweep <= 0 { sweep += 2 * .pi }
            let path = CGMutablePath()
            let t = CGAffineTransform(translationX: r.midX, y: r.midY).scaledBy(x: w / 2, y: h / 2)
            if name == "pie" { path.move(to: CGPoint(x: r.midX, y: r.midY)) }
            path.addRelativeArc(center: .zero, radius: 1, startAngle: a1, delta: sweep, transform: t)
            path.closeSubpath()
            return GeometryPart(path: path, fill: true, stroke: true, open: false)
        default:
            return GeometryPart(path: CGPath(rect: r, transform: nil), fill: true, stroke: true, open: false)
        }
    }

    static func regular(_ count: Int, rect r: CGRect, inner: CGFloat?) -> [CGPoint] {
        let center = CGPoint(x: r.midX, y: r.midY)
        var points: [CGPoint] = []
        let steps = inner == nil ? count : count * 2
        for index in 0..<steps {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(steps)
            let scale: CGFloat = inner != nil && index % 2 == 1 ? inner! : 1
            points.append(CGPoint(x: center.x + cos(angle) * r.width / 2 * scale, y: center.y + sin(angle) * r.height / 2 * scale))
        }
        return points
    }

    // MARK: Custom geometry

    static func customParts(_ geometry: XMLElement, rect: CGRect, emuSize: CGSize) -> [GeometryPart] {
        var guides = GuideEvaluator(width: emuSize.width, height: emuSize.height)
        for guide in geometry.kid("avLst")?.kids("gd") ?? [] { guides.define(guide) }
        for guide in geometry.kid("gdLst")?.kids("gd") ?? [] { guides.define(guide) }
        var parts: [GeometryPart] = []
        for pathNode in geometry.kid("pathLst")?.kids("path") ?? [] {
            let pw = pathNode.optionalNumber("w") ?? emuSize.width
            let ph = pathNode.optionalNumber("h") ?? emuSize.height
            let sx = pw > 0 ? rect.width / pw : 0
            let sy = ph > 0 ? rect.height / ph : 0
            let path = CGMutablePath()
            var current = CGPoint.zero
            var first: CGPoint?, second: CGPoint?
            var previous = CGPoint.zero
            var closed = false
            func point(_ node: XMLElement?) -> CGPoint {
                guard let node else { return .zero }
                return CGPoint(x: guides.value(node.attr("x")), y: guides.value(node.attr("y")))
            }
            func track(_ next: CGPoint) {
                if first == nil { first = next } else if second == nil { second = next }
                previous = current
                current = next
            }
            for command in pathNode.elements {
                switch command.localName {
                case "moveTo":
                    let pt = point(command.kid("pt"))
                    path.move(to: pt)
                    if first == nil { first = pt }
                    current = pt
                case "lnTo":
                    let pt = point(command.kid("pt"))
                    if path.isEmpty { path.move(to: current) }
                    path.addLine(to: pt)
                    track(pt)
                case "cubicBezTo":
                    let pts = command.kids("pt").map(point)
                    guard pts.count == 3 else { continue }
                    if path.isEmpty { path.move(to: current) }
                    path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
                    if second == nil, first != nil { second = pts[0] }
                    previous = pts[1]
                    current = pts[2]
                case "quadBezTo":
                    let pts = command.kids("pt").map(point)
                    guard pts.count == 2 else { continue }
                    if path.isEmpty { path.move(to: current) }
                    path.addQuadCurve(to: pts[1], control: pts[0])
                    if second == nil, first != nil { second = pts[0] }
                    previous = pts[0]
                    current = pts[1]
                case "arcTo":
                    let wr = guides.value(command.attr("wR")), hr = guides.value(command.attr("hR"))
                    let start = guides.value(command.attr("stAng")) / 60_000 * .pi / 180
                    let sweep = guides.value(command.attr("swAng")) / 60_000 * .pi / 180
                    guard wr > 0, hr > 0 else { continue }
                    let center = CGPoint(x: current.x - wr * cos(start), y: current.y - hr * sin(start))
                    if path.isEmpty { path.move(to: current) }
                    let t = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: wr, y: hr)
                    path.addRelativeArc(center: .zero, radius: 1, startAngle: start, delta: sweep, transform: t)
                    previous = current
                    current = CGPoint(x: center.x + wr * cos(start + sweep), y: center.y + hr * sin(start + sweep))
                case "close":
                    path.closeSubpath()
                    closed = true
                default:
                    break
                }
            }
            var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: sx, y: sy)
            guard let placed = path.copy(using: &transform) else { continue }
            let fillMode = pathNode.attr("fill") ?? "norm"
            let strokes = pathNode.flag("stroke") ?? true
            var part = GeometryPart(path: placed, fill: fillMode != "none", stroke: strokes, open: !closed)
            if !closed, let first, let second {
                part.start = (tip: first.applying(transform), from: second.applying(transform))
                part.end = (tip: current.applying(transform), from: previous.applying(transform))
            }
            parts.append(part)
        }
        return parts
    }
}

/// Evaluates DrawingML shape guide formulas.
struct GuideEvaluator {
    var values: [String: CGFloat] = [:]

    init(width w: CGFloat, height h: CGFloat) {
        let ss = min(w, h), ls = max(w, h)
        values = [
            "w": w, "h": h, "l": 0, "t": 0, "r": w, "b": h, "hc": w / 2, "vc": h / 2,
            "wd2": w / 2, "wd3": w / 3, "wd4": w / 4, "wd5": w / 5, "wd6": w / 6, "wd8": w / 8, "wd10": w / 10, "wd32": w / 32,
            "hd2": h / 2, "hd3": h / 3, "hd4": h / 4, "hd5": h / 5, "hd6": h / 6, "hd8": h / 8, "hd10": h / 10,
            "ss": ss, "ls": ls, "ssd2": ss / 2, "ssd4": ss / 4, "ssd6": ss / 6, "ssd8": ss / 8, "ssd16": ss / 16, "ssd32": ss / 32,
            "cd2": 10_800_000, "cd4": 5_400_000, "cd8": 2_700_000, "3cd4": 16_200_000, "3cd8": 8_100_000,
            "5cd8": 13_500_000, "7cd8": 18_900_000
        ]
    }

    func value(_ token: String?) -> CGFloat {
        guard let token else { return 0 }
        if let number = Double(token) { return CGFloat(number) }
        return values[token] ?? 0
    }

    mutating func define(_ guide: XMLElement) {
        guard let name = guide.attr("name"), let formula = guide.attr("fmla") else { return }
        values[name] = evaluate(formula)
    }

    func evaluate(_ formula: String) -> CGFloat {
        let parts = formula.split(separator: " ").map(String.init)
        guard let op = parts.first else { return 0 }
        let a = parts.count > 1 ? value(parts[1]) : 0
        let b = parts.count > 2 ? value(parts[2]) : 0
        let c = parts.count > 3 ? value(parts[3]) : 0
        let degrees = { (v: CGFloat) in v / 60_000 * .pi / 180 }
        switch op {
        case "val": return a
        case "*/": return c == 0 ? 0 : a * b / c
        case "+-": return a + b - c
        case "+/": return c == 0 ? 0 : (a + b) / c
        case "?:": return a > 0 ? b : c
        case "abs": return abs(a)
        case "at2": return atan2(b, a) * 180 / .pi * 60_000
        case "cat2": return a * cos(atan2(c, b))
        case "sat2": return a * sin(atan2(c, b))
        case "cos": return a * cos(degrees(b))
        case "sin": return a * sin(degrees(b))
        case "tan": return a * tan(degrees(b))
        case "max": return max(a, b)
        case "min": return min(a, b)
        case "mod": return sqrt(a * a + b * b + c * c)
        case "pin": return b < a ? a : b > c ? c : b
        case "sqrt": return sqrt(max(a, 0))
        default: return 0
        }
    }
}
