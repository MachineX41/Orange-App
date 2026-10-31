import AppKit
import OrangeKit
import SwiftUI

enum OrangeTheme {
    static let accent = Color(hex: 0xF26B1D)
    static let accentDeep = Color(hex: 0xD9480F)
    static let ember = Color(hex: 0xFF453A)
    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0xFF9F45), Color(hex: 0xF0522B)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let stage = Color(hex: 0x101012)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }

    var rgba: RGBA {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return RGBA(Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent), Double(color.alphaComponent))
    }
}

/// Warm animated mesh behind every window, the colour that Liquid Glass refracts.
struct OrangeBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var intensity: Double = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let drift = Float(sin(t / 7) * 0.06)
            let sway = Float(cos(t / 9) * 0.05)
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5 + sway, 0], [1, 0],
                    [0, 0.5 - drift], [0.5 + drift, 0.5 + sway], [1, 0.5 + drift],
                    [0, 1], [0.5 - sway, 1], [1, 1]
                ],
                colors: palette
            )
            .opacity(intensity)
        }
        .ignoresSafeArea()
    }

    private var palette: [Color] {
        if scheme == .dark {
            return [
                Color(hex: 0x2A1206), Color(hex: 0x3A1508), Color(hex: 0x24080F),
                Color(hex: 0x4A1D07), Color(hex: 0x6B2A0A), Color(hex: 0x3B0D1F),
                Color(hex: 0x1A0A06), Color(hex: 0x2E0B1A), Color(hex: 0x1C0A24)
            ]
        }
        return [
            Color(hex: 0xFFE7B3), Color(hex: 0xFFC978), Color(hex: 0xFFB37A),
            Color(hex: 0xFFB258), Color(hex: 0xFF8A3D), Color(hex: 0xF7798A),
            Color(hex: 0xFF9F6B), Color(hex: 0xF06A8F), Color(hex: 0xB77BE0)
        ]
    }
}

struct GlassCard: ViewModifier {
    var radius: CGFloat = 24
    var tint: Color?
    var interactive = false

    func body(content: Content) -> some View {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return content.glassEffect(glass, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func glassCard(radius: CGFloat = 24, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, tint: tint, interactive: interactive))
    }
}

struct SectionLabel: View {
    var title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(title)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(OrangeTheme.ember)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KeyCap: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct EmptyHint: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
