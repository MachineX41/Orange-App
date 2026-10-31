import AVFoundation
import OrangeKit
import SwiftUI

enum WheelMetrics {
    static let size: CGFloat = 308
    static let outer: CGFloat = 142
    static let inner: CGFloat = 58
    static let gap: CGFloat = 5
    static let corner: CGFloat = 14

    static func layout(count: Int, in size: CGSize = CGSize(width: WheelMetrics.size, height: WheelMetrics.size)) -> WheelLayout {
        WheelLayout(
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            ringRadius: (outer + inner) / 2,
            innerRadius: inner + 2,
            outerRadius: outer + 8,
            count: count
        )
    }
}

/// Annular sector with rounded corners. Index 0 is centered at twelve o’clock.
struct WheelSegment: Shape {
    var index: Int
    var count: Int
    var inner: CGFloat = WheelMetrics.inner
    var outer: CGFloat = WheelMetrics.outer
    var gap: CGFloat = WheelMetrics.gap
    var corner: CGFloat = WheelMetrics.corner

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard count > 1 else {
            let ring = Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
            return ring.subtracting(Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)))
        }
        let slice = 2 * CGFloat.pi / CGFloat(count)
        let mid = -CGFloat.pi / 2 + CGFloat(index) * slice
        let r0 = inner + corner
        let r1 = outer - corner
        let half0 = max(0.01, slice / 2 - (gap / 2 + corner) / r0)
        let half1 = max(0.01, slice / 2 - (gap / 2 + corner) / r1)

        func point(_ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }

        var base = Path()
        let steps = 28
        for step in 0...steps {
            let angle = mid - half1 + 2 * half1 * CGFloat(step) / CGFloat(steps)
            step == 0 ? base.move(to: point(r1, angle)) : base.addLine(to: point(r1, angle))
        }
        for step in 0...steps {
            let angle = mid + half0 - 2 * half0 * CGFloat(step) / CGFloat(steps)
            base.addLine(to: point(r0, angle))
        }
        base.closeSubpath()
        return base.union(base.strokedPath(StrokeStyle(lineWidth: corner * 2, lineCap: .round, lineJoin: .round)))
    }
}

struct WheelFace: View {
    var session: WheelSession
    var highlight: Int?

    private var layout: WheelLayout { WheelMetrics.layout(count: session.choices.count) }

    var body: some View {
        ZStack {
            GlassEffectContainer(spacing: 0) {
                ForEach(Array(session.choices.enumerated()), id: \.element.id) { index, _ in
                    let shape = WheelSegment(index: index, count: session.choices.count)
                    Color.clear
                        .frame(width: WheelMetrics.size, height: WheelMetrics.size)
                        .glassEffect(glass(for: index), in: shape)
                        .overlay {
                            shape
                                .fill(LinearGradient(colors: [Color(hex: 0xFF8A3D), OrangeTheme.accentDeep], startPoint: .top, endPoint: .bottom))
                                .opacity(index == highlight ? 0.92 : 0)
                                .allowsHitTesting(false)
                        }
                }
            }

            ForEach(Array(session.choices.enumerated()), id: \.element.id) { index, choice in
                let selected = index == highlight
                VStack(spacing: 3) {
                    Image(systemName: choice.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                    Text(choice.title.uppercased(with: .current))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 64)
                .scaleEffect(selected ? 1.04 : 1)
                .position(layout.point(for: index))
            }

            WheelCenter(session: session)
        }
        .frame(width: WheelMetrics.size, height: WheelMetrics.size)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: highlight)
    }

    private func glass(for index: Int) -> Glass {
        index == highlight ? .regular.tint(OrangeTheme.accent).interactive() : .regular.interactive()
    }
}

struct WheelCenter: View {
    var session: WheelSession

    private var label: String {
        let size = ByteCountFormatter.string(fromByteCount: session.files.reduce(0) { $0 + $1.byteCount }, countStyle: .file)
        return session.files.count > 1 ? "\(session.files.count) · \(size)" : size
    }

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: Capsule())
    }
}

/// Click-driven wheel shown inside the main window.
struct LocalWheelOverlay: View {
    @Environment(AppRuntime.self) private var runtime
    var session: WheelSession
    @State var highlight: Int?
    @State var appeared = false
    @FocusState var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { runtime.localWheel = nil }
            WheelFace(session: session, highlight: highlight)
                .contentShape(Circle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let point):
                        let index = WheelMetrics.layout(count: session.choices.count).index(at: point)
                        if index != highlight, index != nil { WheelFeedback.sliceChanged() }
                        highlight = index
                    case .ended:
                        break
                    }
                }
                .onTapGesture(coordinateSpace: .local) { point in
                    if let index = WheelMetrics.layout(count: session.choices.count).index(at: point) {
                        runtime.commit(session.choices[index], files: session.files)
                    } else {
                        runtime.localWheel = nil
                    }
                }
                .scaleEffect(appeared ? 1 : 0.86)
                .opacity(appeared ? 1 : 0)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.escape) {
            runtime.localWheel = nil
            return .handled
        }
        .onKeyPress(.rightArrow) { step(1) }
        .onKeyPress(.downArrow) { step(1) }
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.upArrow) { step(-1) }
        .onKeyPress(.return) {
            if let highlight { runtime.commit(session.choices[highlight], files: session.files) }
            return .handled
        }
        .onAppear {
            focused = true
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { appeared = true }
        }
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        let count = session.choices.count
        let next = ((highlight ?? (delta > 0 ? -1 : 0)) + delta + count) % count
        if next != highlight { WheelFeedback.sliceChanged() }
        highlight = next
        return .handled
    }
}

/// Quiet tick plus the system alignment haptic when the pointer moves onto another slice.
enum WheelFeedback {
    @MainActor
    static func sliceChanged() {
        WheelTick.play()
        guard AppRuntime.shared.hapticOnWheel else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

/// A 20 ms decaying tick. Loud system sounds read as alerts; this stays under the interface.
private enum WheelTick {
    private static let clip: Data = makeWav()
    private static let player: AVAudioPlayer? = {
        let player = try? AVAudioPlayer(data: clip)
        player?.volume = 0.2
        player?.prepareToPlay()
        return player
    }()

    static func play() {
        guard let player else { return }
        if player.isPlaying { player.stop() }
        player.currentTime = 0
        player.play()
    }

    private static func makeWav() -> Data {
        let sampleRate = 44_100
        let count = 980
        var pcm = Data(count: count * 2)
        pcm.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for index in 0..<count {
                let time = Double(index) / Double(sampleRate)
                let click = sin(2 * .pi * 2400 * time) * exp(-time * 280)
                let body = sin(2 * .pi * 980 * time) * exp(-time * 140) * 0.35
                let wave = max(-1, min(1, (click * 0.55 + body) * 0.5))
                samples[index] = Int16(wave * 32_767)
            }
        }
        var data = Data()
        func ascii(_ value: String) { data.append(Data(value.utf8)) }
        func u32(_ value: UInt32) { var little = value.littleEndian; data.append(Data(bytes: &little, count: 4)) }
        func u16(_ value: UInt16) { var little = value.littleEndian; data.append(Data(bytes: &little, count: 2)) }
        ascii("RIFF")
        u32(UInt32(36 + pcm.count))
        ascii("WAVE")
        ascii("fmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))
        u16(2)
        u16(16)
        ascii("data")
        u32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}
