import AppKit
import CoreText
import Foundation

/// Draws DrawingML charts from the values cached inside the chart part.
struct ChartRenderer {
    struct Series {
        var name: String
        var values: [Double?]
        var xValues: [Double?]
        var color: NSColor?
        var pointColors: [Int: NSColor]
    }

    enum Kind { case bar, line, area, pie, doughnut, scatter, radar }

    let space: XMLElement
    let palette: DrawingPalette
    let context: CGContext

    func draw(in rect: CGRect) {
        guard let chart = space.kid("chart"), let plot = chart.kid("plotArea") else { return }
        if let fill = space.kid("spPr").flatMap(solid) {
            context.setFillColor(fill.srgbCG)
            context.fill(rect)
        }
        let base = min(max(min(rect.width, rect.height) / 26, 7), 16)
        var area = rect.insetBy(dx: base * 0.6, dy: base * 0.6)

        let groups = plot.elements.filter { ($0.localName ?? "").hasSuffix("Chart") }
        guard let group = groups.first else { return }
        let kind = kind(of: group)
        let allSeries = groups.flatMap { series(in: $0) }
        guard !allSeries.isEmpty else { return }
        let categories = categories(in: group)

        if let title = title(chart, fallback: allSeries.count == 1 && kind != .pie ? allSeries[0].name : nil) {
            let size = base * 1.35
            drawText(title, at: CGPoint(x: area.midX, y: area.minY + size), size: size, color: palette.text, align: .center, bold: false)
            area.origin.y += size * 1.8
            area.size.height -= size * 1.8
        }

        var legendItems: [(String, NSColor)] = []
        if chart.kid("legend") != nil {
            if kind == .pie || kind == .doughnut || (group.kid("varyColors")?.flag("val") == true && allSeries.count == 1) {
                legendItems = categories.enumerated().map { ($0.element, color(for: allSeries[0], index: 0, point: $0.offset, vary: true)) }
            } else {
                legendItems = allSeries.enumerated().map { ($0.element.name, color(for: $0.element, index: $0.offset, point: nil, vary: false)) }
            }
        }
        let legendPosition = chart.kid("legend")?.kid("legendPos")?.attr("val") ?? "r"
        if !legendItems.isEmpty {
            area = drawLegend(legendItems, in: area, position: legendPosition, size: base)
        }

        switch kind {
        case .pie, .doughnut:
            drawPie(allSeries[0], kind: kind, group: group, in: area, size: base)
        case .scatter:
            drawScatter(allSeries, in: area, size: base)
        case .radar:
            drawRadar(allSeries, categories: categories, in: area, size: base)
        default:
            drawCartesian(allSeries, categories: categories, kind: kind, group: group, in: area, size: base)
        }
    }

    // MARK: Parsing

    func kind(of group: XMLElement) -> Kind {
        switch group.localName {
        case "lineChart", "line3DChart", "stockChart": return .line
        case "areaChart", "area3DChart": return .area
        case "pieChart", "pie3DChart", "ofPieChart": return .pie
        case "doughnutChart": return .doughnut
        case "scatterChart", "bubbleChart": return .scatter
        case "radarChart": return .radar
        default: return .bar
        }
    }

    func series(in group: XMLElement) -> [Series] {
        group.kids("ser").map { node in
            let name = node.kid("tx").map(cachedStrings).flatMap(\.first) ?? node.kid("tx")?.kid("v")?.stringValue ?? ""
            let values = (node.kid("val") ?? node.kid("yVal")).map(cachedNumbers) ?? []
            let xs = node.kid("xVal").map(cachedNumbers) ?? []
            var points: [Int: NSColor] = [:]
            for point in node.kids("dPt") {
                if let index = Int(point.kid("idx")?.attr("val") ?? ""), let color = point.kid("spPr").flatMap(solid) {
                    points[index] = color
                }
            }
            return Series(name: name, values: values, xValues: xs, color: node.kid("spPr").flatMap(solid), pointColors: points)
        }
    }

    func categories(in group: XMLElement) -> [String] {
        guard let first = group.kid("ser") else { return [] }
        if let cat = first.kid("cat") {
            let strings = cachedStrings(cat)
            if !strings.isEmpty { return strings }
            return cachedNumbers(cat).map { $0.map(format) ?? "" }
        }
        let count = (first.kid("val").map(cachedNumbers) ?? []).count
        return (0..<count).map { String($0 + 1) }
    }

    func cachedStrings(_ node: XMLElement) -> [String] {
        guard let cache = node.deep("strCache") ?? node.deep("strLit") ?? node.deep("multiLvlStrCache") else { return [] }
        let count = Int(cache.kid("ptCount")?.attr("val") ?? "") ?? 0
        var output = Array(repeating: "", count: count)
        for point in cache.deepAll("pt") {
            guard let index = Int(point.attr("idx") ?? "") else { continue }
            let value = point.kid("v")?.stringValue ?? ""
            if index < output.count { if output[index].isEmpty { output[index] = value } } else { output.append(value) }
        }
        return output
    }

    func cachedNumbers(_ node: XMLElement) -> [Double?] {
        guard let cache = node.deep("numCache") ?? node.deep("numLit") else { return [] }
        let count = Int(cache.kid("ptCount")?.attr("val") ?? "") ?? 0
        var output: [Double?] = Array(repeating: nil, count: count)
        for point in cache.kids("pt") + cache.deepAll("pt") {
            guard let index = Int(point.attr("idx") ?? ""), let value = point.kid("v")?.stringValue.flatMap(Double.init) else { continue }
            while output.count <= index { output.append(nil) }
            output[index] = value
        }
        return output
    }

    func title(_ chart: XMLElement, fallback: String?) -> String? {
        if let title = chart.kid("title") {
            let rich = title.deep("rich").map { $0.deepAll("t").compactMap(\.stringValue).joined() }
            let cached = title.kid("tx").map(cachedStrings)?.first
            let text = rich ?? cached ?? fallback ?? ""
            return text.isEmpty ? nil : text
        }
        if chart.kid("autoTitleDeleted")?.flag("val") == true { return nil }
        return fallback
    }

    func solid(_ properties: XMLElement) -> NSColor? {
        if properties.kid("noFill") != nil { return nil }
        if let fill = properties.kid("solidFill") { return palette.color(in: fill) }
        if let stop = properties.kid("gradFill")?.kid("gsLst")?.kids("gs").first { return palette.color(in: stop) }
        return nil
    }

    func color(for series: Series, index: Int, point: Int?, vary: Bool) -> NSColor {
        if let point, let custom = series.pointColors[point] { return custom }
        if !vary, let color = series.color { return color }
        let slot = vary ? (point ?? 0) : index
        let base = palette.scheme("accent\(slot % 6 + 1)") ?? .systemBlue
        let round = slot / 6
        guard round > 0 else { return base }
        return round % 2 == 1 ? base.blended(with: .black, fraction: 0.3) : base.blended(with: .white, fraction: 0.35)
    }

    // MARK: Drawing

    func drawLegend(_ items: [(String, NSColor)], in area: CGRect, position: String, size: CGFloat) -> CGRect {
        let font = size * 0.95
        let swatch = font * 0.8
        let widths = items.map { textWidth($0.0, size: font) + swatch + font * 0.6 }
        var remaining = area
        if position == "b" || position == "t" {
            let total = widths.reduce(0, +) + CGFloat(max(items.count - 1, 0)) * font
            var x = area.midX - min(total, area.width) / 2
            let y = position == "b" ? area.maxY - font * 0.4 : area.minY + font
            for (offset, item) in items.enumerated() {
                context.setFillColor(item.1.srgbCG)
                context.fill(CGRect(x: x, y: y - swatch, width: swatch, height: swatch))
                drawText(item.0, at: CGPoint(x: x + swatch + font * 0.3, y: y), size: font, color: palette.text, align: .left, bold: false)
                x += widths[offset] + font
            }
            remaining.size.height -= font * 2
            if position == "t" { remaining.origin.y += font * 2 }
        } else {
            let column = min((widths.max() ?? 0) + font, area.width * 0.4)
            let total = CGFloat(items.count) * font * 1.5
            var y = area.midY - total / 2 + font
            let x = position == "l" ? area.minX : area.maxX - column + font * 0.5
            for item in items {
                context.setFillColor(item.1.srgbCG)
                context.fill(CGRect(x: x, y: y - swatch, width: swatch, height: swatch))
                drawText(item.0, at: CGPoint(x: x + swatch + font * 0.3, y: y), size: font, color: palette.text, align: .left, bold: false)
                y += font * 1.5
            }
            remaining.size.width -= column
            if position == "l" { remaining.origin.x += column }
        }
        return remaining
    }

    func drawPie(_ series: Series, kind: Kind, group: XMLElement, in area: CGRect, size: CGFloat) {
        let values = series.values.map { max($0 ?? 0, 0) }
        let total = values.reduce(0, +)
        guard total > 0 else { return }
        let radius = min(area.width, area.height) / 2 * 0.92
        let center = CGPoint(x: area.midX, y: area.midY)
        let hole = kind == .doughnut ? radius * CGFloat(group.kid("holeSize").map { $0.number("val") } ?? 50) / 100 : 0
        var angle = -CGFloat.pi / 2 + CGFloat(group.kid("firstSliceAng")?.number("val") ?? 0) * .pi / 180
        let labels = group.deep("showPercent")?.flag("val") == true || group.deep("showVal")?.flag("val") == true
        let percent = group.deep("showPercent")?.flag("val") == true
        for (index, value) in values.enumerated() where value > 0 {
            let sweep = CGFloat(value / total) * 2 * .pi
            let path = CGMutablePath()
            path.addArc(center: center, radius: radius, startAngle: angle, endAngle: angle + sweep, clockwise: false)
            if hole > 0 {
                path.addArc(center: center, radius: hole, startAngle: angle + sweep, endAngle: angle, clockwise: true)
            } else {
                path.addLine(to: center)
            }
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(color(for: series, index: 0, point: index, vary: true).srgbCG)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(NSColor.white.srgbCG)
            context.setLineWidth(max(radius / 120, 0.75))
            context.strokePath()
            if labels {
                let middle = angle + sweep / 2
                let distance = hole > 0 ? (radius + hole) / 2 : radius * 0.62
                let text = percent ? "\(Int((value / total * 100).rounded()))%" : format(value)
                drawText(text, at: CGPoint(x: center.x + cos(middle) * distance, y: center.y + sin(middle) * distance + size * 0.35),
                         size: size, color: .white, align: .center, bold: true)
            }
            angle += sweep
        }
    }

    func drawCartesian(_ series: [Series], categories: [String], kind: Kind, group: XMLElement, in area: CGRect, size: CGFloat) {
        let grouping = group.kid("grouping")?.attr("val") ?? "clustered"
        let stacked = grouping == "stacked" || grouping == "percentStacked"
        let percent = grouping == "percentStacked"
        let horizontal = group.kid("barDir")?.attr("val") == "bar" && kind == .bar
        let count = max(categories.count, series.map(\.values.count).max() ?? 0)
        guard count > 0 else { return }

        var low = 0.0, high = 0.0
        for index in 0..<count {
            if stacked {
                var positive = 0.0, negative = 0.0
                for item in series {
                    let value = index < item.values.count ? item.values[index] ?? 0 : 0
                    if value >= 0 { positive += value } else { negative += value }
                }
                if percent { positive = positive > 0 ? 100 : 0; negative = negative < 0 ? -100 : 0 }
                high = max(high, positive); low = min(low, negative)
            } else {
                for item in series where index < item.values.count {
                    if let value = item.values[index] { high = max(high, value); low = min(low, value) }
                }
            }
        }
        if high == low { high = low + 1 }
        let ticks = niceTicks(low: low, high: high)
        low = ticks.first ?? low
        high = ticks.last ?? high

        let labelSize = size * 0.85
        let valueLabelWidth = ticks.map { textWidth(format($0) + (percent ? "%" : ""), size: labelSize) }.max() ?? 0
        var plot = area
        if horizontal {
            let categoryWidth = min(categories.map { textWidth($0, size: labelSize) }.max() ?? 0, area.width * 0.3)
            plot.origin.x += categoryWidth + labelSize * 0.6
            plot.size.width -= categoryWidth + labelSize * 0.6
            plot.size.height -= labelSize * 1.6
        } else {
            plot.origin.x += valueLabelWidth + labelSize * 0.6
            plot.size.width -= valueLabelWidth + labelSize * 0.6
            plot.size.height -= labelSize * 1.8
        }
        guard plot.width > 4, plot.height > 4 else { return }

        func position(_ value: Double) -> CGFloat {
            let fraction = CGFloat((value - low) / (high - low))
            return horizontal ? plot.minX + fraction * plot.width : plot.maxY - fraction * plot.height
        }

        context.setLineWidth(0.5)
        context.setStrokeColor(NSColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1).srgbCG)
        for tick in ticks {
            let p = position(tick)
            if horizontal {
                context.move(to: CGPoint(x: p, y: plot.minY)); context.addLine(to: CGPoint(x: p, y: plot.maxY))
            } else {
                context.move(to: CGPoint(x: plot.minX, y: p)); context.addLine(to: CGPoint(x: plot.maxX, y: p))
            }
        }
        context.strokePath()
        let labelColor = palette.text.blended(with: .white, fraction: 0.35)
        for tick in ticks {
            let text = format(tick) + (percent ? "%" : "")
            if horizontal {
                drawText(text, at: CGPoint(x: position(tick), y: plot.maxY + labelSize * 1.3), size: labelSize, color: labelColor, align: .center, bold: false)
            } else {
                drawText(text, at: CGPoint(x: plot.minX - labelSize * 0.4, y: position(tick) + labelSize * 0.35), size: labelSize, color: labelColor, align: .right, bold: false)
            }
        }

        let band = (horizontal ? plot.height : plot.width) / CGFloat(count)
        for (index, name) in categories.enumerated() where index < count {
            let center = (horizontal ? plot.minY : plot.minX) + band * (CGFloat(index) + 0.5)
            if horizontal {
                drawText(name, at: CGPoint(x: plot.minX - labelSize * 0.4, y: center + labelSize * 0.35), size: labelSize, color: labelColor, align: .right, bold: false)
            } else {
                drawText(name, at: CGPoint(x: center, y: plot.maxY + labelSize * 1.3), size: labelSize, color: labelColor, align: .center, bold: false, maxWidth: band)
            }
        }

        let zero = position(max(low, min(0, high)))
        let showValues = group.deep("dLbls")?.kid("showVal")?.flag("val") == true
        switch kind {
        case .bar:
            let gap = CGFloat(group.kid("gapWidth")?.number("val") ?? 150) / 100
            let slots = stacked ? 1 : max(series.count, 1)
            let barWidth = band / (CGFloat(slots) + gap)
            for index in 0..<count {
                var positive = 0.0, negative = 0.0
                let total = series.reduce(0.0) { $0 + abs(index < $1.values.count ? $1.values[index] ?? 0 : 0) }
                for (s, item) in series.enumerated() {
                    guard index < item.values.count, var value = item.values[index] else { continue }
                    if percent { value = total > 0 ? value / total * 100 : 0 }
                    let from: Double, to: Double
                    if stacked {
                        if value >= 0 { from = positive; positive += value; to = positive } else { from = negative; negative += value; to = negative }
                    } else {
                        from = 0; to = value
                    }
                    let a = position(max(min(from, high), low)), b = position(max(min(to, high), low))
                    let offset = (horizontal ? plot.minY : plot.minX) + band * CGFloat(index) + barWidth * gap / 2
                        + (stacked ? 0 : barWidth * CGFloat(s))
                    let bar = horizontal
                        ? CGRect(x: min(a, b), y: offset, width: abs(b - a), height: barWidth)
                        : CGRect(x: offset, y: min(a, b), width: barWidth, height: abs(b - a))
                    let vary = group.kid("varyColors")?.flag("val") == true && series.count == 1
                    context.setFillColor(color(for: item, index: s, point: index, vary: vary).srgbCG)
                    context.fill(bar)
                    if showValues {
                        let point = horizontal ? CGPoint(x: bar.maxX + labelSize * 0.3, y: bar.midY + labelSize * 0.35) : CGPoint(x: bar.midX, y: bar.minY - labelSize * 0.3)
                        drawText(format(item.values[index] ?? 0), at: point, size: labelSize, color: palette.text, align: horizontal ? .left : .center, bold: false)
                    }
                }
            }
        case .line, .area:
            var running = Array(repeating: 0.0, count: count)
            for (s, item) in series.enumerated() {
                var points: [CGPoint] = []
                for index in 0..<count {
                    guard index < item.values.count, let raw = item.values[index] else { continue }
                    var value = raw
                    if stacked { running[index] += raw; value = running[index] }
                    points.append(CGPoint(x: plot.minX + band * (CGFloat(index) + 0.5), y: position(value)))
                }
                guard !points.isEmpty else { continue }
                let color = color(for: item, index: s, point: nil, vary: false)
                if kind == .area {
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: points[0].x, y: zero))
                    path.addLines(between: points)
                    path.addLine(to: CGPoint(x: points[points.count - 1].x, y: zero))
                    path.closeSubpath()
                    context.addPath(path)
                    context.setFillColor(color.withAlphaComponent(0.85).srgbCG)
                    context.fillPath()
                } else {
                    context.setStrokeColor(color.srgbCG)
                    context.setLineWidth(max(size / 6, 1.5))
                    context.setLineJoin(.round)
                    context.addLines(between: points)
                    context.strokePath()
                    context.setFillColor(color.srgbCG)
                    for point in points {
                        context.fillEllipse(in: CGRect(x: point.x - size / 5, y: point.y - size / 5, width: size / 2.5, height: size / 2.5))
                    }
                }
            }
        default:
            break
        }
        context.setStrokeColor(NSColor(srgbRed: 0.75, green: 0.75, blue: 0.75, alpha: 1).srgbCG)
        context.setLineWidth(0.75)
        if horizontal {
            context.move(to: CGPoint(x: zero, y: plot.minY)); context.addLine(to: CGPoint(x: zero, y: plot.maxY))
        } else {
            context.move(to: CGPoint(x: plot.minX, y: zero)); context.addLine(to: CGPoint(x: plot.maxX, y: zero))
        }
        context.strokePath()
    }

    func drawScatter(_ series: [Series], in area: CGRect, size: CGFloat) {
        let xs = series.flatMap { $0.xValues.isEmpty ? $0.values.indices.map { Double($0 + 1) } : $0.xValues.compactMap { $0 } }
        let ys = series.flatMap { $0.values.compactMap { $0 } }
        guard let xMin = xs.min(), let xMax = xs.max(), let yMin = ys.min(), let yMax = ys.max() else { return }
        let xTicks = niceTicks(low: min(xMin, 0), high: xMax == xMin ? xMin + 1 : xMax)
        let yTicks = niceTicks(low: min(yMin, 0), high: yMax == yMin ? yMin + 1 : yMax)
        let labelSize = size * 0.85
        let labelWidth = yTicks.map { textWidth(format($0), size: labelSize) }.max() ?? 0
        var plot = area
        plot.origin.x += labelWidth + labelSize * 0.6
        plot.size.width -= labelWidth + labelSize * 0.6
        plot.size.height -= labelSize * 1.8
        guard plot.width > 4, plot.height > 4, let x0 = xTicks.first, let x1 = xTicks.last, let y0 = yTicks.first, let y1 = yTicks.last else { return }
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: plot.minX + CGFloat((x - x0) / (x1 - x0)) * plot.width, y: plot.maxY - CGFloat((y - y0) / (y1 - y0)) * plot.height)
        }
        context.setStrokeColor(NSColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1).srgbCG)
        context.setLineWidth(0.5)
        for tick in yTicks {
            let p = point(x0, tick)
            context.move(to: p); context.addLine(to: CGPoint(x: plot.maxX, y: p.y))
            drawText(format(tick), at: CGPoint(x: plot.minX - labelSize * 0.4, y: p.y + labelSize * 0.35), size: labelSize, color: palette.text, align: .right, bold: false)
        }
        context.strokePath()
        for tick in xTicks {
            drawText(format(tick), at: CGPoint(x: point(tick, y0).x, y: plot.maxY + labelSize * 1.3), size: labelSize, color: palette.text, align: .center, bold: false)
        }
        for (s, item) in series.enumerated() {
            context.setFillColor(color(for: item, index: s, point: nil, vary: false).srgbCG)
            for (index, value) in item.values.enumerated() {
                guard let value else { continue }
                let x = item.xValues.isEmpty ? Double(index + 1) : (index < item.xValues.count ? item.xValues[index] ?? 0 : 0)
                let p = point(x, value)
                context.fillEllipse(in: CGRect(x: p.x - size / 4, y: p.y - size / 4, width: size / 2, height: size / 2))
            }
        }
    }

    func drawRadar(_ series: [Series], categories: [String], in area: CGRect, size: CGFloat) {
        let count = max(categories.count, series.map(\.values.count).max() ?? 0)
        guard count > 1 else { return }
        let values = series.flatMap { $0.values.compactMap { $0 } }
        let high = max(values.max() ?? 1, 1)
        let radius = min(area.width, area.height) / 2 * 0.78
        let center = CGPoint(x: area.midX, y: area.midY)
        let labelSize = size * 0.85
        context.setStrokeColor(NSColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1).srgbCG)
        context.setLineWidth(0.75)
        for ring in 1...4 {
            let r = radius * CGFloat(ring) / 4
            let path = CGMutablePath()
            for index in 0..<count {
                let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(count)
                let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            context.addPath(path)
            context.strokePath()
        }
        for index in 0..<count {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(count)
            context.move(to: center)
            context.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            context.strokePath()
            let name = index < categories.count ? categories[index] : String(index + 1)
            let label = CGPoint(x: center.x + cos(angle) * (radius + labelSize * 1.4), y: center.y + sin(angle) * (radius + labelSize * 1.4) + labelSize * 0.35)
            drawText(name, at: label, size: labelSize, color: palette.text, align: .center, bold: false)
        }
        for (s, item) in series.enumerated() {
            var points: [CGPoint] = []
            for index in 0..<count {
                let value = index < item.values.count ? item.values[index] ?? 0 : 0
                let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(count)
                let distance = radius * CGFloat(max(min(value / high, 1), 0))
                points.append(CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance))
            }
            guard points.count > 1 else { continue }
            let color = color(for: item, index: s, point: nil, vary: false)
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(color.withAlphaComponent(0.22).srgbCG)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(color.srgbCG)
            context.setLineWidth(max(size / 6, 1.5))
            context.strokePath()
            context.setFillColor(color.srgbCG)
            for point in points {
                context.fillEllipse(in: CGRect(x: point.x - size / 5, y: point.y - size / 5, width: size / 2.5, height: size / 2.5))
            }
        }
    }

    // MARK: Helpers

    func niceTicks(low: Double, high: Double) -> [Double] {
        let span = high - low
        guard span > 0, span.isFinite else { return [low, low + 1] }
        let rough = span / 5
        let magnitude = pow(10, floor(log10(rough)))
        let residual = rough / magnitude
        let step = (residual > 5 ? 10 : residual > 2 ? 5 : residual > 1 ? 2 : 1) * magnitude
        let start = floor(low / step) * step
        let end = ceil(high / step) * step
        var ticks: [Double] = []
        var value = start
        while value <= end + step / 2, ticks.count < 30 {
            ticks.append(abs(value) < step / 1e6 ? 0 : value)
            value += step
        }
        return ticks
    }

    func format(_ value: Double) -> String {
        if abs(value) >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value == value.rounded() { return String(Int(value)) }
        return String(format: abs(value) < 1 ? "%.2f" : "%.1f", value)
    }

    func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributed(text, size: size, color: .black, bold: false))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    func attributed(_ text: String, size: CGFloat, color: NSColor, bold: Bool) -> NSAttributedString {
        let font = FontResolver.font(family: palette.theme.minorFont, size: size, bold: bold, italic: false)
        return NSAttributedString(string: text, attributes: [
            .font: font as CTFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.srgbCG
        ])
    }

    /// Draws a single line with its baseline at `point` in a y-down context.
    func drawText(_ text: String, at point: CGPoint, size: CGFloat, color: NSColor, align: NSTextAlignment, bold: Bool, maxWidth: CGFloat? = nil) {
        var line = CTLineCreateWithAttributedString(attributed(text, size: size, color: color, bold: bold))
        if let maxWidth, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) > maxWidth,
           let truncated = CTLineCreateTruncatedLine(line, Double(maxWidth), .end,
                                                      CTLineCreateWithAttributedString(attributed("…", size: size, color: color, bold: bold))) {
            line = truncated
        }
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let x: CGFloat = align == .center ? point.x - width / 2 : align == .right ? point.x - width : point.x
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: point.y)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
