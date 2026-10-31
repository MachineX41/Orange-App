import CoreGraphics
import Foundation

public typealias ProgressHandler = @Sendable (Double) -> Void

public enum Lang {
    public static var isTurkish: Bool {
        Locale.preferredLanguages.first?.hasPrefix("tr") == true
    }

    public static func t(_ english: String, _ turkish: String) -> String {
        isTurkish ? turkish : english
    }
}

public struct RGBA: Hashable, Codable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255,
            alpha
        )
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    public func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(r, g, b, alpha)
    }
}
