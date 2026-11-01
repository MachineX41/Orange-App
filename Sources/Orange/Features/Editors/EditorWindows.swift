import AppKit
import OrangeKit
import SwiftUI

struct EditorContext {
    var tool: ToolID
    var files: [URL]
    var close: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    @Entry var editor = EditorContext(tool: .metadata, files: [])
}

/// Each editor lives in its own AppKit window so several can be open next to the main window.
@MainActor
final class EditorWindows: NSObject, NSWindowDelegate {
    static let shared = EditorWindows()

    private struct HostedEditor {
        var window: NSWindow
        var tool: ToolID
        var files: [URL]
    }

    private var editors: [HostedEditor] = []

    func present(_ tool: ToolID, files: [URL]) {
        let key = tool.rawValue + "|" + files.map(\.path).joined(separator: "|")
        if let existing = editors.first(where: { $0.window.identifier?.rawValue == key }) {
            bringForward(existing.window)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(key)
        window.title = tool.windowTitle
        window.subtitle = files.count == 1 ? files[0].lastPathComponent : L("\(files.count) files", "\(files.count) dosya")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 560)
        window.delegate = self
        window.tabbingMode = .disallowed

        let context = EditorContext(tool: tool, files: files) { [weak window] in window?.close() }
        let root = EditorRoot()
            .environment(\.editor, context)
            .environment(AppRuntime.shared)
            .preferredColorScheme(AppRuntime.shared.appearance.colorScheme)
            .tint(OrangeTheme.accent)
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(NSSize(width: 1080, height: 720))
        if let main = NSApp.mainWindow ?? NSApp.keyWindow, main.isVisible {
            window.setFrameTopLeftPoint(NSPoint(x: main.frame.minX + 36, y: main.frame.maxY - 36))
        } else {
            window.center()
        }
        editors.append(HostedEditor(window: window, tool: tool, files: files))
        bringForward(window)
    }

    func applyLanguage() {
        for editor in editors {
            editor.window.title = editor.tool.windowTitle
            editor.window.subtitle = editor.files.count == 1
                ? editor.files[0].lastPathComponent
                : L("\(editor.files.count) files", "\(editor.files.count) dosya")
        }
    }

    /// Drops onto the nonactivating wheel come from another app, so activation alone may be refused.
    private func bringForward(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        editors.removeAll { $0.window === window }
    }
}

struct EditorRoot: View {
    @Environment(\.editor) private var editor

    var body: some View {
        ZStack {
            OrangeBackdrop()
            content
        }
        .frame(minWidth: 860, minHeight: 560)
    }

    @ViewBuilder private var content: some View {
        let files = editor.files
        switch editor.tool {
        case .adjustImage: AdjustEditor(url: files[0])
        case .cropImage, .rotateImage: CropEditor(url: files[0])
        case .compressImage: CompressImagesEditor(urls: files)
        case .annotateImage: AnnotateEditor(url: files[0])
        case .redactImage: RedactImageEditor(url: files[0])
        case .addBackground: BackdropEditor(url: files[0])
        case .resizeImage: ResizeEditor(url: files[0])
        case .collage: CollageEditor(urls: files)
        case .metadata: MetadataEditor(url: files[0])
        case .readQR: CodeReaderEditor(urls: files)
        case .mergePDF: MergePDFEditor(urls: files)
        case .splitPDF: SplitPDFEditor(url: files[0])
        case .organizePDF: OrganizePDFEditor(url: files[0])
        case .trimVideo: TrimVideoEditor(url: files[0])
        case .cropVideo: CropVideoEditor(url: files[0])
        case .compressVideo: CompressVideoEditor(urls: files)
        case .videoSpeed: SpeedEditor(url: files[0])
        case .videoFrames: FramesEditor(url: files[0])
        case .splitVideo: SplitVideoEditor(url: files[0])
        case .redactVideo: RedactVideoEditor(url: files[0])
        case .joinVideos: JoinVideosEditor(urls: files)
        case .trimAudio: TrimAudioEditor(url: files[0])
        case .audioChannels: ChannelsEditor(url: files[0])
        case .bleepAudio: BleepEditor(url: files[0])
        case .normalizeAudio: LevelEditor(urls: files)
        case .audioToVideo: AudioToVideoEditor(url: files[0])
        case .removeBackground, .imagesToPDF, .compressPDF, .muteVideo, .unzip:
            EmptyHint(symbol: editor.tool.symbol, title: editor.tool.title, message: "")
        }
    }
}
