import AppKit
import Foundation
import ServiceManagement

/// The only system permissions Orange asks for. Folder access is requested by macOS itself the
/// first time Orange touches a protected folder; this asks on the user's terms, one folder at a time.
enum ProtectedFolder: String, CaseIterable, Identifiable {
    case desktop, documents, downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: L("Desktop", "Masaüstü")
        case .documents: L("Documents", "Belgeler")
        case .downloads: L("Downloads", "İndirilenler")
        }
    }

    var symbol: String {
        switch self {
        case .desktop: "menubar.dock.rectangle"
        case .documents: "doc.on.doc"
        case .downloads: "arrow.down.circle"
        }
    }

    var reason: String {
        switch self {
        case .desktop: L("Save converted copies next to files on your Desktop.", "Masaüstündeki dosyaların dönüştürülmüş kopyalarını yanlarına kaydetmek için.")
        case .documents: L("Save results next to files in Documents.", "Belgeler’deki dosyaların sonuçlarını yanlarına kaydetmek için.")
        case .downloads: L("Save link downloads, and results when the original folder is read-only.", "Link indirmelerini ve orijinal klasör yazılamazsa sonuçları kaydetmek için.")
        }
    }

    var url: URL {
        let directory: FileManager.SearchPathDirectory = switch self {
        case .desktop: .desktopDirectory
        case .documents: .documentDirectory
        case .downloads: .downloadsDirectory
        }
        return FileManager.default.urls(for: directory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
}

enum FolderAccess: String {
    case unknown, granted, denied
}

@MainActor
@Observable
final class Permissions {
    static let shared = Permissions()

    private(set) var folders: [ProtectedFolder: FolderAccess] = [:]
    private(set) var checking: Set<ProtectedFolder> = []
    private(set) var loginItem: SMAppService.Status = SMAppService.mainApp.status
    var loginItemError: String?

    private let defaults = UserDefaults.standard

    private init() {
        for folder in ProtectedFolder.allCases {
            let stored = defaults.string(forKey: key(folder)).flatMap(FolderAccess.init(rawValue:))
            folders[folder] = stored ?? .unknown
        }
    }

    func access(_ folder: ProtectedFolder) -> FolderAccess {
        folders[folder] ?? .unknown
    }

    /// Reads the folder listing, which makes macOS show its consent prompt the first time.
    /// Later calls never prompt again; they only report the current answer.
    func request(_ folder: ProtectedFolder) {
        guard !checking.contains(folder) else { return }
        checking.insert(folder)
        let path = folder.url.path
        Task {
            let granted = await Task.detached(priority: .userInitiated) {
                (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
            }.value
            checking.remove(folder)
            let state: FolderAccess = granted ? .granted : .denied
            folders[folder] = state
            defaults.set(state.rawValue, forKey: key(folder))
        }
    }

    func requestAll() {
        for folder in ProtectedFolder.allCases where access(folder) != .granted {
            request(folder)
        }
    }

    func openPrivacySettings() {
        let link = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    // MARK: Login item

    var opensAtLogin: Bool {
        loginItem == .enabled || loginItem == .requiresApproval
    }

    func setOpensAtLogin(_ enabled: Bool) {
        loginItemError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
        }
        loginItem = SMAppService.mainApp.status
    }

    func refreshLoginItem() {
        loginItem = SMAppService.mainApp.status
    }

    private func key(_ folder: ProtectedFolder) -> String {
        "folderAccess.\(folder.rawValue)"
    }
}

/// What the user agreed to, versioned so a changed policy can be shown again.
enum Consent {
    static let currentVersion = 2
    static let privacyURL = URL(string: "https://github.com/MachineX41/Orange-App/blob/main/PRIVACY.md")!
    static let termsURL = URL(string: "https://github.com/MachineX41/Orange-App/blob/main/TERMS.md")!

    static var accepted: Bool {
        UserDefaults.standard.integer(forKey: "consentVersion") >= currentVersion
    }

    static var acceptedAt: Date? {
        UserDefaults.standard.object(forKey: "consentAcceptedAt") as? Date
    }

    static func accept() {
        UserDefaults.standard.set(currentVersion, forKey: "consentVersion")
        UserDefaults.standard.set(Date(), forKey: "consentAcceptedAt")
    }
}
