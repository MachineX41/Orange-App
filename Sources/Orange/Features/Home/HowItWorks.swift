import OrangeKit
import SwiftUI

/// Looping demo of the drag wheel: drag, hold a key, drop on a slice. Cycles through the three wheels
/// until the user picks one.
struct HowItWorks: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var pinned: WheelMode?

    static let period: Double = 4.6

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(title: L("How it works", "Nasıl çalışır"), symbol: "hand.draw")
                Spacer()
                Button {
                    runtime.showShortcuts = true
                } label: {
                    HStack(spacing: 6) {
                        Text(L("All shortcuts", "Tüm kısayollar"))
                        KeyCombo(keys: ["⌘", "/"])
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let progress = reduceMotion ? 0.6 : (time.truncatingRemainder(dividingBy: Self.period)) / Self.period
                let cycle = Int(time / Self.period) % WheelMode.allCases.count
                let mode = pinned ?? WheelMode.allCases[reduceMotion ? 0 : cycle]
                HStack(alignment: .center, spacing: 18) {
                    WheelDemo(mode: mode, progress: progress)
                        .frame(width: 250, height: 190)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(WheelMode.allCases, id: \.self) { item in
                            row(item, active: item == mode)
                        }
                        Text(pinned == nil
                             ? L("Pick a wheel to pin the demo.", "Demoyu sabitlemek için bir çark seçin.")
                             : L("Click again to resume the tour.", "Tura devam etmek için tekrar tıklayın."))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 4)
                    }
                }
            }
            .padding(16)
            .glassCard(radius: 22)
        }
    }

    private func row(_ mode: WheelMode, active: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                pinned = pinned == mode ? nil : mode
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                KeyCap(text: mode.key, pressed: active)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mode.title).font(.system(size: 13.5, weight: .semibold))
                        if pinned == mode {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(mode.explanation)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("In window", "Pencerede"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(mode.menuKeyText)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(active ? 0.06 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.25), value: active)
    }
}

/// One frame of the guide animation, driven by `progress` in 0...1.
struct WheelDemo: View {
    var mode: WheelMode
    var progress: Double

    private let outer: CGFloat = 64
    private let inner: CGFloat = 27
    private let target = 1

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2 - 4)
            let count = mode.sampleSymbols.count
            let slice = 2 * CGFloat.pi / CGFloat(count)
            let targetAngle = -CGFloat.pi / 2 + CGFloat(target) * slice
            let targetPoint = CGPoint(
                x: center.x + cos(targetAngle) * (outer + inner) / 2,
                y: center.y + sin(targetAngle) * (outer + inner) / 2
            )
            let start = CGPoint(x: size.width * 0.12, y: size.height * 0.82)

            let reach = ease(range(0.04, 0.26))
            let wheelIn = ease(range(0.28, 0.38))
            let wheelOut = ease(range(0.86, 0.94))
            let wheelVisible = wheelIn * (1 - wheelOut)
            let toSlice = ease(range(0.42, 0.62))
            let drop = ease(range(0.68, 0.76))
            let done = range(0.76, 0.82) * (1 - range(0.92, 0.99))
            let holding = progress > 0.27 && progress < 0.86
            let highlighted = progress > 0.56 && progress < 0.8

            let filePoint = mix(mix(start, center, reach), targetPoint, toSlice)

            ZStack {
                ZStack {
                    ForEach(0..<count, id: \.self) { index in
                        WheelSegment(index: index, count: count, inner: inner, outer: outer, gap: 3, corner: 6)
                            .fill(index == target && highlighted ? OrangeTheme.accent : Color(white: 0.36).opacity(0.92))
                            .frame(width: outer * 2, height: outer * 2)
                            .position(center)
                        let angle = -CGFloat.pi / 2 + CGFloat(index) * slice
                        Image(systemName: mode.sampleSymbols[index])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .position(
                                x: center.x + cos(angle) * (outer + inner) / 2,
                                y: center.y + sin(angle) * (outer + inner) / 2
                            )
                    }
                }
                .frame(width: size.width, height: size.height)
                .scaleEffect(0.82 + 0.18 * wheelVisible, anchor: UnitPoint(x: center.x / size.width, y: center.y / size.height))
                .opacity(wheelVisible)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, OrangeTheme.accent)
                    .scaleEffect(0.6 + 0.4 * done)
                    .opacity(done)
                    .position(center)

                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white)
                        .frame(width: 26, height: 32)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 11))
                                .foregroundStyle(OrangeTheme.accent)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .offset(x: 10, y: 12)
                }
                .scaleEffect(1 - 0.7 * drop)
                .opacity(1 - drop)
                .position(filePoint)

                KeyCap(text: mode.key, pressed: holding)
                    .position(x: 26, y: 22)
                    .animation(.easeOut(duration: 0.15), value: holding)

                stepLabel
                    .position(x: size.width / 2, y: size.height - 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var stepLabel: some View {
        let step = progress < 0.27 ? 0 : (progress < 0.62 ? 1 : 2)
        let titles = [
            L("Drag a file", "Dosyayı sürükleyin"),
            L("Hold \(mode.key)", "\(mode.key) basılı tutun"),
            L("Drop on a slice", "Bir dilime bırakın")
        ]
        return HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == step ? OrangeTheme.accent : Color.primary.opacity(0.15))
                    .frame(width: index == step ? 14 : 5, height: 5)
            }
            Text(titles[step])
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .transaction { $0.animation = nil }
        }
        .animation(.easeOut(duration: 0.2), value: step)
    }

    private func range(_ lower: Double, _ upper: Double) -> Double {
        min(1, max(0, (progress - lower) / (upper - lower)))
    }

    private func ease(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }

    private func mix(_ a: CGPoint, _ b: CGPoint, _ amount: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount)
    }
}
