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

    public func point(for index: Int) -> CGPoint {
        guard count > 0 else { return center }
        let slice = (2 * CGFloat.pi) / CGFloat(count)
        let theta = (-CGFloat.pi / 2) + (CGFloat(index) * slice)
        return CGPoint(
            x: center.x + cos(theta) * ringRadius,
            y: center.y + sin(theta) * ringRadius
        )
    }

    public func index(at point: CGPoint) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= outerRadius else { return nil }

        let slice = (2 * CGFloat.pi) / CGFloat(count)
        var delta = atan2(dy, dx) - (-CGFloat.pi / 2)
        while delta <= -.pi { delta += 2 * .pi }
        while delta > .pi { delta -= 2 * .pi }
        var index = Int((delta / slice).rounded())
        index %= count
        if index < 0 { index += count }
        return index
    }
}
