import AppKit
import Darwin

/// Offers to move Orange into /Applications when it was opened from a disk image or Downloads.
/// Apps opened from there run translocated from a random read-only path, which breaks login items and updates.
@MainActor
enum AppMover {
    private static let skipKey = "skipMoveToApplications"

    static func offerIfNeeded() {
        #if DEBUG
        return
        #else
        let current = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard !isInApplications(current), !UserDefaults.standard.bool(forKey: skipKey) else { return }
        let source = originalURL(of: current) ?? current

        let alert = NSAlert()
        alert.messageText = L("Move Orange to the Applications folder?", "Orange Uygulamalar klasörüne taşınsın mı?")
        alert.informativeText = L(
            "Orange is running from a disk image or the Downloads folder. In that location macOS runs it from a temporary copy, so the wheel, permissions and login item may not work reliably.",
            "Orange bir disk görüntüsünden ya da İndirilenler klasöründen çalışıyor. macOS bu durumda uygulamayı geçici bir kopyadan açar; çark, izinler ve girişte açılma güvenilir çalışmayabilir."
        )
        alert.addButton(withTitle: L("Move to Applications", "Uygulamalar’a Taşı"))
        alert.addButton(withTitle: L("Not Now", "Şimdi Değil"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L("Don’t ask again", "Bir daha sorma")
        NSApp.activate()
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: skipKey) }
        guard response == .alertFirstButtonReturn else { return }

        do {
            let destination = try install(source)
            relaunch(destination)
        } catch {
            let failure = NSAlert(error: error)
            failure.informativeText = L(
                "Drag Orange from the disk image into the Applications folder in Finder, then open it from there.",
                "Orange’ı Finder’da disk görüntüsünden Uygulamalar klasörüne sürükleyin ve oradan açın."
            )
            failure.runModal()
        }
        #endif
    }

    private static func isInApplications(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return parent == "/Applications" || parent.hasPrefix("/Applications/") || parent == home || parent.hasPrefix(home + "/")
    }

    /// Resolves the real location of a translocated bundle, e.g. the copy inside the mounted disk image.
    private static func originalURL(of url: URL) -> URL? {
        guard url.path.contains("/AppTranslocation/"),
              let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        typealias Resolve = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let resolve = unsafeBitCast(symbol, to: Resolve.self)
        return resolve(url as CFURL, nil)?.takeRetainedValue() as URL?
    }

    private static func install(_ source: URL) throws -> URL {
        let manager = FileManager.default
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)
        if manager.fileExists(atPath: destination.path) {
            try manager.trashItem(at: destination, resultingItemURL: nil)
        }
        try manager.copyItem(at: source, to: destination)
        clearQuarantine(destination)
        return destination
    }

    /// The person already approved this copy in Gatekeeper; without this the installed copy would be translocated again.
    private static func clearQuarantine(_ url: URL) {
        let attribute = "com.apple.quarantine"
        removexattr(url.path, attribute, XATTR_NOFOLLOW)
        guard let items = FileManager.default.enumerator(atPath: url.path) else { return }
        for case let item as String in items {
            removexattr(url.appendingPathComponent(item).path, attribute, XATTR_NOFOLLOW)
        }
    }

    private static func relaunch(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
