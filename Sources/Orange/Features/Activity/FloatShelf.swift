import AppKit
import OrangeKit
import SwiftUI

/// Always-on-top shelf for parking files while moving between apps. One liquid-glass vessel, like the drop container.
@MainActor
final class FloatShelf {
    static let shared = FloatShelf()
    fileprivate static let size = NSSize(width: 132, height: 460)
    fileprivate static let radius: CGFloat = 30

    private var panelStorage: NSPanel?
    /// Card and button frames, in the shelf’s top-left coordinates, that must keep their own click or file drag.
    fileprivate var interactiveFrames: [CGRect] = []

    private var panel: NSPanel {
        if let panelStorage { return panelStorage }
        let created = makePanel()
        panelStorage = created
        return created
    }

    private func defaultOrigin() -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else { return NSPoint(x: 40, y: 80) }
        return NSPoint(x: visible.maxX - Self.size.width - 18, y: visible.midY - Self.size.height / 2)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: defaultOrigin(), size: Self.size),
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
            var frame = panel.frame
            frame.size = Self.size
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame.insetBy(dx: 20, dy: 20)) }) {
                frame.origin = defaultOrigin()
            }
            panel.setFrame(frame, display: false)
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
}

struct FloatShelfView: View {
    @Environment(AppRuntime.self) private var runtime
    @State var targeted = false

    var body: some View {
        VStack(spacing: 10) {
            header
            if runtime.shelf.isEmpty {
                empty
            } else {
                files
            }
        }
        .padding(10)
        .frame(width: FloatShelf.size.width, height: FloatShelf.size.height)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: FloatShelf.radius, style: .continuous))
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

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "tray.full")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
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

    private var files: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(runtime.shelf) { file in
                        VStack(spacing: 4) {
                            FileThumbnail(url: file.url, side: 72, radius: 12)
                            Text(file.name)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
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
                }
                .padding(1)
            }
            .scrollIndicators(.never)
            Button(L("Clear", "Temizle")) { runtime.clearShelf() }
                .buttonStyle(.glass).tint(nil)
                .controlSize(.small)
                .shelfInteractive()
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
        } else {
            window?.performDrag(with: event)
        }
    }
}

private struct ShelfInteractiveFrames: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private extension View {
    func shelfInteractive() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: ShelfInteractiveFrames.self, value: [proxy.frame(in: .named("shelf"))])
            }
        }
    }
}
