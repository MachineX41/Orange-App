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

/// Warm stone mesh behind every window. Dark enough that glass reads as a surface, without an orange wash.
struct OrangeBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var intensity: Double = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let drift = Float(sin(t / 11) * 0.05)
            let sway = Float(cos(t / 13) * 0.04)
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
                Color(hex: 0x1B1A19), Color(hex: 0x1D1B1A), Color(hex: 0x18181B),
                Color(hex: 0x1E1B19), Color(hex: 0x2A1D14), Color(hex: 0x1A191C),
                Color(hex: 0x161616), Color(hex: 0x19181A), Color(hex: 0x17171A)
            ]
        }
        return [
            Color(hex: 0xE3DED6), Color(hex: 0xE0DAD1), Color(hex: 0xDCD7D0),
            Color(hex: 0xE1DBD2), Color(hex: 0xE6D3C0), Color(hex: 0xD8D3CC),
            Color(hex: 0xD6D1CA), Color(hex: 0xDAD4CC), Color(hex: 0xD2CDC6)
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

/// The application icon, used wherever Orange itself is the mark.
struct OrangeMark: View {
    var side: CGFloat = 36

    var body: some View {
        Image(nsImage: OrangeMark.image)
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous))
    }

    private static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "OrangeLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }()
}

/// Monochrome wheel for the menu bar. A template image so macOS tints it like its own status items.
enum MenuBarIcon {
    static let image: NSImage = {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let outer: CGFloat = 8.4
            let inner: CGFloat = 4.1
            let count = 8
            let slice = 2 * CGFloat.pi / CGFloat(count)
            let gap: CGFloat = 0.2
            NSColor.black.setFill()
            for index in 0..<count {
                let start = CGFloat(index) * slice + gap / 2 + .pi / 8
                let end = start + slice - gap
                let path = NSBezierPath()
                path.appendArc(withCenter: center, radius: outer, startAngle: start * 180 / .pi, endAngle: end * 180 / .pi)
                path.appendArc(withCenter: center, radius: inner, startAngle: end * 180 / .pi, endAngle: start * 180 / .pi, clockwise: true)
                path.close()
                path.fill()
            }
            NSBezierPath(ovalIn: CGRect(x: center.x - 1.7, y: center.y - 1.7, width: 3.4, height: 3.4)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Orange"
        return image
    }()
}

struct SectionLabel: View {
    var title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
            }
            Text(title)
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KeyCap: View {
    var text: String
    var pressed = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(pressed ? Color.white : Color.primary)
            .frame(minWidth: 14)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassEffect(pressed ? .regular.tint(OrangeTheme.accent) : .regular, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .scaleEffect(pressed ? 0.92 : 1)
    }
}

/// A shortcut such as ⇧⌘L drawn as separate keys.
struct KeyCombo: View {
    var keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCap(text: key)
            }
        }
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
