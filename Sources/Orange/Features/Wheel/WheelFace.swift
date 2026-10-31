import OrangeKit
import SwiftUI

enum WheelMetrics {
    static let size: CGFloat = 470
    static let outer: CGFloat = 214
    static let inner: CGFloat = 98
    static let gap: CGFloat = 7
    static let corner: CGFloat = 16

    static func layout(count: Int, in size: CGSize = CGSize(width: WheelMetrics.size, height: WheelMetrics.size)) -> WheelLayout {
        WheelLayout(
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            ringRadius: (outer + inner) / 2,
            innerRadius: inner - 6,
            outerRadius: outer + 40,
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
            GlassEffectContainer(spacing: 10) {
                ZStack {
                    ForEach(Array(session.choices.enumerated()), id: \.element.id) { index, _ in
                        let shape = WheelSegment(index: index, count: session.choices.count)
                        Color.clear
                            .frame(width: WheelMetrics.size, height: WheelMetrics.size)
                            .glassEffect(glass(for: index), in: shape)
                            .overlay {
                                shape.fill(LinearGradient(colors: [Color(hex: 0xFF8A3D), OrangeTheme.accentDeep], startPoint: .top, endPoint: .bottom))
                                    .opacity(index == highlight ? 1 : 0)
                            }
                            .overlay {
                                shape.stroke(
                                    LinearGradient(colors: [.white.opacity(index == highlight ? 0.7 : 0.38), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                                    lineWidth: 1
                                )
                            }
                    }
                    Color.clear
                        .frame(width: WheelMetrics.size, height: WheelMetrics.size)
                        .glassEffect(.regular.tint(.black.opacity(0.28)), in: Circle().inset(by: WheelMetrics.size / 2 - WheelMetrics.inner + 12))
                        .overlay {
                            Circle().inset(by: WheelMetrics.size / 2 - WheelMetrics.inner + 12)
                                .stroke(.white.opacity(0.22), lineWidth: 1)
                        }
                }
            }
            .shadow(color: .black.opacity(0.28), radius: 24, y: 10)

            ForEach(Array(session.choices.enumerated()), id: \.element.id) { index, choice in
                let selected = index == highlight
                VStack(spacing: 6) {
                    Image(systemName: choice.symbol)
                        .font(.system(size: 22, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                    Text(choice.title.uppercased(with: .current))
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white.opacity(selected ? 1 : 0.92))
                .shadow(color: .black.opacity(selected ? 0.2 : 0.35), radius: 2, y: 1)
                .frame(width: 84)
                .scaleEffect(selected ? 1.12 : 1)
                .position(layout.point(for: index))
            }

            WheelCenter(session: session)
        }
        .frame(width: WheelMetrics.size, height: WheelMetrics.size)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: highlight)
    }

    private func glass(for index: Int) -> Glass {
        index == highlight ? .regular.tint(OrangeTheme.accent).interactive() : .regular.tint(.black.opacity(0.34)).interactive()
    }
}

struct WheelCenter: View {
    var session: WheelSession

    var body: some View {
        VStack(spacing: 7) {
            Label(session.mode.title.uppercased(with: .current), systemImage: session.mode.symbol)
                .font(.system(size: 9.5, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(OrangeTheme.ember)
            ZStack(alignment: .topTrailing) {
                if let first = session.files.first {
                    FileThumbnail(url: first.url, side: 66, radius: 12)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }
                if session.files.count > 1 {
                    Text("\(session.files.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(OrangeTheme.accent, in: Capsule())
                        .offset(x: 8, y: -6)
                }
            }
            Text(ByteCountFormatter.string(fromByteCount: session.files.reduce(0) { $0 + $1.byteCount }, countStyle: .file))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .glassEffect(.regular, in: Capsule())
        }
        .frame(width: WheelMetrics.inner * 2 - 24)
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
                        if index != highlight, index != nil, runtime.hapticOnWheel {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
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
        highlight = ((highlight ?? (delta > 0 ? -1 : 0)) + delta + count) % count
        return .handled
    }
}
