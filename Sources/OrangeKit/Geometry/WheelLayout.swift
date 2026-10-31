import CoreGraphics
import Foundation

public struct WheelLayout: Equatable, Sendable {
    public var center: CGPoint
    public var ringRadius: CGFloat
    public var innerRadius: CGFloat
    public var outerRadius: CGFloat
    public var count: Int

    public init(center: CGPoint, ringRadius: CGFloat, innerRadius: CGFloat, outerRadius: CGFloat, count: Int) {
        self.center = center
        self.ringRadius = ringRadius
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.count = count
    }

    public var sliceAngle: CGFloat {
        count > 0 ? (2 * .pi) / CGFloat(count) : 0
    }

    /// Angle of the slice's center. Index 0 sits at twelve o’clock and indexes advance clockwise on screen.
    public func angle(for index: Int) -> CGFloat {
        -.pi / 2 + CGFloat(index) * sliceAngle
    }

    public func point(for index: Int, radius: CGFloat? = nil) -> CGPoint {
        guard count > 0 else { return center }
        let theta = angle(for: index)
        let r = radius ?? ringRadius
        return CGPoint(x: center.x + cos(theta) * r, y: center.y + sin(theta) * r)
    }

    /// Point uses a top-left origin with y growing downward.
    public func index(at point: CGPoint) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= outerRadius else { return nil }
        var delta = atan2(dy, dx) + .pi / 2
        while delta < 0 { delta += 2 * .pi }
        while delta >= 2 * .pi { delta -= 2 * .pi }
        var index = Int((delta / sliceAngle).rounded())
        index %= count
        return index
    }
}
