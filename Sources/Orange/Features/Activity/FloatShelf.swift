import AppKit
import OrangeKit
import SwiftUI

/// Always-on-top glass shelf for parking files while moving between apps.
@MainActor
final class FloatShelf {
    static let shared = FloatShelf()

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 132, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: FloatShelfView().environment(AppRuntime.shared))
        host.sizingOptions = []
        panel.contentView = host
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 150, y: frame.midY - 230))
        }
        return panel
    }()

    var isVisible: Bool { panel.isVisible }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
    func toggle() { isVisible ? hide() : show() }
}

struct FloatShelfView: View {
    @Environment(AppRuntime.self) private var runtime
    @State var targeted = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "tray.full")
                    .foregroundStyle(OrangeTheme.accent)
                Spacer()
                Button {
                    FloatShelf.shared.hide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.glass).tint(nil)
                .buttonBorderShape(.circle)
                .controlSize(.mini)
            }
            .padding(.horizontal, 4)

            if runtime.shelf.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 22, weight: .light))
                    Text(L("Drop files here", "Dosyaları buraya bırakın"))
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(runtime.shelf) { file in
                            VStack(spacing: 4) {
                                FileThumbnail(url: file.url, side: 72, radius: 12)
                                Text(file.name)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(width: 96)
                            .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
                            .contextMenu {
                                Button(L("Reveal in Finder", "Finder’da Göster")) {
                                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                                }
                                Button(L("Remove", "Kaldır")) { runtime.removeFromShelf(file) }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                Button(L("Clear", "Temizle")) { runtime.clearShelf() }
                    .buttonStyle(.glass).tint(nil)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 120, height: 440)
        .glassEffect(.regular.tint(targeted ? OrangeTheme.accent.opacity(0.4) : nil), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(6)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.compactMap(FileRef.load)
            for file in files where !runtime.shelf.contains(file) { runtime.shelf.insert(file, at: 0) }
            runtime.perform(.float, files: [])
            return !files.isEmpty
        } isTargeted: { targeted = $0 }
    }
}
