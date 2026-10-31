import AppKit
import OrangeKit
import SwiftUI

enum WheelMetrics {
    static let size: CGFloat = 440
    static let ring: CGFloat = 150
    static let inner: CGFloat = 78
    static let outer: CGFloat = 214
}

struct WheelFace: View {
    var session: WheelSession
    var highlight: Int?
    var interactive: Bool
    var onHighlight: (Int) -> Void
    var onCommit: (Int) -> Void

    private var layout: WheelLayout {
        WheelLayout(
            center: CGPoint(x: WheelMetrics.size / 2, y: WheelMetrics.size / 2),
            ringRadius: WheelMetrics.ring,
            innerRadius: WheelMetrics.inner,
            outerRadius: WheelMetrics.outer,
            count: session.choices.count
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 392, height: 392)
                .overlay(Circle().strokeBorder(OrangeTheme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 30, y: 16)

            Circle()
                .strokeBorder(OrangeTheme.line, lineWidth: 1)
                .frame(width: WheelMetrics.ring * 2, height: WheelMetrics.ring * 2)

            centerDisc

            ForEach(Array(session.choices.enumerated()), id: \.element.id) { index, choice in
                bubble(choice, selected: highlight == index)
                    .position(layout.point(for: index))
                    .onHover { inside in
                        guard interactive, inside else { return }
                        onHighlight(index)
                    }
                    .onTapGesture {
                        guard interactive else { return }
                        onCommit(index)
                    }
                    .allowsHitTesting(interactive)
            }
        }
        .frame(width: WheelMetrics.size, height: WheelMetrics.size)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: highlight)
    }

    private var centerDisc: some View {
        VStack(spacing: 4) {
            Text(Copy.modeTitle(session.mode).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(OrangeTheme.muted)
            Text(centerTitle)
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(OrangeTheme.ink)
                .lineLimit(2)
            Text(Copy.count(session.files.count))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(OrangeTheme.muted)
        }
        .padding(12)
        .frame(width: 132, height: 132)
        .background(Circle().fill(OrangeTheme.card))
        .overlay(Circle().strokeBorder(OrangeTheme.line, lineWidth: 1))
    }

    private var centerTitle: String {
        if let highlight, session.choices.indices.contains(highlight) {
            return session.choices[highlight].title
        }
        return session.files.count == 1 ? session.files[0].name : Copy.modeTitle(session.mode)
    }

    private func bubble(_ choice: WheelChoice, selected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: choice.symbol)
                .font(.system(size: 14, weight: .semibold))
            Text(choice.title)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(selected ? Color.white : OrangeTheme.ink)
        .frame(width: 78, height: 58)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selected ? AnyShapeStyle(OrangeTheme.accent) : AnyShapeStyle(OrangeTheme.card))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? Color.white.opacity(0.25) : OrangeTheme.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(selected ? 0.2 : 0.08), radius: selected ? 14 : 8, y: 6)
        .scaleEffect(selected ? 1.06 : 1)
    }
}

struct WheelOverlay: View {
    @Environment(AppRuntime.self) private var runtime
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.28))
                .ignoresSafeArea()
                .onTapGesture { runtime.localWheel = nil }
            if let session = runtime.localWheel {
                VStack(spacing: 16) {
                    WheelFace(
                        session: session,
                        highlight: runtime.localHighlight,
                        interactive: true,
                        onHighlight: { runtime.localHighlight = $0 },
                        onCommit: { index in
                            guard session.choices.indices.contains(index) else { return }
                            runtime.commit(choice: session.choices[index], files: session.files)
                        }
                    )
                    Text(Copy.wheelHelp)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.86))
                }
            }
        }
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.escape) {
            runtime.localWheel = nil
            return .handled
        }
        .onKeyPress(.return) {
            runtime.commitLocalHighlight()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            runtime.nudgeLocalHighlight(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            runtime.nudgeLocalHighlight(1)
            return .handled
        }
        .onExitCommand { runtime.localWheel = nil }
    }
}

struct GlobalWheelHost: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        if let session = runtime.globalWheel {
            WheelFace(
                session: session,
                highlight: runtime.globalHighlight,
                interactive: false,
                onHighlight: { _ in },
                onCommit: { _ in }
            )
        } else {
            Color.clear
        }
    }
}

@MainActor
final class WheelPanelController {
    private var panel: NSPanel?
    var frame: CGRect? { panel?.frame }

    func show() {
        let panel = self.panel ?? make()
        self.panel = panel
        let mouse = NSEvent.mouseLocation
        let size = WheelMetrics.size
        var origin = CGPoint(x: mouse.x - size / 2, y: mouse.y - size / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size - 8)
        }
        panel.setFrame(CGRect(origin: origin, size: CGSize(width: size, height: size)), display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func make() -> NSPanel {
        let size = WheelMetrics.size
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        let host = NSHostingView(rootView: GlobalWheelHost().environment(AppRuntime.shared))
        host.frame = NSRect(x: 0, y: 0, width: size, height: size)
        panel.contentView = host
        return panel
    }
}

@MainActor
final class DragWheelMonitor {
    static let shared = DragWheelMonitor()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var tracking = false
    private var cached: [URL] = []
    private let panel = WheelPanelController()

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp, .flagsChanged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated {
                DragWheelMonitor.shared.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated {
                DragWheelMonitor.shared.handle(event)
            }
            return event
        }
        AppRuntime.shared.globalMonitorAvailable = globalMonitor != nil
    }

    private func handle(_ event: NSEvent) {
        let runtime = AppRuntime.shared
        if runtime.localWheel != nil {
            end()
            return
        }
        switch event.type {
        case .leftMouseUp:
            if tracking { commit() }
            end()
        case .leftMouseDragged:
            follow(event)
        case .flagsChanged where tracking:
            if mode(from: event.modifierFlags) == nil {
                end()
            } else {
                follow(event)
            }
        default:
            break
        }
    }

    private func follow(_ event: NSEvent) {
        guard NSEvent.pressedMouseButtons & 1 == 1 else { return }
        let flags = event.modifierFlags.union(NSEvent.modifierFlags)
        guard let wheelMode = mode(from: flags) else { return }
        let found = readDragURLs()
        if !found.isEmpty { cached = found }
        guard !cached.isEmpty else { return }
        tracking = true
        let runtime = AppRuntime.shared
        panel.show()
        runtime.updateGlobalWheel(files: cached, mode: wheelMode, highlight: nil)
        runtime.updateGlobalWheel(files: cached, mode: wheelMode, highlight: highlight())
    }

    private func commit() {
        let runtime = AppRuntime.shared
        guard let session = runtime.globalWheel,
              let index = runtime.globalHighlight,
              session.choices.indices.contains(index) else { return }
        runtime.commit(choice: session.choices[index], files: session.files)
    }

    private func end() {
        tracking = false
        cached = []
        AppRuntime.shared.clearGlobalWheel()
        panel.hide()
    }

    private func highlight() -> Int? {
        guard let session = AppRuntime.shared.globalWheel, let frame = panel.frame else { return nil }
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        let layout = WheelLayout(
            center: CGPoint(x: WheelMetrics.size / 2, y: WheelMetrics.size / 2),
            ringRadius: WheelMetrics.ring,
            innerRadius: WheelMetrics.inner,
            outerRadius: WheelMetrics.outer,
            count: session.choices.count
        )
        return layout.index(at: local)
    }

    private func mode(from flags: NSEvent.ModifierFlags) -> WheelMode? {
        if flags.contains(.control) { return .actions }
        if flags.contains(.command) { return .tools }
        if flags.contains(.shift) { return .convert }
        return nil
    }

    private func readDragURLs() -> [URL] {
        let pasteboard = NSPasteboard(name: .drag)
        var urls: [URL] = []
        if let items = pasteboard.pasteboardItems {
            for item in items {
                if let value = item.string(forType: .fileURL), let url = URL(string: value), url.isFileURL {
                    urls.append(url)
                }
            }
        }
        if urls.isEmpty, let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            urls = objects.filter(\.isFileURL)
        }
        return urls
    }
}
