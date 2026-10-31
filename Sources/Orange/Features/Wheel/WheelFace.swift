import AVFoundation
import OrangeKit
import SwiftUI

enum WheelMetrics {
    static let size: CGFloat = 308
    static let outer: CGFloat = 142
    static let inner: CGFloat = 58
    static let gap: CGFloat = 4
    static let corner: CGFloat = 12

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
        guard count > 1 else { return annulus(center: center) }

        let slice = 2 * CGFloat.pi / CGFloat(count)
        let mid = -CGFloat.pi / 2 + CGFloat(index) * slice
        let gapAngle = gap / ((inner + outer) / 2)
        let start = mid - slice / 2 + gapAngle / 2
        let end = mid + slice / 2 - gapAngle / 2
        let span = max(0.05, end - start)
        let insetOuter = min(corner / outer, span * 0.32)
        let insetInner = min(corner / inner, span * 0.32)

        func point(_ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }

        var path = Path()
        path.move(to: point(outer, start + insetOuter))
        path.addArc(
            center: center,
            radius: outer,
            startAngle: .radians(start + insetOuter),
            endAngle: .radians(end - insetOuter),
            clockwise: false
        )
        path.addQuadCurve(to: point(outer - corner, end), control: point(outer, end))
        path.addLine(to: point(inner + corner, end))
        path.addQuadCurve(to: point(inner, end - insetInner), control: point(inner, end))
        path.addArc(
            center: center,
            radius: inner,
            startAngle: .radians(end - insetInner),
            endAngle: .radians(start + insetInner),
            clockwise: true
        )
        path.addQuadCurve(to: point(inner + corner, start), control: point(inner, start))
        path.addLine(to: point(outer - corner, start))
        path.addQuadCurve(to: point(outer, start + insetOuter), control: point(outer, start))
        path.closeSubpath()
        return path
    }

    private func annulus(center: CGPoint) -> Path {
        let outerCircle = Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        let innerCircle = Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
        return outerCircle.subtracting(innerCircle)
    }
}

struct WheelFace: View {
    var session: WheelSession
    var highlight: Int?

    private var layout: WheelLayout { WheelMetrics.layout(count: session.choices.count) }

    var body: some View {
        ZStack {
            ZStack {
                ForEach(Array(session.choices.enumerated()), id: \.element.id) { index, _ in
                    let shape = WheelSegment(index: index, count: session.choices.count)
                    shape
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: WheelMetrics.size, height: WheelMetrics.size)
                        .glassEffect(.regular, in: shape)
                        .overlay {
                            shape
                                .fill(OrangeTheme.accent)
                                .opacity(index == highlight ? 1 : 0)
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

/// A dry 12 ms snap. The old tick had a low tail; this one is only the attack.
private enum WheelTick {
    private static let clip: Data = makeWav()
    private static let player: AVAudioPlayer? = {
        let player = try? AVAudioPlayer(data: clip)
        player?.volume = 0.32
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
        let count = 520
        var pcm = Data(count: count * 2)
        pcm.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for index in 0..<count {
                let time = Double(index) / Double(sampleRate)
                let burst = (Self.noise(index) * 2 - 1) * exp(-time * 1100)
                let snap = sin(2 * .pi * 4800 * time) * exp(-time * 650)
                let wave = max(-1, min(1, burst * 0.72 + snap * 0.4))
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

    private static func noise(_ index: Int) -> Double {
        let value = sin(Double(index) * 12.9898) * 43758.5453
        return value - floor(value)
    }
}
