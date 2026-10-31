import AppKit
import OrangeKit
import SwiftUI

/// A borderless panel that stays where it opened so the file can be dragged onto a slice.
@MainActor
final class GlobalWheel {
    static let shared = GlobalWheel()

    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?

    var isVisible: Bool { panel.isVisible }

    private init() {
        let size = NSSize(width: WheelMetrics.size, height: WheelMetrics.size)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let host = NSHostingView(rootView: GlobalWheelView().environment(AppRuntime.shared))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        host.sizingOptions = []
        let drop = WheelDropView(frame: container.bounds)
        drop.autoresizingMask = [.width, .height]
        container.addSubview(host)
        container.addSubview(drop)
        panel.contentView = container
    }

    func show(at screenPoint: NSPoint) {
        hideTask?.cancel()
        let size = panel.frame.size
        var origin = NSPoint(x: screenPoint.x - size.width / 2, y: screenPoint.y - size.height / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(screenPoint, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide(after delay: Double = 0) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            AppRuntime.shared.globalWheel = nil
            AppRuntime.shared.globalHighlight = nil
        }
    }
}

struct GlobalWheelView: View {
    @Environment(AppRuntime.self) private var runtime
    @State var appeared = false

    var body: some View {
        ZStack {
            if let session = runtime.globalWheel {
                WheelFace(session: session, highlight: runtime.globalHighlight)
                    .scaleEffect(appeared ? 1 : 0.84)
                    .opacity(appeared ? 1 : 0)
                    .onAppear {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.76)) { appeared = true }
                    }
                    .onDisappear { appeared = false }
                    .id(session.signature)
            }
        }
        .frame(width: WheelMetrics.size, height: WheelMetrics.size)
    }
}

/// Transparent drop target laid over the wheel. Highlights the slice under the cursor and commits on drop.
final class WheelDropView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    private func index(for sender: NSDraggingInfo) -> Int? {
        let point = convert(sender.draggingLocation, from: nil)
        guard let session = AppRuntime.shared.globalWheel else { return nil }
        return WheelMetrics.layout(count: session.choices.count, in: bounds.size).index(at: point)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let index = index(for: sender)
        AppRuntime.shared.setGlobalHighlight(index)
        return index == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        AppRuntime.shared.setGlobalHighlight(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        index(for: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let runtime = AppRuntime.shared
        guard let session = runtime.globalWheel, let index = index(for: sender), session.choices.indices.contains(index) else {
            return false
        }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let files = urls.compactMap(FileRef.load)
        let choice = session.choices[index]
        DragWatcher.shared.didDrop()
        GlobalWheel.shared.hide()
        DispatchQueue.main.async {
            runtime.commit(choice, files: files.isEmpty ? session.files : files)
        }
        return true
    }
}

/// Watches system-wide file drags without Accessibility permission.
/// Shift opens Convert, Command opens Tools and Control opens Actions while a drag is in flight.
@MainActor
final class DragWatcher {
    static let shared = DragWatcher()

    private var timer: Timer?
    private var baseline = NSPasteboard(name: .drag).changeCount
    private var dragging = false
    private var files: [FileRef] = []
    private var mode: WheelMode?

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
            MainActor.assumeIsolated { DragWatcher.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func didDrop() {
        mode = nil
    }

    private func tick() {
        let board = NSPasteboard(name: .drag)
        let mouseDown = NSEvent.pressedMouseButtons & 1 == 1
        guard mouseDown else {
            if dragging { endDrag() }
            baseline = board.changeCount
            return
        }
        let runtime = AppRuntime.shared
        guard runtime.wheelEnabled else { return }
        if !dragging {
            guard board.changeCount != baseline else { return }
            dragging = true
            let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            files = urls.compactMap(FileRef.load)
        }
        guard !files.isEmpty else { return }
        let flags = NSEvent.modifierFlags
        let wanted: WheelMode? = if flags.contains(.shift) {
            .convert
        } else if flags.contains(.command) {
            .tools
        } else if flags.contains(.control) {
            .actions
        } else {
            nil
        }
        guard let wanted, wanted != mode, let session = runtime.session(wanted, files: files) else { return }
        mode = wanted
        runtime.globalHighlight = nil
        runtime.globalWheel = session
        if !GlobalWheel.shared.isVisible {
            GlobalWheel.shared.show(at: NSEvent.mouseLocation)
        }
    }

    private func endDrag() {
        dragging = false
        files = []
        mode = nil
        if GlobalWheel.shared.isVisible {
            GlobalWheel.shared.hide(after: 0.35)
        }
    }
}
