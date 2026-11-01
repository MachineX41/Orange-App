import AppKit
import OrangeKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRuntime.shared.applyInterfaceAppearance()
        if Consent.accepted { DragWatcher.shared.start() }
        NSApp.activate()
        DispatchQueue.main.async { AppMover.offerIfNeeded() }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppRuntime.shared.applyInterfaceAppearance()
            }
        }
        #if DEBUG
        runDemoIfRequested()
        #endif
    }

    /// The system Settings item's key changes with the macOS language (⌘Ö in Turkish), so it is read rather than assumed.
    static var settingsKey: String {
        let items = NSApp.mainMenu?.items.first?.submenu?.items ?? []
        let key = items.prefix { $0.submenu == nil }.first { !$0.keyEquivalent.isEmpty }?.keyEquivalent ?? ""
        return key.isEmpty ? "," : key.uppercased()
    }

    #if DEBUG
    /// `ORANGE_DEMO=wheel:<mode>:<path>` shows the global wheel, `ORANGE_DEMO=tool:<id>:<path>[,<path>]` opens an editor.
    private func runDemoIfRequested() {
        guard let demo = ProcessInfo.processInfo.environment["ORANGE_DEMO"] else { return }
        let parts = demo.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return }
        let urls = parts[2].split(separator: ",").map { URL(fileURLWithPath: String($0)) }
        let files = urls.compactMap(FileRef.load)
        let runtime = AppRuntime.shared
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            switch parts[0] {
            case "wheel":
                guard let mode = WheelMode(rawValue: parts[1]), let session = runtime.session(mode, files: files) else { return }
                runtime.globalWheel = session
                runtime.globalHighlight = 1
                if let screen = NSScreen.main { GlobalWheel.shared.show(at: NSPoint(x: screen.frame.midX, y: screen.frame.midY)) }
            case "tool":
                guard let tool = ToolID(rawValue: parts[1]) else { return }
                runtime.open(tool, files: files)
            case "select":
                runtime.importURLs(urls)
            case "toast":
                runtime.toast(parts[1], urls.first?.lastPathComponent ?? "", symbol: "checkmark.circle.fill", style: .info)
            default:
                break
            }
        }
    }
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppRuntime.shared.showMainWindow() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppRuntime.shared.importURLs(urls)
        AppRuntime.shared.showMainWindow()
    }
}
