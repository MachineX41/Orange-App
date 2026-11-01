import AppKit
import OrangeKit
import SwiftUI

/// Always-on-top shelf for parking files while moving between apps. One liquid-glass vessel, like the drop container.
/// Reaching the top or bottom edge turns it into a horizontal bar; pulling away restores the column.
@MainActor
@Observable
final class FloatShelf {
    static let shared = FloatShelf()
    /// Same width in both poses. Only the height eases, so the shelf never stretches sideways.
    fileprivate static let width: CGFloat = 132
    fileprivate static let columnHeight: CGFloat = 460
    fileprivate static let barHeight: CGFloat = 112
    fileprivate static var verticalSize: NSSize { NSSize(width: width, height: columnHeight) }
    fileprivate static var horizontalSize: NSSize { NSSize(width: width, height: barHeight) }
    fileprivate static let radius: CGFloat = 30
    /// How close the column must get before it docks, and how far the pointer must then travel to release it.
    private static let dockDistance: CGFloat = 18
    private static let undockDistance: CGFloat = 64

    private enum Edge { case top, bottom }

    private var panelStorage: NSPanel?
    /// Card and button frames, in the shelf’s top-left coordinates, that must keep their own click or file drag.
    fileprivate var interactiveFrames: [CGRect] = []
    private var magnet: Edge?
    /// Pointer position when the shelf latched to an edge. Pulling inward from here releases it.
    private var magnetAnchorY: CGFloat = 0
    /// After undocking, ignore a new dock until the column is clearly clear of that edge.
    private var releaseGuard: Edge?
    private(set) var horizontal = false
    /// Animated height. Width never changes, so the morph is one continuous motion.
    private(set) var span: CGFloat = columnHeight
    private var shelfHeight: CGFloat = columnHeight
    private var heightTarget: CGFloat = columnHeight
    private var morphFrom: CGFloat = columnHeight
    private var morphStart = CACurrentMediaTime() - 10
    private let morphDuration: CFTimeInterval = 0.72
    private var lastMouse: NSPoint?
    private var lastGrab = CGPoint(x: 0.5, y: 0.5)
    private var pointerDown = false
    private var timer: Timer?

    private var panel: NSPanel {
        if let panelStorage { return panelStorage }
        let created = makePanel()
        panelStorage = created
        return created
    }

    private func defaultOrigin() -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else { return NSPoint(x: 40, y: 80) }
        return NSPoint(x: visible.maxX - Self.verticalSize.width - 18, y: visible.midY - Self.verticalSize.height / 2)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: defaultOrigin(), size: Self.verticalSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = ShelfHost(
            rootView: FloatShelfView()
                .environment(AppRuntime.shared)
                .tint(OrangeTheme.accent)
        )
        host.sizingOptions = []
        host.wantsLayer = true
        host.layer?.isOpaque = false
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host
        if panel.setFrameAutosaveName("OrangeFloatingShelf") {
            let resolved = resolvedFrame(panel.frame)
            horizontal = resolved.horizontal
            magnet = resolved.edge
            magnetAnchorY = resolved.anchorY
            shelfHeight = resolved.frame.height
            heightTarget = resolved.frame.height
            span = resolved.frame.height
            panel.setFrame(resolved.frame, display: false)
        }
        apply(AppRuntime.shared.appearance, to: panel)
        return panel
    }

    /// Glass follows the app theme, including System when the Mac switches on its own.
    func applyAppearance() {
        guard let panelStorage else { return }
        apply(AppRuntime.shared.appearance, to: panelStorage)
    }

    private func apply(_ choice: AppearanceChoice, to panel: NSPanel) {
        let appearance: NSAppearance? = switch choice {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        panel.appearance = appearance
        panel.contentView?.appearance = appearance
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        panel.title = L("Shelf", "Raf")
        applyAppearance()
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
    func toggle() { isVisible ? hide() : show() }

    /// Follows the pointer. The column becomes a bar when it reaches the top or bottom edge.
    fileprivate func drag(to mouse: NSPoint, grab: CGPoint) {
        guard panelStorage != nil else { return }
        let screen = screen(at: mouse) ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let natural = NSRect(
            x: mouse.x - grab.x * Self.verticalSize.width,
            y: mouse.y - grab.y * Self.verticalSize.height,
            width: Self.verticalSize.width,
            height: Self.verticalSize.height
        )

        if let guardEdge = releaseGuard {
            let gap: CGFloat = switch guardEdge {
            case .top: visible.maxY - natural.maxY
            case .bottom: natural.minY - visible.minY
            }
            if gap > 40 { releaseGuard = nil }
        }

        var next = magnet
        switch magnet {
        case nil:
            if releaseGuard == nil {
                if visible.maxY - natural.maxY <= Self.dockDistance {
                    next = .top
                    magnetAnchorY = mouse.y
                } else if natural.minY - visible.minY <= Self.dockDistance {
                    next = .bottom
                    magnetAnchorY = mouse.y
                }
            }
        case .top:
            if mouse.y < magnetAnchorY - Self.undockDistance {
                next = nil
                releaseGuard = .top
            }
        case .bottom:
            if mouse.y > magnetAnchorY + Self.undockDistance {
                next = nil
                releaseGuard = .bottom
            }
        }

        magnet = next
        pointerDown = true
        lastMouse = mouse
        lastGrab = grab
        let target = next == nil ? Self.columnHeight : Self.barHeight
        if heightTarget != target {
            morphFrom = shelfHeight
            morphStart = CACurrentMediaTime()
            heightTarget = target
            horizontal = next != nil
        }
        ensureTimer()
        tick()
    }

    fileprivate func dragEnded() {
        pointerDown = false
        tick()
    }

    /// Zero slope at both ends, so the shelf eases out of one pose and into the other without a hitch.
    private func tick() {
        let elapsed = CACurrentMediaTime() - morphStart
        let t = min(1, max(0, elapsed / morphDuration))
        let x = CGFloat(t)
        let eased = x * x * x * (x * (x * 6 - 15) + 10)
        shelfHeight = morphFrom + (heightTarget - morphFrom) * eased
        if t >= 1 { shelfHeight = heightTarget }
        span = shelfHeight
        applyFrame()
        if !pointerDown, shelfHeight == heightTarget {
            stopTimer()
        }
    }

    private func applyFrame() {
        guard let panel = panelStorage, let mouse = lastMouse else { return }
        let height = shelfHeight
        var origin = NSPoint(x: mouse.x - lastGrab.x * Self.width, y: mouse.y - lastGrab.y * height)
        if let screen = screen(at: mouse) ?? panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let inset: CGFloat = 8
            switch magnet {
            case .top:
                origin.y = visible.maxY - inset - height
            case .bottom:
                origin.y = visible.minY + inset
            case nil:
                let low = visible.minY - 12
                let high = max(low, visible.maxY - height + 12)
                origin.y = min(max(origin.y, low), high)
            }
            let minX = visible.minX + inset
            let maxX = max(minX, visible.maxX - Self.width - inset)
            origin.x = min(max(origin.x, minX), maxX)
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: Self.width, height: height), display: true)
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            MainActor.assumeIsolated { FloatShelf.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func frame(for edge: Edge?, mouse: NSPoint, natural: NSRect, visible: NSRect) -> NSRect {
        guard let edge else {
            guard let guardEdge = releaseGuard else { return natural }
            var parked = natural
            switch guardEdge {
            case .top:
                parked.origin.y = min(parked.origin.y, visible.maxY - Self.verticalSize.height - 48)
            case .bottom:
                parked.origin.y = max(parked.origin.y, visible.minY + 48)
            }
            return parked
        }
        let size = Self.horizontalSize
        let inset: CGFloat = 8
        let low = visible.minX + inset
        let high = max(low, visible.maxX - size.width - inset)
        return NSRect(
            x: min(max(mouse.x - size.width / 2, low), high),
            y: edge == .top ? visible.maxY - size.height - inset : visible.minY + inset,
            width: size.width,
            height: size.height
        )
    }

    private func resolvedFrame(_ saved: NSRect) -> (horizontal: Bool, edge: Edge?, anchorY: CGFloat, frame: NSRect) {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(saved.insetBy(dx: 20, dy: 20)) }) else {
            return (false, nil, 0, NSRect(origin: defaultOrigin(), size: Self.verticalSize))
        }
        let visible = screen.visibleFrame
        let topGap = visible.maxY - saved.maxY
        let bottomGap = saved.minY - visible.minY
        let edge: Edge? = if topGap <= 28, topGap <= bottomGap {
            .top
        } else if bottomGap <= 28 {
            .bottom
        } else {
            nil
        }
        guard let edge else {
            var frame = saved
            frame.size = Self.verticalSize
            return (false, nil, 0, frame)
        }
        let mouse = NSPoint(x: saved.midX, y: edge == .top ? visible.maxY : visible.minY)
        let anchor = edge == .top ? visible.maxY : visible.minY
        return (true, edge, anchor, frame(for: edge, mouse: mouse, natural: saved, visible: visible))
    }

    private func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}

struct FloatShelfView: View {
    @Environment(AppRuntime.self) private var runtime
    @State var targeted = false

    var body: some View {
        let horizontal = FloatShelf.shared.horizontal
        let shape = RoundedRectangle(cornerRadius: FloatShelf.radius, style: .continuous)
        ZStack {
            column
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.shelfHits, !horizontal)
                .opacity(horizontal ? 0 : 1)
                .allowsHitTesting(!horizontal)
            bar
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.shelfHits, horizontal)
                .opacity(horizontal ? 1 : 0)
                .allowsHitTesting(horizontal)
        }
        .animation(.smooth(duration: 0.6), value: horizontal)
        .padding(10)
        .frame(width: FloatShelf.width, height: FloatShelf.shared.span)
        .glassEffect(.clear, in: shape)
        .coordinateSpace(name: "shelf")
        .preferredColorScheme(runtime.appearance.colorScheme)
        .onPreferenceChange(ShelfInteractiveFrames.self) { FloatShelf.shared.interactiveFrames = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.compactMap(FileRef.load)
            for file in files where !runtime.shelf.contains(file) { runtime.shelf.insert(file, at: 0) }
            runtime.perform(.float, files: [])
            return !files.isEmpty
        } isTargeted: { targeted = $0 }
    }

    private var column: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                trayIcon
                Spacer(minLength: 0)
                closeButton
            }
            if runtime.shelf.isEmpty {
                empty
            } else {
                VStack(spacing: 8) {
                    ScrollView { fileStack(.vertical) }
                        .scrollIndicators(.never)
                    clearButton
                }
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            VStack(spacing: 5) {
                trayIcon
                closeButton
                if !runtime.shelf.isEmpty {
                    Button {
                        runtime.clearShelf()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.glass).tint(nil)
                    .buttonBorderShape(.circle)
                    .controlSize(.mini)
                    .shelfInteractive()
                }
            }
            .fixedSize()
            if runtime.shelf.isEmpty {
                emptyBar
            } else {
                ScrollView(.horizontal) { fileStack(.horizontal) }
                    .scrollIndicators(.never)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var trayIcon: some View {
        Image(systemName: "tray.full")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var closeButton: some View {
        Button {
            FloatShelf.shared.hide()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
        }
        .buttonStyle(.glass).tint(nil)
        .buttonBorderShape(.circle)
        .controlSize(.mini)
        .shelfInteractive()
    }

    private var clearButton: some View {
        Button(L("Clear", "Temizle")) { runtime.clearShelf() }
            .buttonStyle(.glass).tint(nil)
            .controlSize(.small)
            .fixedSize()
            .shelfInteractive()
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)
            Text(L("Drop files here", "Dosyaları buraya bırakın"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 16, weight: .light))
            Text(L("Drop files here", "Dosyaları buraya bırakın"))
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileStack(_ axis: Axis) -> some View {
        let stack = ForEach(runtime.shelf) { file in
            VStack(spacing: 4) {
                FileThumbnail(url: file.url, side: axis == .vertical ? 72 : 52, radius: 12)
                Text(file.name)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: axis == .vertical ? .infinity : nil)
            .frame(width: axis == .horizontal ? 76 : nil)
            .shelfInteractive()
            .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
            .contextMenu {
                Button(L("Use as Input", "Girdi Olarak Kullan")) { runtime.importURLs([file.url]) }
                Button(L("Reveal in Finder", "Finder’da Göster")) {
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                }
                Button(L("Remove", "Kaldır")) { runtime.removeFromShelf(file) }
            }
        }
        return Group {
            if axis == .vertical {
                VStack(spacing: 8) { stack }.padding(1)
            } else {
                HStack(spacing: 8) { stack }.padding(1)
            }
        }
    }
}

/// A click outside a card or button drags the shelf itself. Cards keep their file drag.
private final class ShelfHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let point = isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
        let interactive = MainActor.assumeIsolated { FloatShelf.shared.interactiveFrames }
        if interactive.contains(where: { $0.insetBy(dx: -3, dy: -3).contains(point) }) {
            super.mouseDown(with: event)
            return
        }
        guard let window else { return }
        let grab = CGPoint(
            x: min(max(event.locationInWindow.x / max(window.frame.width, 1), 0), 1),
            y: min(max(event.locationInWindow.y / max(window.frame.height, 1), 0), 1)
        )
        while window.isVisible {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }
            if next.type == .leftMouseUp { break }
            MainActor.assumeIsolated {
                FloatShelf.shared.drag(to: NSEvent.mouseLocation, grab: grab)
            }
        }
        MainActor.assumeIsolated { FloatShelf.shared.dragEnded() }
    }
}

private struct ShelfInteractiveFrames: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ShelfHitsKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var shelfHits: Bool {
        get { self[ShelfHitsKey.self] }
        set { self[ShelfHitsKey.self] = newValue }
    }
}

private struct ShelfInteractive: ViewModifier {
    @Environment(\.shelfHits) private var hits

    func body(content: Content) -> some View {
        content.background {
            if hits {
                GeometryReader { proxy in
                    Color.clear.preference(key: ShelfInteractiveFrames.self, value: [proxy.frame(in: .named("shelf"))])
                }
            }
        }
    }
}

private extension View {
    func shelfInteractive() -> some View {
        modifier(ShelfInteractive())
    }
}
