import CoreGraphics
import Foundation
import Observation

public typealias ProgressHandler = @Sendable (Double) -> Void

public enum LanguageChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case turkish
    case english

    public var id: String { rawValue }
}

public enum Lang {
    public static let defaultsKey = "language"

    /// Views read this while drawing, so changing it redraws every screen that asks for a string.
    @Observable
    final class Refresh {
        static let shared = Refresh()
        var token = 0
        private init() {}
    }

    nonisolated(unsafe) private static var stored: LanguageChoice = {
        LanguageChoice(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }()

    public static var choice: LanguageChoice {
        get { stored }
        set {
            stored = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            let bump = { Refresh.shared.token &+= 1 }
            if Thread.isMainThread {
                bump()
            } else {
                DispatchQueue.main.async(execute: bump)
            }
        }
    }

    public static var isTurkish: Bool {
        switch stored {
        case .turkish: true
        case .english: false
        case .system: Locale.preferredLanguages.first?.hasPrefix("tr") == true
        }
    }

    public static func t(_ english: String, _ turkish: String) -> String {
        if Thread.isMainThread {
            _ = Refresh.shared.token
        }
        return isTurkish ? turkish : english
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
