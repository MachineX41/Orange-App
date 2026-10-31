import AppKit
import SwiftUI

enum OrangeTheme {
    static let accent = Color(hex: 0xF15A12)
    static let accentDeep = Color(hex: 0xC2410C)
    static let canvas = Color(dynamic: (light: 0xF6F1EA, dark: 0x141210))
    static let sidebar = Color(dynamic: (light: 0xEFE8DF, dark: 0x1C1916))
    static let card = Color(dynamic: (light: 0xFFFCF8, dark: 0x26221E))
    static let ink = Color(dynamic: (light: 0x1C1612, dark: 0xF6F1EA))
    static let muted = Color(dynamic: (light: 0x6F655C, dark: 0xA89C90))
    static let line = Color(dynamicAlpha: (light: 0.08, dark: 0.10))
    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0xFF8A3D), Color(hex: 0xE23E00)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init(dynamic pair: (light: UInt32, dark: UInt32)) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = dark ? pair.dark : pair.light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    init(dynamicAlpha pair: (light: Double, dark: Double)) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(srgbRed: 0.12, green: 0.09, blue: 0.07, alpha: dark ? pair.dark : pair.light)
        })
    }
}

struct CardModifier: ViewModifier {
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .background(OrangeTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(OrangeTheme.line, lineWidth: 1)
            )
    }
}

extension View {
    func orangeCard(radius: CGFloat = 22) -> some View {
        modifier(CardModifier(radius: radius))
    }
}

struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView) }
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.title = "Orange"
    }
}
