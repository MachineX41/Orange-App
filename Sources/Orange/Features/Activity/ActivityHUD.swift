import AppKit
import OrangeKit
import SwiftUI

/// Floating glass notifications for running jobs and results, visible from any app.
@MainActor
final class ActivityHUD {
    static let shared = ActivityHUD()

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: ActivityStack().environment(AppRuntime.shared))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }()

    func refresh() {
        let runtime = AppRuntime.shared
        let empty = runtime.running.isEmpty && runtime.toasts.isEmpty
        if empty {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                let runtime = AppRuntime.shared
                if runtime.running.isEmpty && runtime.toasts.isEmpty { self.panel.orderOut(nil) }
            }
            return
        }
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 12, y: frame.maxY - panel.frame.height - 8))
        panel.orderFrontRegardless()
    }
}

struct ActivityStack: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(runtime.running) { job in
                JobToast(job: job, progress: runtime.progress[job.id] ?? 0)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ForEach(runtime.toasts) { toast in
                ResultToast(toast: toast)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 360, height: 420, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: runtime.toasts)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: runtime.running)
    }
}

struct JobToast: View {
    var job: JobRecord
    var progress: Double

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 3)
                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(OrangeTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.2), value: progress)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                        let angle = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1) * 360
                        Circle()
                            .trim(from: 0, to: 0.28)
                            .stroke(OrangeTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(angle - 90))
                    }
                }
                Image(systemName: job.symbol)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(job.detail).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if AppRuntime.shared.canCancel(job.id) {
                Button(L("Cancel", "İptal")) {
                    AppRuntime.shared.cancelJob(job.id)
                }
                .buttonStyle(.glass).tint(nil)
                .controlSize(.small)
                .accessibilityLabel(L("Cancel", "İptal"))
            } else {
                Text(progressLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: progressLabel)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: 330)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var progressLabel: String {
        guard progress > 0 else { return "…" }
        let percent = progress * 100
        if percent < 10 { return String(format: "%.1f%%", percent) }
        return "\(Int(percent.rounded()))%"
    }
}

struct ResultToast: View {
    @Environment(AppRuntime.self) private var runtime
    var toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(toast.message).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 0)
            if !toast.outputs.isEmpty {
                Button(L("Show", "Göster")) {
                    NSWorkspace.shared.activateFileViewerSelecting(toast.outputs)
                    runtime.dismiss(toast)
                }
                .buttonStyle(.glass).tint(nil)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: 330)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onDrag {
            NSItemProvider(contentsOf: toast.outputs.first) ?? NSItemProvider()
        }
        .onTapGesture { runtime.dismiss(toast) }
    }

    private var color: Color {
        switch toast.style {
        case .success: .green
        case .failure: OrangeTheme.ember
        case .info: OrangeTheme.accent
        }
    }
}
