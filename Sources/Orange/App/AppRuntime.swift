import AppKit
import OrangeKit
import SwiftUI
import UniformTypeIdentifiers

struct Toast: Identifiable, Equatable {
    enum Style { case success, failure, info }

    let id = UUID()
    var title: String
    var message: String
    var symbol: String
    var style: Style
    var outputs: [URL] = []
}

@MainActor
@Observable
final class AppRuntime {
    static let shared = AppRuntime()

    // MARK: State

    var section: AppSection = .home
    var selection: [FileRef] = []
    var jobs: [JobRecord] = []
    var progress: [UUID: Double] = [:]
    var shelf: [FileRef] = []
    var toasts: [Toast] = []

    var globalWheel: WheelSession?
    var globalHighlight: Int?
    var localWheel: WheelSession?

    var appearance: AppearanceChoice { didSet { save() } }
    var revealWhenDone: Bool { didSet { save() } }
    var soundOnDone: Bool { didSet { save() } }
    var hapticOnWheel: Bool { didSet { save() } }
    var wheelEnabled: Bool { didSet { save() } }
    var imageQuality: Double { didSet { save() } }
    var customOutputPath: String? {
        didSet {
            OutputLocation.customDirectory = customOutputPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            save()
        }
    }

    var running: [JobRecord] { jobs.filter { $0.state == .running } }

    var recentOutputs: [URL] {
        var seen = Set<String>()
        return jobs.lazy
            .filter { $0.state == .success }
            .flatMap(\.outputPaths)
            .filter { FileManager.default.fileExists(atPath: $0) && seen.insert($0).inserted }
            .prefix(12)
            .map { URL(fileURLWithPath: $0) }
    }

    private let store = LibraryStore()
    private let defaults = UserDefaults.standard
    private var loading = true

    private init() {
        let defaults = UserDefaults.standard
        appearance = AppearanceChoice(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        revealWhenDone = defaults.object(forKey: "revealWhenDone") as? Bool ?? false
        soundOnDone = defaults.object(forKey: "soundOnDone") as? Bool ?? true
        hapticOnWheel = defaults.object(forKey: "hapticOnWheel") as? Bool ?? true
        wheelEnabled = defaults.object(forKey: "wheelEnabled") as? Bool ?? true
        imageQuality = defaults.object(forKey: "imageQuality") as? Double ?? 0.88
        customOutputPath = defaults.string(forKey: "customOutputPath")
        OutputLocation.customDirectory = customOutputPath.map { URL(fileURLWithPath: $0, isDirectory: true) }

        let snapshot = store.load()
        jobs = snapshot.jobs.map { job in
            guard job.state == .running else { return job }
            var copy = job
            copy.state = .failure
            copy.detail = L("Interrupted", "Yarıda kaldı")
            return copy
        }
        shelf = snapshot.shelf.compactMap { FileRef.load(URL(fileURLWithPath: $0)) }
        loading = false
    }

    private func save() {
        guard !loading else { return }
        defaults.set(appearance.rawValue, forKey: "appearance")
        defaults.set(revealWhenDone, forKey: "revealWhenDone")
        defaults.set(soundOnDone, forKey: "soundOnDone")
        defaults.set(hapticOnWheel, forKey: "hapticOnWheel")
        defaults.set(wheelEnabled, forKey: "wheelEnabled")
        defaults.set(imageQuality, forKey: "imageQuality")
        defaults.set(customOutputPath, forKey: "customOutputPath")
    }

    private func persist() {
        store.save(LibrarySnapshot(jobs: Array(jobs.prefix(300)), shelf: shelf.map(\.path)))
    }

    // MARK: Selection

    func importURLs(_ urls: [URL]) {
        let files = urls.compactMap(FileRef.load)
        guard !files.isEmpty else { return }
        var merged = selection
        for file in files where !merged.contains(file) { merged.append(file) }
        selection = merged
        section = .home
    }

    func replaceSelection(_ urls: [URL]) {
        selection = urls.compactMap(FileRef.load)
    }

    func remove(_ file: FileRef) {
        selection.removeAll { $0 == file }
    }

    func chooseFiles(kinds: Set<MediaKind>? = nil, multiple: Bool = true) async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple
        if let kinds {
            panel.allowedContentTypes = kinds.flatMap(Self.contentTypes)
        }
        let response = await panel.begin()
        return response == .OK ? panel.urls : []
    }

    static func contentTypes(_ kind: MediaKind) -> [UTType] {
        switch kind {
        case .image: [.image]
        case .video: [.movie, .video]
        case .audio: [.audio]
        case .pdf: [.pdf]
        case .document: [.plainText, .rtf, .html, UTType("org.openxmlformats.wordprocessingml.document"), UTType("org.oasis-open.opendocument.text")].compactMap { $0 }
        case .archive: [.archive, .zip]
        case .other: [.data]
        }
    }

    func openFiles() {
        Task {
            let urls = await chooseFiles()
            importURLs(urls)
        }
    }

    func useSample() {
        do {
            importURLs([try SampleMaker.write()])
        } catch {
            notify(error)
        }
    }

    @ObservationIgnored var openWindowAction: OpenWindowAction?

    func showMainWindow() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            openWindowAction?(id: "main")
        }
    }

    // MARK: Wheel

    func choices(_ mode: WheelMode, files: [FileRef]) -> [WheelChoice] {
        let urls = files.map(\.url)
        switch mode {
        case .convert:
            let targets = Catalog.commonConvertTargets(for: urls)
            return targets.prefix(10).map {
                WheelChoice(id: "c-\($0.rawValue)", title: $0.title, symbol: $0.symbol, payload: .convert($0))
            }
        case .tools:
            let tools = Catalog.commonTools(for: urls)
            var list = tools.prefix(tools.count > 8 ? 7 : 8).map {
                WheelChoice(id: "t-\($0.rawValue)", title: $0.title, symbol: $0.symbol, payload: .tool($0))
            }
            if tools.count > 8 {
                list.append(WheelChoice(id: "more", title: L("More", "Diğer"), symbol: "ellipsis", payload: .more))
            }
            return list
        case .actions:
            return ActionID.allCases.map {
                WheelChoice(id: "a-\($0.rawValue)", title: $0.title, symbol: $0.symbol, payload: .action($0))
            }
        }
    }

    func session(_ mode: WheelMode, files: [FileRef]) -> WheelSession? {
        let list = choices(mode, files: files)
        guard !files.isEmpty, !list.isEmpty else { return nil }
        return WheelSession(mode: mode, files: files, choices: list)
    }

    func presentLocalWheel(_ mode: WheelMode) {
        guard !selection.isEmpty else { return notify(OrangeError.empty) }
        guard let session = session(mode, files: selection) else {
            return toast(L("Nothing to offer", "Seçenek yok"), L("These files don’t share a format.", "Bu dosyaların ortak biçimi yok."), symbol: "exclamationmark.circle", style: .info)
        }
        localWheel = session
    }

    func setGlobalHighlight(_ index: Int?) {
        guard index != globalHighlight else { return }
        if hapticOnWheel, index != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        globalHighlight = index
    }

    func commit(_ choice: WheelChoice, files: [FileRef]) {
        localWheel = nil
        switch choice.payload {
        case .convert(let target): convert(files, to: target)
        case .tool(let tool): open(tool, files: files)
        case .action(let action): perform(action, files: files)
        case .more:
            selection = files
            section = .home
            showMainWindow()
        }
    }

    // MARK: Tools

    func open(_ tool: ToolID, files: [FileRef]) {
        let usable = files.filter { tool.kinds.contains($0.kind) }
        guard !usable.isEmpty else {
            return toast(tool.title, L("These files can’t be used with this tool.", "Bu dosyalar bu araçla kullanılamaz."), symbol: tool.symbol, style: .failure)
        }
        guard usable.count >= tool.minimumFiles else {
            return toast(tool.title, L("Choose at least \(tool.minimumFiles) files.", "En az \(tool.minimumFiles) dosya seçin."), symbol: tool.symbol, style: .info)
        }
        let urls = usable.map(\.url)
        switch tool {
        case .removeBackground:
            runEach(urls, title: tool.title, symbol: tool.symbol) { url, _ in
                let cutout = try BackgroundRemover.cutout(ImageEngine.load(url))
                return [try ImageEngine.save(cutout, from: url, suffix: L("Cutout", "Kesik"), format: .png)]
            }
        case .imagesToPDF:
            run(tool.title, symbol: tool.symbol, detail: L("\(urls.count) images", "\(urls.count) görsel")) { _ in
                [try PDFToolkit.imagesToPDF(sources: urls, into: OutputLocation.directory(beside: urls[0]))]
            }
        case .compressPDF:
            runEach(urls, title: tool.title, symbol: tool.symbol) { url, _ in
                [try PDFToolkit.compress(url: url)]
            }
        case .muteVideo:
            runEach(urls, title: tool.title, symbol: tool.symbol) { url, progress in
                [try await VideoEditor.mute(url, progress: progress)]
            }
        case .unzip:
            runEach(urls, title: tool.title, symbol: tool.symbol) { url, _ in
                [try ArchiveToolkit.extract(archive: url, into: OutputLocation.directory(beside: url))]
            }
        default:
            let route = tool.acceptsMany || tool.minimumFiles > 1 ? urls : [urls[0]]
            EditorWindows.shared.present(tool, files: route)
        }
    }

    func request(_ tool: ToolID) {
        let matching = selection.filter { tool.kinds.contains($0.kind) }
        if matching.count >= tool.minimumFiles, !matching.isEmpty {
            open(tool, files: matching)
            return
        }
        Task {
            let urls = await chooseFiles(kinds: tool.kinds, multiple: tool.acceptsMany || tool.minimumFiles > 1)
            let files = urls.compactMap(FileRef.load)
            guard !files.isEmpty else { return }
            open(tool, files: files)
        }
    }

    func convert(_ files: [FileRef], to target: ConvertTarget) {
        let quality = imageQuality
        runEach(files.map(\.url), title: L("Convert to \(target.title)", "\(target.title) biçimine dönüştür"), symbol: target.symbol) { url, progress in
            try await ConversionRouter.convert(url, to: target, quality: quality, progress: progress)
        }
    }

    // MARK: Actions

    func perform(_ action: ActionID, files: [FileRef]) {
        let urls = files.map(\.url)
        switch action {
        case .float:
            for file in files where !shelf.contains(file) { shelf.insert(file, at: 0) }
            persist()
            FloatShelf.shared.show()
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(urls as [NSURL])
            toast(L("Copied", "Kopyalandı"), L("\(urls.count) item(s) on the clipboard", "\(urls.count) öğe panoda"), symbol: action.symbol, style: .info)
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            toast(L("Path copied", "Yol kopyalandı"), urls.first?.lastPathComponent ?? "", symbol: action.symbol, style: .info)
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .airDrop:
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
                return toast("AirDrop", L("AirDrop isn’t available right now.", "AirDrop şu an kullanılamıyor."), symbol: action.symbol, style: .failure)
            }
            NSApp.activate()
            service.perform(withItems: urls)
        case .zip:
            run(action.title, symbol: action.symbol, detail: L("\(urls.count) item(s)", "\(urls.count) öğe")) { _ in
                [try ArchiveToolkit.zip(urls: urls, into: OutputLocation.directory(beside: urls[0]))]
            }
        case .duplicate:
            runEach(urls, title: action.title, symbol: action.symbol) { url, _ in
                let copy = UniqueDestination.url(
                    in: url.deletingLastPathComponent(),
                    baseName: url.deletingPathExtension().lastPathComponent,
                    extension: url.pathExtension
                )
                try FileManager.default.copyItem(at: url, to: copy)
                return [copy]
            }
        case .move:
            Task { await move(urls) }
        case .openTerminal:
            let folder = urls[0].hasDirectoryPath ? urls[0] : urls[0].deletingLastPathComponent()
            if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    private func move(_ urls: [URL]) async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L("Move Here", "Buraya Taşı")
        NSApp.activate()
        guard await panel.begin() == .OK, let folder = panel.url else { return }
        runEach(urls, title: ActionID.move.title, symbol: ActionID.move.symbol) { url, _ in
            let target = UniqueDestination.url(
                in: folder,
                baseName: url.deletingPathExtension().lastPathComponent,
                extension: url.pathExtension
            )
            try FileManager.default.moveItem(at: url, to: target)
            return [target]
        }
        selection.removeAll { file in urls.contains(file.url) }
    }

    func removeFromShelf(_ file: FileRef) {
        shelf.removeAll { $0 == file }
        persist()
    }

    func clearShelf() {
        shelf.removeAll()
        persist()
    }

    func clearHistory() {
        jobs.removeAll { $0.state != .running }
        persist()
    }

    // MARK: Jobs

    @discardableResult
    func run(
        _ title: String,
        symbol: String,
        detail: String = "",
        work: @escaping @Sendable (@escaping ProgressHandler) async throws -> [URL]
    ) -> Task<[URL], Never> {
        let id = UUID()
        jobs.insert(JobRecord(id: id, title: title, detail: detail.isEmpty ? L("Working…", "İşleniyor…") : detail, symbol: symbol, createdAt: .now, state: .running, outputPaths: []), at: 0)
        progress[id] = 0
        ActivityHUD.shared.refresh()
        let report: ProgressHandler = { value in
            Task { @MainActor in
                let runtime = AppRuntime.shared
                guard let current = runtime.progress[id], value - current >= 0.01 || value >= 1 else { return }
                runtime.progress[id] = min(max(value, 0), 1)
            }
        }
        return Task {
            do {
                let outputs = try await Task.detached(priority: .userInitiated) { try await work(report) }.value
                finish(id, outputs: outputs, title: title, symbol: symbol)
                return outputs
            } catch {
                fail(id, error: error, title: title)
                return []
            }
        }
    }

    func runEach(
        _ urls: [URL],
        title: String,
        symbol: String,
        work: @escaping @Sendable (URL, @escaping ProgressHandler) async throws -> [URL]
    ) {
        if urls.count == 1, let url = urls.first {
            run(title, symbol: symbol, detail: url.lastPathComponent) { progress in try await work(url, progress) }
            return
        }
        run(title, symbol: symbol, detail: L("\(urls.count) files", "\(urls.count) dosya")) { progress in
            var outputs: [URL] = []
            var firstError: Error?
            for (index, url) in urls.enumerated() {
                try Task.checkCancellation()
                do {
                    outputs += try await work(url) { value in progress((Double(index) + value) / Double(urls.count)) }
                } catch {
                    firstError = firstError ?? error
                }
                progress(Double(index + 1) / Double(urls.count))
            }
            if outputs.isEmpty, let firstError { throw firstError }
            return outputs
        }
    }

    private func finish(_ id: UUID, outputs: [URL], title: String, symbol: String) {
        progress[id] = nil
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            jobs[index].state = .success
            jobs[index].outputPaths = outputs.map(\.path)
            jobs[index].detail = outputs.count == 1 ? outputs[0].lastPathComponent : L("\(outputs.count) files", "\(outputs.count) dosya")
        }
        persist()
        if soundOnDone { NSSound(named: "Glass")?.play() }
        if revealWhenDone, !outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
        toast(title, outputs.count == 1 ? outputs[0].lastPathComponent : L("\(outputs.count) files ready", "\(outputs.count) dosya hazır"), symbol: "checkmark.circle.fill", style: .success, outputs: outputs)
    }

    private func fail(_ id: UUID, error: Error, title: String) {
        progress[id] = nil
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            jobs[index].state = .failure
            jobs[index].detail = error.orangeMessage
        }
        persist()
        if soundOnDone { NSSound(named: "Basso")?.play() }
        toast(title, error.orangeMessage, symbol: "exclamationmark.triangle.fill", style: .failure)
    }

    // MARK: Toasts

    func toast(_ title: String, _ message: String, symbol: String, style: Toast.Style, outputs: [URL] = []) {
        let toast = Toast(title: title, message: message, symbol: symbol, style: style, outputs: outputs)
        toasts.append(toast)
        if toasts.count > 3 { toasts.removeFirst(toasts.count - 3) }
        ActivityHUD.shared.refresh()
        Task {
            try? await Task.sleep(for: .seconds(style == .failure ? 6 : 4))
            dismiss(toast)
        }
    }

    func notify(_ error: Error) {
        toast(L("Orange", "Orange"), error.orangeMessage, symbol: "exclamationmark.triangle.fill", style: .failure)
    }

    func dismiss(_ toast: Toast) {
        toasts.removeAll { $0.id == toast.id }
        ActivityHUD.shared.refresh()
    }
}